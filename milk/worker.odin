package milk

import "core:fmt"
import "core:os"
import "core:mem"
import "core:sync"
import "core:container/queue"
import "core:thread"
import "core:time"

// Stores all the data we need for a fixed timestep loop within each worker thread
// The timestep is centralized within the context, each loop needs its own accumulator
Timestep :: struct {
    frame_duration: f64,
    alpha: f64,
}

timestep_new :: proc(prev_time: time.Tick) -> Timestep {
    return Timestep {
        frame_duration = time.duration_seconds(time.tick_since(prev_time)),
        alpha = 0.0
    }
}

Worker_Pool :: struct {
    allocator: mem.Allocator,
    mutex: sync.Mutex,
    sem_available: sync.Sema,

    // Atomic variables
    num_waiting: int,
    num_in_processing: int,
    num_outstanding: int,
    num_done: int,

    is_running: bool,

    threads: []^thread.Thread,

    tasks: queue.Queue(Task),
    tasks_done: [dynamic]Task,

    // Sync
    sync: sync.Barrier,
}

worker_pool_new :: proc(pool: ^Worker_Pool, allocator: mem.Allocator, thread_count: int) {
    context.allocator = allocator
    pool.allocator = allocator
    queue.init(&pool.tasks)
    pool.tasks_done = make([dynamic]Task)
    pool.threads = make([]^thread.Thread, max(thread_count, 1))

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
    queue.destroy(&pool.tasks)
    delete(pool.tasks_done)
    queue.clear(&pool.tasks)

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
    queue.clear(&pool.tasks)

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

worker_pool_add_task :: proc(pool: ^Worker_Pool, procedure: Task) {
    sync.guard(&pool.mutex)

    queue.push_back(&pool.tasks, procedure)
    sync.atomic_add(&pool.num_waiting, 1)
    sync.atomic_add(&pool.num_outstanding, 1)
}

worker_pool_add_module :: proc(pool: ^Worker_Pool, module: Module) {
    sync.guard(&pool.mutex)

    queue.push_back_elems(&pool.tasks, ..module.tasks[:])
    sync.atomic_add(&pool.num_waiting, len(module.tasks))
    sync.atomic_add(&pool.num_outstanding, len(module.tasks))
}

worker_pool_shutdown :: proc(pool: ^Worker_Pool, exit_code: int = 1) {
    sync.atomic_store(&pool.is_running, false)
    sync.guard(&pool.mutex)

    for t in pool.threads {
        thread.terminate(t, exit_code)

        data := cast(^Worker_Thread_Data)t.data
        if data.task.systems != nil {
            append(&pool.tasks_done, data.task)
            sync.atomic_add(&pool.num_done, 1)
            sync.atomic_sub(&pool.num_outstanding, 1)
            sync.atomic_sub(&pool.num_in_processing, 1)
        }
    }
}

worker_pool_pop_waiting :: proc(pool: ^Worker_Pool) -> (task: Task, ok: bool) {
    sync.guard(&pool.mutex)

    if queue.len(pool.tasks) != 0 {
        sync.atomic_sub(&pool.num_waiting, 1)
        sync.atomic_add(&pool.num_in_processing, 1)
        task = queue.pop_front(&pool.tasks)
        ok = true
    }

    return
}

worker_pool_pop_done :: proc(pool: ^Worker_Pool) -> (task: Task, ok: bool) {
    sync.guard(&pool.mutex)

    if len(pool.tasks_done) != 0 {
        task = pop_front(&pool.tasks_done)
        ok = true
        sync.atomic_sub(&pool.num_done, 1)
    }

    return
}

worker_pool_clear_done :: proc(pool: ^Worker_Pool) {
    sync.guard(&pool.mutex)

    if len(pool.tasks_done) != 0 {
        sync.atomic_sub(&pool.num_done, len(pool.tasks_done))
        clear(&pool.tasks_done)
    }
}

Worker_Thread_Data :: struct {
    // Data for the thread
    // Naturally, we need the Context and the ecs.World of the context
    ctx: ^Context,
    // The timestep data for our fixed timestep loop.
    timestep: ^Timestep,
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
    
    outer: for sync.atomic_load(&pool.is_running) {
        sync.barrier_wait(&pool.sync)

        for task, ok := worker_pool_pop_waiting(pool); ok; task, ok = worker_pool_pop_waiting(pool) {
            // Run the task
            accumulator += d.timestep.frame_duration

            if task.type == .Update {
                for accumulator > d.ctx.update_fps {
                    task_run(&task, d.ctx, d.ctx.update_fps, d.transform_state)
                    accumulator -= d.ctx.update_fps
                }
            } else {
                // We're drawing, run immediately
                task_run(&task, d.ctx, d.ctx.update_fps, d.transform_state)
            }

            append(&pool.tasks_done, task)
            sync.atomic_add(&pool.num_done, 1)
            sync.atomic_sub(&pool.num_outstanding, 1)
            sync.atomic_sub(&pool.num_in_processing, 1)

            sync.guard(&pool.mutex)
        }

        // Free temp allocations
        free_all(context.temp_allocator)
        // Wait to quit
        sync.barrier_wait(&pool.sync)
    }
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