package milk

import pt "platform"

import "core:fmt"
import "core:strings"
import "core:os"
import "vendor:stb/image"

// # Texture
// A component referring to a loaded Texture Asset via an Asset Handle
Texture :: struct {
    handle: Asset_Handle,
}

// # Texture Asset
// A loaded texture, stored within the renderer's internal data buffers
Texture_Asset :: struct {
    internal: pt.Texture_Internal,
    commands: pt.Texture_Commands,
    width, height, num_channels: i32,
}

texture_bind :: proc(buffer: Command_Buffer, texture: Texture_Asset) {
    texture.commands.bind(buffer.internal, texture.internal)
}

texture_asset_new :: proc(buffer: Command_Buffer, path: string) -> (out: Texture_Asset) {
    width, height, num_channels: i32
    tex_data: [^]u8

    image.set_flip_vertically_on_load(1)

    path_str := strings.clone_to_cstring(path, context.temp_allocator)
    tex_data = image.load(path_str, &out.width, &out.height, &out.num_channels, 0)

    out.internal, out.commands = pt.texture_internal_new(buffer.internal, out.width, out.height, out.num_channels, tex_data)
    
    return
}

texture_asset_destroy :: proc(buffer: Command_Buffer, texture: ^Texture_Asset) {
    texture.commands.destroy(buffer.internal, &texture.internal)
}

texture_asset_load :: proc(scene: ^Scene, path: string) {
    full_path := asset_get_full_path(path)
    fmt.println("Texture loading:", full_path)

    buffer := gfx_get_command_buffer(&scene.ctx.renderer)

    tex := texture_asset_new(buffer, full_path)

    info, i_err := os.stat(full_path, context.temp_allocator)

    // Submit buffer
    gfx_submit_buffer(buffer)

    asset_add(scene, path, tex, Asset_File {
        full_path = info.fullpath
    })
}

texture_asset_unload :: proc(scene: ^Scene, path: string) {
    storage := asset_server_get_storage(&scene.ctx.asset_server, Texture_Asset)

    texture := asset_storage_get_ptr(storage, path, Texture_Asset)

    buffer := gfx_get_command_buffer(&scene.ctx.renderer)

    texture_asset_destroy(buffer, texture)

    gfx_submit_buffer(buffer)

    asset_storage_remove(storage, path, Texture_Asset)
}