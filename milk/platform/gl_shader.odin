package milk_platform

import "core:fmt"

Gl_Shader :: struct {
    src: []u8
}

gl_shader_new :: proc(rend: ^Renderer_Internal, src: []u8) -> Shader_Internal {
    out: Gl_Shader

    out.src = src

    return out
}

gl_shader_destroy :: proc(shader: ^Shader_Internal) {
    shader := &shader.(Gl_Shader)

    //delete(shader.src)
}