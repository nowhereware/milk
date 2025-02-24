package milk_platform

import gl "vendor:OpenGL"
import SDL "vendor:sdl3"

Gl_Renderer :: struct {
    ctx: SDL.GLContext,
    clear_color: Color,
    main_pool: ^Gl_Command_Pool
}

gl_renderer_new :: proc(window: ^SDL.Window, conf: ^Renderer_Config) -> (Renderer_Internal, [dynamic]Graphics_Device_Internal) {
    out: Gl_Renderer

    SDL.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 4)
    SDL.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 6)
    SDL.GL_SetAttribute(.CONTEXT_PROFILE_MASK, cast(i32)SDL.GLProfileFlag.CORE)
    out.ctx = SDL.GL_CreateContext(window)

    gl.load_up_to(4, 6, SDL.gl_set_proc_address)

    w, h: i32
    SDL.GetWindowSize(window, &w, &h)

    gl.Viewport(0, 0, w, h)

    return out, {}
}

gl_renderer_begin :: proc(rend: ^Renderer_Internal) {
    rend := &rend.(Gl_Renderer)
    color := color_as_percent(rend.clear_color)

    gl.ClearColor(color.value.r, color.value.g, color.value.b, color.value.a)
    gl.Clear(gl.COLOR_BUFFER_BIT)
}

gl_renderer_end :: proc(rend: ^Renderer_Internal, window: ^SDL.Window) {
    SDL.GL_SwapWindow(window)
}

gl_renderer_quit :: proc(rend: ^Renderer_Internal) {
    rend := &rend.(Gl_Renderer)
}

gl_renderer_set_framebuffer_resized :: proc(rend: ^Renderer_Internal, size: UVector2) {
    rend := &rend.(Gl_Renderer)

    gl.Viewport(0, 0, i32(size.x), i32(size.y))
}

gl_renderer_submit_buffer :: proc(rend: ^Renderer_Internal, buffer: Command_Buffer_Internal) {
    rend := &rend.(Gl_Renderer)
    buffer := buffer.(^Gl_Command_Buffer)

    for command in buffer.commands {
        command.execute(command.data)
    }
}

gl_renderer_register_main_pool :: proc(rend: ^Renderer_Internal, pool: ^Command_Pool_Internal) {
    rend := &rend.(Gl_Renderer)
    pool := &pool.(Gl_Command_Pool)
    rend.main_pool = pool
}

gl_renderer_set_clear_color :: proc(rend: ^Renderer_Internal, color: Color) {
    rend := &rend.(Gl_Renderer)
    rend.clear_color = color_as_percent(color)
}