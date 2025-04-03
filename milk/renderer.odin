package milk

import pt "platform"

import "core:fmt"
import "core:os"
import "core:container/queue"
import "core:strings"
import "core:sync"
import SDL "vendor:sdl3"
import vk "vendor:vulkan"

@(thread_local)
local_command_pool: Command_Pool

Renderer :: struct {
    window: ^SDL.Window,

    // Renderer instance

    type: pt.Renderer_Type,
    internal: pt.Renderer_Internal,
    commands: pt.Renderer_Commands,

    // Data

    // A list of graphics devices exposed by the system.
    devices: [dynamic]Graphics_Device,
    // A queue of pools that need to be submitted.
    pool_queue: queue.Queue(^Command_Pool),
    // A mutex to sync access to the queue
    buffer_mutex: sync.Mutex,
    // The clear color of the renderer
    clear_color: Color,
    // The Viewport of the main window
    primary_viewport: Viewport,
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
    queue.init(&out.pool_queue, os.processor_core_count())
    out.commands.set_clear_color(&out.internal, conf.clear_color)

    local_command_pool = command_pool_new(&out)

    // Register pool
    out.commands.register_main_pool(&out.internal, &local_command_pool.internal)

    return
}

renderer_destroy :: proc(rend: ^Renderer) {
    queue.destroy(&rend.pool_queue)

    rend.commands.quit(&rend.internal)
    SDL.DestroyWindow(rend.window)

    for &device in rend.devices {
        graphics_device_destroy(&device)
    }
    
    delete(rend.devices)
}

renderer_process_queue :: proc(rend: ^Renderer) {
    sync.lock(&rend.buffer_mutex)
    for queue.len(rend.pool_queue) != 0 {
        pool := queue.pop_back(&rend.pool_queue)
        rend.commands.submit_pool(&rend.internal, &pool.internal)
    }
    sync.unlock(&rend.buffer_mutex)
}

renderer_set_clear_color :: proc(rend: ^Renderer, color: Color) {
    rend.clear_color = color
}

gfx_get_command_buffer :: proc(rend: ^Renderer) -> Command_Buffer {
    return command_pool_acquire(rend, &local_command_pool)
}

gfx_submit_pool :: proc(rend: ^Renderer, pool: ^Command_Pool) {
    // Acquire a lock on the pool queue and push the pool to the queue
    sync.lock(&rend.buffer_mutex)
    queue.push(&rend.pool_queue, pool)
    sync.unlock(&rend.buffer_mutex)
}

gfx_get_swapchain_texture :: proc(rend: ^Renderer) -> pt.Texture_Internal {
    return rend.commands.get_swapchain_texture(&rend.internal)
}

gfx_get_primary_viewport :: proc(rend: ^Renderer) -> ^Viewport {
    return &rend.primary_viewport
}



// Commands for internal renderer



renderer_window_resized :: proc(rend: ^Renderer, size: UVector2) {
    rend.commands.set_framebuffer_resized(&rend.internal, size)
}

renderer_begin :: proc(rend: ^Renderer) {
    rend.commands.begin(&rend.internal)
}

renderer_end :: proc(rend: ^Renderer) {
    rend.commands.end(&rend.internal, rend.window)
}