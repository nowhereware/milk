package milk

import pt "platform"
import "core:os"
import "core:strings"

Shader_Type :: enum {
	Geometry,
	Vertex,
	Fragment,
	Compute,
}

// # Shader_Asset
// A compiled shader asset, stored within the Asset_Server.
Shader_Asset :: struct {
    internal: pt.Shader_Internal,
    commands: pt.Shader_Commands,
}

shader_new :: proc(rend: ^Renderer, src: []u8) -> (out: Shader_Asset) {
    out.internal, out.commands = pt.shader_internal_new(&rend.internal, src)

    return
}

shader_asset_load :: proc(server: ^Asset_Server, path: string) {
    // Find the file.
    file_path := asset_get_full_path(path)

    data, ok := file_get(file_path)

    if !ok {
        panic("Failed to read shader asset file!")
    }

    asset_add(server, path, shader_new(&server.ctx.renderer, data))
}