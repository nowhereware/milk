package milk

import pt "platform"

import "core:fmt"
import "core:os"
import "core:container/queue"
import "core:strings"
import "core:sync"
import SDL "vendor:sdl3"
import vk "vendor:vulkan"

Renderer :: struct {
    window: ^SDL.Window,

    // Renderer instance

    type: pt.Renderer_Type,
    internal: pt.Renderer_Internal,
    commands: pt.Renderer_Commands,

    // Data

    // A list of graphics devices exposed by the system.
    devices: [dynamic]Graphics_Device,
    // A map of command pools, indexed by thread id.
    command_pools: map[int]Command_Pool,
    // A queue of buffers that need to be submitted.
    buffer_queue: queue.Queue(Command_Buffer),
    // A mutex to sync access to the queue
    buffer_mutex: sync.Mutex,
    // The clear color of the renderer
    clear_color: Color,
}

// Creates the Renderer.
// NOTE: Currently we only support Vulkan. Future versions should ideally support other APIs
renderer_new :: proc(conf: ^Context_Config) -> (out: Renderer) {
    flags: SDL.WindowFlags = { .HIGH_PIXEL_DENSITY }

    if (conf.resizable) {
        flags = flags + {.RESIZABLE}
    }

    switch conf.renderer {
        case .Vulkan: {
            flags = flags + { .VULKAN }
        }
        case .OpenGL: {
            flags = flags + { .OPENGL }
        }
    }

    out.window = SDL.CreateWindow(
        conf.title,
        i32(conf.window_size.x),
        i32(conf.window_size.y),
        flags
    )

    if out.window == nil {
        fmt.eprintln("Error: Window could not be created!")
        fmt.eprintln("Flags: ", flags)
        fmt.eprintln("SDL Errors: ", SDL.GetError())
        return Renderer {}
    }

    out.type = conf.renderer

    internal_devices: [dynamic]pt.Graphics_Device_Internal

    rend_cfg := pt.Renderer_Config {
        app_name = conf.title,
        app_version = conf.version,
        type = conf.renderer
    }

    out.internal, out.commands, internal_devices = pt.renderer_internal_new(out.window, &rend_cfg)
    queue.init(&out.buffer_queue)
    out.commands.set_clear_color(&out.internal, conf.clear_color)

    // Register pool
    pool := gfx_get_command_pool(&out)
    out.commands.register_main_pool(&out.internal, &pool.internal)

    return
}

renderer_destroy :: proc(rend: ^Renderer) {
    for _, &pool in rend.command_pools {
        pool.commands.destroy(&pool.internal)
    }
    queue.destroy(&rend.buffer_queue)
    delete(rend.command_pools)

    rend.commands.quit(&rend.internal)
    SDL.DestroyWindow(rend.window)

    for &device in rend.devices {
        graphics_device_destroy(&device)
    }
    delete(rend.devices)
}

renderer_process_queue :: proc(rend: ^Renderer) {
    for queue.len(rend.buffer_queue) != 0 {
        buffer := queue.pop_back(&rend.buffer_queue)
        rend.commands.submit_buffer(&rend.internal, buffer.internal)
    }
}

renderer_set_clear_color :: proc(rend: ^Renderer, color: Color) {
    rend.clear_color = color
}

gfx_get_command_pool :: proc(rend: ^Renderer) -> ^Command_Pool {
    thread_id := os.current_thread_id()

    if thread_id not_in rend.command_pools {
        rend.command_pools[thread_id] = command_pool_new(rend)
    }

    return &rend.command_pools[thread_id]
}

gfx_get_command_buffer :: proc(rend: ^Renderer) -> Command_Buffer {
    pool := gfx_get_command_pool(rend)
    return command_pool_acquire(rend, pool)
}

gfx_submit_buffer :: proc(rend: ^Renderer, buffer: Command_Buffer) {
    // End the buffer
    buffer.commands.end(buffer.internal)
    // Acquire a lock on the buffer queue and push the buffer to the queue
    sync.lock(&rend.buffer_mutex)
    queue.push(&rend.buffer_queue, buffer)
    sync.unlock(&rend.buffer_mutex)
}

gfx_get_swapchain_texture :: proc(rend: ^Renderer) -> pt.Texture_Internal {
    return rend.commands.get_swapchain_texture(&rend.internal)
}

gfx_begin_draw :: proc(
    rend: ^Renderer,
    buffer: Command_Buffer,
) {
    buffer.commands.begin_draw(&rend.internal, buffer.internal)
}



// Commands for internal renderer



renderer_window_resized :: proc(rend: ^Renderer, size: UVector2) {
    rend.commands.set_framebuffer_resized(&rend.internal, size)
}

renderer_begin :: proc(rend: ^Renderer) {
    rend.commands.begin(
        &rend.internal
    )
}

renderer_bind_graphics_pipeline :: proc(rend: ^Renderer, pipeline: ^Pipeline_Asset) {
    rend.commands.bind_graphics_pipeline(&rend.internal, &pipeline.internal)
}

renderer_end :: proc(rend: ^Renderer) {
    rend.commands.end(&rend.internal, rend.window)
}