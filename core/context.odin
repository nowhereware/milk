package milk_core

import "core:fmt"
import "core:time"
import "core:strings"
import "core:thread"
import "core:sync"
import "core:container/queue"
import "core:os"
import SDL "vendor:sdl3"

Context_Config :: struct {
    /// The title of the main window of the context. This is also used for the internally stored name of the project.
    title: cstring,
    /// The initial size of the main window of the context.
    window_size: UVector2,
    /// Determines whether or not the main window may be resized.
    resizable: bool,
    /// Determines whether to enable vertical sync. Generally, V-Sync is enabled internally with a preference for Mailbox, and a fallback to FIFO otherwise.
    vsync: bool,
    /// The version of the application.
    version: UVector3,
    /// The preferred rendering backend.
    renderer: Renderer_Type,
    /// The simulation FPS of the game. Note that Rendering FPS is separate, and generally matches the refresh rate of the monitor.
    fps: f64,
    /// The clear color for the primary viewport
    clear_color: Color,
}

context_config_new :: proc() -> Context_Config {
    return Context_Config {
        title = "New Milk Project",
        window_size = { 1024, 576 },
        resizable = false,
        vsync = true,
        version = { 1, 0, 0 },
        renderer = .Vulkan,
        fps = 1.0 / 60.0,
        clear_color = COLOR_CORNFLOWER_BLUE
    }
}

Context :: struct {
    // Subsystems

    // The active renderer for the engine
    renderer: Renderer,
    // The asset server
    asset_server: Asset_Server,

    // Application state

    // Whether or not the app should quit
    should_quit: bool,
    // Whether or not the app should render based on a criteria (ex. minimized window)
    should_render: bool,
    // The desired simulation framerate
    update_fps: f64,

    // Workers

    // List of tasks
    task_list: [dynamic]Task,
    // A slice that is iterated through each frame by each thread
    task_queue: queue.Queue(Task),

    // User data

    // The current user-defined scene
    scene: ^Scene,
}

// Creates and returns a new Context, while also initializing subsystems
context_new :: proc(conf: ^Context_Config) -> (out: Context) {
    flags: SDL.InitFlags = SDL.INIT_VIDEO

    // Init subsystems
    if (!SDL.Init(flags)) {
        fmt.eprintln("Error: SDL could not be initialized!")
        return Context {}
    }

    out.renderer = renderer_new(conf)
    out.asset_server = asset_server_new()
    out.update_fps = conf.fps

    out.should_quit = false
    out.should_render = true

    thread_profiler_pool = {}

    return
}

context_add_task :: proc(ctx: ^Context, task: Task) {
    append(&ctx.task_list, task)
}

// Changes the scene to a preloaded scene
context_change_scene_to :: proc(ctx: ^Context, scene: ^Scene) {
    old_scene := ctx.scene
    ctx.scene = scene
    ctx.scene.scene_unload(old_scene)
    scene_destroy(old_scene)
}

// Sets the scene for the context to start with, given that the scene has already been loaded
context_set_startup_scene :: proc(ctx: ^Context, scene: ^Scene) {
    ctx.scene = scene
}

// Sets the framerate of the context, given a value of frames to run per second
context_set_fps :: proc(ctx: ^Context, frames: int) {
    ctx.update_fps = 1.0 / cast(f64)frames
}

