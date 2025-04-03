package milk

import pt "platform"
import "core:fmt"
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

shader_asset_load :: proc(scene: ^Scene, path: string) {
    file_path := asset_get_full_path(path)
    fmt.println("Shader loading:", path)
    data := file_get(file_path)

    info, i_err := os.stat(file_path, context.temp_allocator)

    asset_add(scene, path, shader_new(&scene.ctx.renderer, data), type = Asset_File {
        full_path = info.fullpath
    })
}

shader_asset_unload :: proc(scene: ^Scene, path: string) {
    storage := &scene.ctx.asset_server.storages[scene.ctx.asset_server.type_map[typeid_of(Shader_Asset)]]

    fmt.println("Deleting shader.")

    shader := asset_storage_get(storage, path, Shader_Asset)

    shader.commands.destroy(&shader.internal)

    asset_storage_remove(storage, path, Shader_Asset)
}