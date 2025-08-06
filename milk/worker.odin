package milk

import "core:fmt"
import "core:os"
import "core:mem"
import "core:sync"
import "core:thread"
import "core:time"

Worker_Pool :: struct {
    allocator: mem.Allocator,
    mutex: sync.Mutex,

    is_running: bool,

    threads: []^thread.Thread,

    // Timestep
    prev_time: time.Tick,
    frame_duration: f64,

    // Scheduling
    schedule_list: []Schedule,
    active_indices: [dynamic]int,
    // The index of the schedule we're currently tracking.
    schedule_index: int,
    // The index of the next available task within the schedule we're currently tracking.
    task_index: int,
    // Whether we've finished reading through tasks.
    out_of_tasks: bool,
    job_list: [dynamic]Task,
    tasks_done: map[typeid]struct {},
    // A counter of tasks in progress
    tasks_in_progress: int,
    // A counter of jobs in progress
    jobs_in_progress: int,
    // The maximum amount of jobs in progress
    max_jobs: int,

    // Sync
    sync: sync.Barrier,
}

worker_pool_new :: proc(pool: ^Worker_Pool, allocator: mem.Allocator, thread_count: int) {
    context.allocator = allocator
    pool.allocator = allocator
    pool.tasks_done = {}
    pool.threads = make([]^thread.Thread, max(thread_count, 1))
    pool.max_jobs = os.processor_core_count() / 4
    pool.prev_time = time.tick_now()

    pool.is_running = true
    sync.barrier_init(&pool.sync, thread_count + 1)

    for _, i in pool.threads {
        t := thread.create(worker_thread_proc)
        data := new(Worker_Thread_Data)
        data.pool = pool
        t.user_index = i
        t.data = data
        t.creation_allocator = allocator
        pool.threads[i] = t
    }
}

worker_pool_destroy :: proc(pool: ^Worker_Pool) {
    delete(pool.task_slice)
    delete(pool.tasks_done)

    for &t in pool.threads {
        data := cast(^Worker_Thread_Data)t.data
        free(data, pool.allocator)
        thread.destroy(t)
    }

    delete(pool.threads, pool.allocator)
}

worker_pool_start :: proc(pool: ^Worker_Pool) {
    for t in pool.threads {
        thread.start(t)
    }
}

worker_pool_join :: proc(pool: ^Worker_Pool) {
    sync.atomic_store(&pool.is_running, false)

    // The pool is no longer running, so clear the queue and if threads are still waiting stop them
    pool.task_slice = {}

    // Wait for start
    sync.barrier_wait(&pool.sync)

    // Wait for end
    sync.barrier_wait(&pool.sync)

    thread.yield()

    started_count: int
    for started_count < len(pool.threads) {
        started_count = 0
        for t in pool.threads {
            flags := sync.atomic_load(&t.flags)
            if .Started in flags {
                started_count += 1
                if .Joined not_in flags {
                    thread.join(t)
                }
            }
        }
    }
}

worker_pool_init_schedules :: proc(pool: ^Worker_Pool, schedule_list: []Schedule) {
    sync.guard(&pool.mutex)

    pool.schedule_list = schedule_list

    pool.frame_duration = time.duration_seconds(time.tick_since(pool.prev_time))
    pool.prev_time = time.tick_now()

    // Find schedules that will run this frame.
    for &sched in pool.schedule_list {
        sched.accumulator += pool.frame_duration
    }
}

worker_pool_shutdown :: proc(pool: ^Worker_Pool, exit_code: int = 1) {
    sync.atomic_store(&pool.is_running, false)
    sync.guard(&pool.mutex)

    for t in pool.threads {
        thread.terminate(t, exit_code)

        data := cast(^Worker_Thread_Data)t.data
        if data.task.systems != nil {
            pool.tasks_done[data.task.name] = {}
            sync.atomic_sub(&pool.tasks_in_progress, 1)
        }
    }
}

