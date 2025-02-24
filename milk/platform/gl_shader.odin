package milk_platform

Gl_Shader :: struct {
    src: []u8
}

gl_shader_new :: proc(rend: ^Renderer_Internal, src: []u8) -> Shader_Internal {
    out: Gl_Shader

    out.src = src

    return out
}