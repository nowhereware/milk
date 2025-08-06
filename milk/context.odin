package milk

import pt "platform"

import "core:fmt"
import "core:time"
import "core:sync"
import "core:container/queue"
import "core:os"
import SDL "vendor:sdl3"

// # Context Config
// Configures the Context with a list of given settings. To use, create a config from `context_config_new()` to get a premade set of default
// attributes, then adjust as needed.
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
    renderer: pt.Renderer_Type,
    /// The simulation FPS of the game. Note that Rendering FPS is separate, and generally matches the refresh rate of the monitor.
    fps: f64,
    /// The clear color for the primary viewport.
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
    // The input state
    input_state: Input_State,

    // Application state

    // Whether or not the app should quit
    should_quit: bool,
    // Whether or not the app should render based on a criteria (ex. minimized window)
    should_render: bool,
    // The desired simulation framerate
    update_fps: f64,

    // Workers
    
    // A list of thread-local profilers, submitted at the end.
    thread_profilers: [dynamic]Profiler,
    // A mutex to access the thread profilers.
    thread_profiler_mutex: sync.Mutex,

    // User data

    // The current user-defined scene
    scene: ^Scene,
}

// Creates and returns a new Context, while also initializing subsystems
context_new :: proc(conf: ^Context_Config) -> (out: Context) {
    flags: SDL.InitFlags = {
        .VIDEO, .GAMEPAD, .AUDIO
    }

    // Init subsystems
    if (!SDL.Init(flags)) {
        fmt.eprintln("Error: SDL could not be initialized!")
        return Context {}
    }

    out.renderer = renderer_new(conf)
    out.asset_server = asset_server_new()
    out.input_state = input_state_new()

    // Register builtin assets
    asset_register_type(&out, Shader_Asset, shader_asset_load, shader_asset_unload, { ".vert", ".frag", ".geom" })
    asset_register_type(&out, Pipeline_Asset, pipeline_asset_load, pipeline_asset_unload, { ".gfx", ".comp" })
    asset_register_type(&out, Texture_Asset, texture_asset_load, texture_asset_unload, { ".png", ".jpg" })

    out.update_fps = conf.fps

    out.should_quit = false
    out.should_render = true

    local_profiler = profiler_new()

    return
}

context_add_module :: proc(ctx: ^Context, module: Module, $T: typeid) {
    id := typeid_of(T)

    if id not_in ctx.module_map {
        append(&ctx.module_list, module)
        ctx.module_map[id] = len(ctx.module_list) - 1
    }
}

// Changes the scene to a preloaded scene
context_change_scene_to :: proc(ctx: ^Context, scene: ^Scene) {
    old_scene := ctx.scene
    ctx.scene = scene
    old_scene.scene_unload(old_scene)

    for asset in old_scene.asset_map {
        if asset not_in scene.asset_map {
            asset_unload(scene, asset)
        }
    }

    // Ensure our commands are processed
    gfx_submit_pool(&ctx.renderer, &local_command_pool)

    scene_destroy(old_scene)
}

