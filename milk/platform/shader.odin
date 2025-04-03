package milk_platform

import "core:fmt"

shader_new_proc :: proc(rend: ^Renderer_Internal, src: []u8) -> Shader_Internal
shader_destroy_proc :: proc(shader: ^Shader_Internal)

Shader_Commands :: struct {
    new: shader_new_proc,
    destroy: shader_destroy_proc,
}

Shader_Internal :: union {
    Vk_Shader,
    Gl_Shader
}

shader_internal_new :: proc(rend: ^Renderer_Internal, src: []u8) -> (internal: Shader_Internal, commands: Shader_Commands) {
    switch r in rend {
        case Vk_Renderer: {
            commands.new = vk_shader_new
        }
        case Gl_Renderer: {
            commands.new = gl_shader_new
            commands.destroy = gl_shader_destroy
        }
    }

    internal = commands.new(rend, src)

    return
}