package milk_platform

shader_new_proc :: proc(rend: ^Renderer_Internal, src: []u8) -> Shader_Internal

Shader_Commands :: struct {
    new: shader_new_proc
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
        }
    }

    internal = commands.new(rend, src)

    return
}