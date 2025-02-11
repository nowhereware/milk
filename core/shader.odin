package milk_core

import "platform"

Shader_Type :: enum {
	Geometry,
	Vertex,
	Fragment,
	Compute,
}

Shader_New_Proc :: proc(rend: ^Renderer_Internal, src: []u8) -> Shader_Internal

Shader_Commands :: struct {
    new: Shader_New_Proc
}

Shader_Internal :: union {
    Shader_Vulkan
}

shader_internal_new :: proc(rend: ^Renderer_Internal, src: []u8) -> (internal: Shader_Internal, commands: Shader_Commands) {
    switch r in rend {
        case Renderer_Vulkan: {
            commands.new = shader_vulkan_new
        }
    }

    internal = commands.new(rend, src)

    return
}

// # Shader_Asset
// A compiled shader asset, stored within the Asset_Server.
Shader_Asset :: struct {
    internal: Shader_Internal,
    commands: Shader_Commands,
}

shader_new :: proc(rend: ^Renderer, src: []u8) -> (out: Shader_Asset) {
    out.internal, out.commands = shader_internal_new(&rend.internal, src)

    return
}
