package milk_platform

import SDL "vendor:sdl3"

Renderer_Type :: enum {
    Vulkan,
    OpenGL,
}

Renderer_Config :: struct {
    app_name: cstring,
    app_version: UVector3,
    type: Renderer_Type,
}

renderer_new_proc :: #type proc(window: ^SDL.Window, conf: ^Renderer_Config) -> (Renderer_Internal, [dynamic]Graphics_Device_Internal)
renderer_begin_proc :: #type proc(rend: ^Renderer_Internal)
renderer_bind_graphics_pipeline_proc :: #type proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal)
renderer_end_proc :: #type proc(rend: ^Renderer_Internal, window: ^SDL.Window)
renderer_quit_proc :: #type proc(rend: ^Renderer_Internal)
renderer_set_framebuffer_resized_proc :: #type proc(rend: ^Renderer_Internal, size: UVector2)
renderer_submit_buffer_proc :: #type proc(rend: ^Renderer_Internal, buffer: Command_Buffer_Internal)
renderer_register_main_pool_proc :: #type proc(rend: ^Renderer_Internal, pool: ^Command_Pool_Internal)
renderer_get_swapchain_texture_proc :: #type proc(rend: ^Renderer_Internal) -> Texture_Internal
renderer_set_clear_color_proc :: #type proc(rend: ^Renderer_Internal, color: Color)

Renderer_Commands :: struct {
    new: renderer_new_proc,
    begin: renderer_begin_proc,
    bind_graphics_pipeline: renderer_bind_graphics_pipeline_proc,
    end: renderer_end_proc,
    quit: renderer_quit_proc,
    set_framebuffer_resized: renderer_set_framebuffer_resized_proc,
    submit_buffer: renderer_submit_buffer_proc,
    register_main_pool: renderer_register_main_pool_proc,
    get_swapchain_texture: renderer_get_swapchain_texture_proc,
    set_clear_color: renderer_set_clear_color_proc,
}

Renderer_Internal :: union {
    Vk_Renderer,
    Gl_Renderer,
}

renderer_internal_new :: proc(window: ^SDL.Window, conf: ^Renderer_Config) -> (
    internal: Renderer_Internal, 
    commands: Renderer_Commands,
    devices: [dynamic]Graphics_Device_Internal
) {
    switch conf.type {
        case .Vulkan: {
            commands.new = vk_renderer_new
            commands.begin = vk_renderer_begin
            commands.bind_graphics_pipeline = vk_renderer_bind_graphics_pipeline
            commands.end = vk_renderer_end
            commands.quit = vk_renderer_quit
            commands.set_framebuffer_resized = vk_renderer_set_framebuffer_resized
            commands.submit_buffer = vk_renderer_submit_buffer
            commands.register_main_pool = vk_renderer_register_main_pool
            commands.get_swapchain_texture = vk_renderer_get_swapchain_texture
        }
        case .OpenGL: {
            commands.new = gl_renderer_new
            commands.begin = gl_renderer_begin
            commands.end = gl_renderer_end
            commands.quit = gl_renderer_quit
            commands.set_framebuffer_resized = gl_renderer_set_framebuffer_resized
            commands.submit_buffer = gl_renderer_submit_buffer
            commands.register_main_pool = gl_renderer_register_main_pool
            commands.set_clear_color = gl_renderer_set_clear_color
        }
    }

    internal, devices = commands.new(window, conf)

    return
}