// Request a new Task or Job
worker_pool_request_task :: proc(pool: ^Worker_Pool) -> (task: Task, ok: bool) {
    sync.guard(&pool.mutex)

    if len(pool.job_list) != 0 && sync.atomic_load(&pool.jobs_in_progress) < sync.atomic_load(&pool.max_jobs) {
        // Recheck to ensure availability hasn't changed from another thread.
        if sync.atomic_load(&pool.jobs_in_progress) < sync.atomic_load(&pool.max_jobs) {
            task = pool.job_list[0]
            ok = true
            unordered_remove(&pool.job_list, 0)
            sync.atomic_add(&pool.jobs_in_progress, 1)
            return
        }
    }

    // Recursively searches to find the next task with satisfied dependencies.
    check_deps :: proc(pool: ^Worker_Pool, start_index: int) -> (task: Task, ok: bool) {
        task = pool.task_slice[start_index]
        ok = true

        // Ensure any dependencies have been sufficed
        if len(task.dependencies) != 0 {
            for dep in task.dependencies {
                if dep not_in pool.tasks_done {
                    // Dependency not done yet, move to next task.
                    if len(pool.task_slice) == start_index + 1 {
                        // We've reached the end of the list, start over
                        return check_deps(pool, 0)
                    }

                    return check_deps(pool, start_index + 1)
                }
            }
        }

        // Dependencies are fulfilled or don't exist
        return task, ok
    }

    // Using task instead
    if len(pool.task_slice) != 0 {
        sync.atomic_add(&pool.tasks_in_progress, 1)
        task, ok = check_deps(pool, 0)

        if len(pool.task_slice) != 1 {
            pool.task_slice = pool.task_slice[1:]
        } else {
            pool.task_slice = {}
        }
    }

    return
}

worker_pool_clear_done :: proc(pool: ^Worker_Pool) {
    sync.guard(&pool.mutex)

    if len(pool.tasks_done) != 0 {
        clear(&pool.tasks_done)
    }

    // Clear the queue out too
    pool.task_slice = {}
}

Worker_Thread_Data :: struct {
    // Data for the thread
    // Naturally, we need the Context and the ecs.World of the context
    ctx: ^Context,
    // The prior transform data of a World, used for draw calls.
    transform_state: ^Transform_State,
    // The task we run
    task: Task,

    // The actual thread.
    thread: ^thread.Thread,
    // The thread's pool
    pool: ^Worker_Pool,
}

worker_thread_proc :: proc(t: ^thread.Thread) {
    d := (^Worker_Thread_Data)(t.data)
    pool := d.pool
    context.allocator = t.creation_allocator

    accumulator: f64

    local_command_pool = command_pool_new(&d.ctx.renderer)

    local_profiler = profiler_new()
    
    outer: for sync.atomic_load(&pool.is_running) {
        sync.barrier_wait(&pool.sync)

        inner: for task, ok := worker_pool_request_task(pool); ok; task, ok = worker_pool_request_task(pool) {
            // Run the task
            accumulator = d.ctx.timestep.accumulator

            if task.type == .Update {
                for accumulator >= d.ctx.update_fps {
                    task_run(&task, d.ctx, d.transform_state)
                    accumulator -= d.ctx.update_fps
                }
            } else {
                // We're drawing, run immediately
                task_run(&task, d.ctx, d.transform_state)
            }

            pool.tasks_done[task.name] = {}
            sync.atomic_sub(&pool.tasks_in_progress, 1)
        }

        // Out of tasks, submit command pool.
        gfx_submit_pool(&d.ctx.renderer, &local_command_pool)

        // Free temp allocations
        free_all(context.temp_allocator)
        // Wait to quit
        sync.barrier_wait(&pool.sync)
    }

    // App ending, submit profiler
    sync.mutex_lock(&d.ctx.thread_profiler_mutex)
    append(&d.ctx.thread_profilers, local_profiler)
    sync.mutex_unlock(&d.ctx.thread_profiler_mutex)

    // Delete command pool
    command_pool_destroy(&local_command_pool)
}

start_worker_thread :: proc(d: ^Worker_Thread_Data) {
    if d.thread = thread.create(worker_thread_proc); d.thread != nil {
        d.thread.init_context = context
        d.thread.data = rawptr(d)
        thread.start(d.thread)
    } else {
        fmt.println("Thread is nil!")
    }
}

stop_worker_thread :: proc(d: ^Worker_Thread_Data) {
    thread.join(d.thread)
    thread.destroy(d.thread)
}