// Sets the scene for the context to start with, given that the scene has already been loaded
context_set_startup_scene :: proc(ctx: ^Context, scene: ^Scene) {
    ctx.scene = scene
    // Upload and process command pool
    gfx_submit_pool(&ctx.renderer, &local_command_pool)
    renderer_process_queue(&ctx.renderer)
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

    // Prior frame transforms
    // We pass these to draw tasks so that they can perform interpolation
    prev_trans_2d := world_get_storage(&ctx.scene.world, Transform_2D)
    prev_trans_3d := world_get_storage(&ctx.scene.world, Transform_3D)
    trans_state := transform_state_new(prev_trans_2d, prev_trans_3d)

    for &thread, index in worker_pool.threads {
        worker := cast(^Worker_Thread_Data)thread.data
        worker.ctx = ctx
        worker.transform_state = &trans_state
    }

    worker_pool_start(&worker_pool)

    task_profiler := profile_get(&local_profiler, "TASK_RUN_PROFILER")

    run_loop: for !ctx.should_quit {
        profile_start(&task_profiler)

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
                    }
                }
                case .WINDOW_RESIZED: {
                    w, h: i32 = 0, 0
                    SDL.GetWindowSize(ctx.renderer.window, &w, &h)
                    renderer_window_resized(&ctx.renderer, { u32(w), u32(h) })

                    if ctx.renderer.primary_viewport.current != nil {
                        if ecs_has(&ctx.scene.world, ctx.renderer.primary_viewport.current.(Entity), Camera_3D) {
                            cam_3d := ecs_get_ptr(&ctx.scene.world, ctx.renderer.primary_viewport.current.(Entity), Camera_3D)
                            camera_3d_update_aspect(cam_3d, f32(w) / f32(h))
                        }
                    }
                }
                case .WINDOW_MINIMIZED: {
                    ctx.should_render = false
                }
                case .WINDOW_RESTORED: {
                    ctx.should_render = true
                }
                case .GAMEPAD_ADDED: {
                    input_state_add_gamepad(&ctx.input_state, event.gdevice.which)
                }
                case .GAMEPAD_REMOVED: {
                    input_state_remove_gamepad(&ctx.input_state, event.gdevice.which)
                }
                case .GAMEPAD_BUTTON_DOWN: {
                    id := event.gdevice.which
                    
                    ctx.input_state.gamepads[ctx.input_state.gamepad_map[id]].accumulated[event.gbutton.button] = true
                }
                case .GAMEPAD_BUTTON_UP: {
                    id := event.gdevice.which

                    ctx.input_state.gamepads[ctx.input_state.gamepad_map[id]].accumulated[event.gbutton.button] = false
                }
            }
        }

        take_step(&task_profiler, "Poll Events")
        
        if !ctx.should_render {
            time.sleep(100 * time.Millisecond)
            continue
        }

        if UPDATE_FRAME {
            // An update frame will run, update the transform state to match old transforms.
            transform_state_update(&ctx.scene.world, &trans_state)
            // Also update the input state
            input_state_update(&ctx.input_state)
        }

        temp_accumulator := ctx.timestep.accumulator
        for temp_accumulator >= ctx.update_fps {
            temp_accumulator -= ctx.update_fps
        }

        ctx.timestep.alpha = temp_accumulator / ctx.update_fps

        take_step(&task_profiler, "Add Modules")

        renderer_begin(&ctx.renderer)

        take_step(&task_profiler, "Renderer Begin")

        // Synchronized start
        sync.barrier_wait(&worker_pool.sync)

        take_step(&task_profiler, "Barrier Begin")

        // TODO: Asset hot-reloading

        // Submit buffers to the queue as they arrive.
        for worker_pool.sync.index != worker_pool.sync.thread_count - 1 {
            renderer_process_queue(&ctx.renderer)
        }

        // Ensure we don't miss a buffer at the last wait
        renderer_process_queue(&ctx.renderer)

        take_step(&task_profiler, "Process Tasks")

        // Synchronized end
        sync.barrier_wait(&worker_pool.sync)

        take_step(&task_profiler, "Barrier End")

        renderer_end(&ctx.renderer)

        take_step(&task_profiler, "Renderer End")

        for ctx.timestep.accumulator >= ctx.update_fps {
            ctx.timestep.accumulator -= ctx.update_fps
        }

        // Reset Temp Allocator
        free_all(context.temp_allocator)

        // Clear the done list
        worker_pool_clear_done(&worker_pool)

        ctx.scene.frame_count += 1

        take_step(&task_profiler, "End Run")

        profile_end(&task_profiler)
    }

    ctx.scene.scene_unload(ctx.scene)

    for asset in ctx.scene.asset_map {
        fmt.println("Unloading", asset)
        asset_unload(ctx.scene, asset)
    }

    // Submit our local command pool
    gfx_submit_pool(&ctx.renderer, &local_command_pool)

    // Process all command pools
    renderer_process_queue(&ctx.renderer)

    transform_state_destroy(&trans_state)

    scene_destroy(ctx.scene)

    // End internal stuff
    renderer_destroy(&ctx.renderer)

    // Indicate to threads that the loop is over
    worker_pool_join(&worker_pool)
    worker_pool_destroy(&worker_pool)

    input_state_destroy(&ctx.input_state)

    // Last step: End subsystems
    SDL.Quit()

    // Print profilers
    append(&ctx.thread_profilers, local_profiler)
    condensed_profiler := condense_profilers(..ctx.thread_profilers[:])

    print_profiles(&condensed_profiler)
    profiler_destroy(&condensed_profiler)

    for &profiler in ctx.thread_profilers {
        profiler_destroy(&profiler)
    }

    delete(ctx.thread_profilers)

    asset_server_destroy(&ctx.asset_server)

    fmt.println("Context finished.")
}