// Runs the context
context_run :: proc(ctx: ^Context) {
    event: SDL.Event

    window_size: IVector2
    SDL.GetWindowSize(ctx.renderer.window, &window_size.x, &window_size.y)
    
    // Set up Task workers
    worker_count := os.processor_core_count() - 1
    worker_pool: Worker_Pool
    worker_pool_new(&worker_pool, context.allocator, worker_count)

    // Fixed timestep
    prev_time := time.tick_now()
    timestep := timestep_new(prev_time)
    alpha_accumulator: f64 = 0.0

    // Prior frame transforms
    // We pass these to draw tasks so that they can perform interpolation
    prev_trans_2d := world_get_storage(&ctx.scene.world, Transform_2D)
    prev_trans_3d := world_get_storage(&ctx.scene.world, Transform_3D)
    trans_state := transform_state_new(prev_trans_2d, prev_trans_3d)

    for &thread, index in worker_pool.threads {
        worker := cast(^Worker_Thread_Data)thread.data
        worker.ctx = ctx
        worker.timestep = &timestep
        worker.transform_state = &trans_state
    }

    task_profiler := profile_get(thread_profiler(), "TASK_RUN_PROFILER")

    worker_pool_start(&worker_pool)

    run_loop: for !ctx.should_quit {
        // Poll events
        for SDL.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT: {
                    ctx.should_quit = true
                    continue run_loop
                }
                case .KEY_DOWN: {
                    if event.key.key == SDL.K_F4 {
                        ctx.should_quit = true
                        break
                    } else if event.key.key == SDL.K_F4 {
                        set_clear_color(&ctx.renderer, color_from_percent({0.0, 0.0, 0.0, 1.0}))
                        fmt.println("Changed!")
                    }
                }
                case .WINDOW_RESIZED: {
                    w, h: i32 = 0, 0
                    SDL.GetWindowSize(ctx.renderer.window, &w, &h)
                    renderer_window_resized(&ctx.renderer, { u32(w), u32(h) })
                }
                case .WINDOW_MINIMIZED: {
                    ctx.should_render = false
                }
                case .WINDOW_RESTORED: {
                    ctx.should_render = true
                }
            }
        }
        
        if !ctx.should_render {
            time.sleep(100 * time.Millisecond)
            continue
        }

        timestep.frame_duration = time.duration_seconds(time.tick_since(prev_time))
        prev_time = time.tick_now()

        // Get the alpha leftover for draw tasks
        alpha_accumulator += timestep.frame_duration

        for alpha_accumulator >= timestep.frame_duration {
            alpha_accumulator -= timestep.frame_duration
        }

        timestep.alpha = alpha_accumulator / timestep.frame_duration

        worker_pool_add_module(&worker_pool, ctx.scene.module)

        begin(&ctx.renderer)

        profile_start(task_profiler)

        // Synchronized start
        sync.barrier_wait(&worker_pool.sync)
        // Synchronized end
        sync.barrier_wait(&worker_pool.sync)

        profile_end(task_profiler)

        end(&ctx.renderer)

        // Reset Temp Allocator
        free_all(context.temp_allocator)

        // Clear the done list
        worker_pool_clear_done(&worker_pool)

        // Update Transform State to match the current frame before proceeding to the next
        trans_state = transform_state_new(world_get_storage(&ctx.scene.world, Transform_2D), world_get_storage(&ctx.scene.world, Transform_3D))

        ctx.scene.frame_count += 1
    }

    ctx.scene.scene_unload(ctx.scene)

    scene_destroy(ctx.scene)

    // End internal stuff
    renderer_destroy(&ctx.renderer)

    worker_pool_join(&worker_pool)
    worker_pool_destroy(&worker_pool)

    for &task in ctx.task_list {
        task_destroy(&task)
    }

    delete(ctx.task_list)

    // Last step: End subsystems
    SDL.Quit()

    // Print profiles
    thread_profilers: [dynamic]Profiler
    for _, profiler in thread_profiler_pool {
        append(&thread_profilers, profiler)
    }
    
    profiler_list := make([dynamic]Profiler)

    for _, profiler in thread_profiler_pool {
        append(&profiler_list, profiler)
    }

    condensed_profiler := condense_profilers(..profiler_list[:])

    //print_profiles(&condensed_profiler)
    profiler_destroy(&condensed_profiler)

    for index, &profiler in thread_profiler_pool {
        profiler_destroy(&profiler)
    }

    delete(profiler_list)
    delete(thread_profilers)
    delete(thread_profiler_pool)

    asset_server_destroy(&ctx.asset_server)

    fmt.println("Context finished.")
}