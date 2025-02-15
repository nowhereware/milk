package milk

import "platform"

import "core:fmt"
import "core:strings"
import SDL "vendor:sdl3"
import vk "vendor:vulkan"

Renderer_Type :: enum {
    Vulkan,
}

Renderer_New_Proc :: proc(window: ^SDL.Window, conf: ^Context_Config, viewport: Viewport) -> Renderer_Internal
Renderer_Begin_Proc :: proc(rend: ^Renderer_Internal, window: ^SDL.Window)
Renderer_Bind_Graphics_Pipeline_Proc :: proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal)
Renderer_End_Proc :: proc(rend: ^Renderer_Internal, window: ^SDL.Window)
Renderer_Quit_Proc :: proc(rend: ^Renderer_Internal)
Renderer_Set_Clear_Color :: proc(rend: ^Renderer_Internal, color: Color)
Renderer_Set_Framebuffer_Resized :: proc(rend: ^Renderer_Internal, size: UVector2)

Renderer_Commands :: struct {
    new: Renderer_New_Proc,
    begin: Renderer_Begin_Proc,
    bind_graphics_pipeline: Renderer_Bind_Graphics_Pipeline_Proc,
    end: Renderer_End_Proc,
    quit: Renderer_Quit_Proc,
    set_clear_color: Renderer_Set_Clear_Color,
    set_framebuffer_resized: Renderer_Set_Framebuffer_Resized
}

Renderer_Internal :: union {
    Renderer_Vulkan
}

renderer_internal_new :: proc(window: ^SDL.Window, conf: ^Context_Config, viewport: Viewport) -> (internal: Renderer_Internal, commands: Renderer_Commands) {
    switch conf.renderer {
        case .Vulkan: {
            commands.new = renderer_vulkan_new
            commands.begin = renderer_vulkan_begin
            commands.bind_graphics_pipeline = renderer_vulkan_bind_graphics_pipeline
            commands.end = renderer_vulkan_end
            commands.quit = renderer_vulkan_quit
            commands.set_clear_color = renderer_vulkan_set_clear_color
            commands.set_framebuffer_resized = renderer_vulkan_set_framebuffer_resized
        }
    }

    internal = commands.new(window, conf, viewport)

    return
}

// Holds the size of the current window, and a clear color.
Viewport :: struct {
    size: UVector2,
    clear_color: Color,
}

Renderer :: struct {
    window: ^SDL.Window,

    // Renderer instance
    type: Renderer_Type,
    internal: Renderer_Internal,
    commands: Renderer_Commands,
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
            flags = flags + {.VULKAN}
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

    viewport := Viewport {
        size = { conf.window_size.x, conf.window_size.y },
        clear_color = color_as_percent(conf.clear_color),
    }

    out.type = conf.renderer

    out.internal, out.commands = renderer_internal_new(out.window, conf, viewport)

    return
}

renderer_destroy :: proc(rend: ^Renderer) {
    rend.commands.quit(&rend.internal)
    SDL.DestroyWindow(rend.window)
}



// Commands for internal renderer



set_clear_color :: proc(rend: ^Renderer, color: Color) {
    rend.commands.set_clear_color(&rend.internal, color)
}

renderer_window_resized :: proc(rend: ^Renderer, size: UVector2) {
    rend.commands.set_framebuffer_resized(&rend.internal, size)
}

begin :: proc(rend: ^Renderer) {
    rend.commands.begin(&rend.internal, rend.window)
}

bind_graphics_pipeline :: proc(rend: ^Renderer, pipeline: ^Pipeline_Asset) {
    rend.commands.bind_graphics_pipeline(&rend.internal, &pipeline.internal)
}

end :: proc(rend: ^Renderer) {
    rend.commands.end(&rend.internal, rend.window)
}