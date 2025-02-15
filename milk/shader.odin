package milk

import "platform"
import "core:os"
import "core:strings"

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

shader_asset_load :: proc(server: ^Asset_Server, path: string) {
    // Find the file.
    file_path := asset_get_full_path(path)

    data, ok := os.read_entire_file_from_filename(file_path)

    if !ok {
        panic("Failed to read shader asset file!")
    }

    asset_add(server, path, shader_new(&server.ctx.renderer, data))
}