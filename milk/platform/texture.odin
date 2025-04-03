package milk_platform

texture_load_proc :: proc(cmd: Command_Buffer_Internal, width, height, num_channels: i32, tex_data: [^]u8) -> Texture_Internal
texture_bind_proc :: proc(cmd: Command_Buffer_Internal, texture: Texture_Internal)
texture_destroy_proc :: proc(cmd: Command_Buffer_Internal, texture: ^Texture_Internal)

Texture_Commands :: struct {
    load: texture_load_proc,
    bind: texture_bind_proc,
    destroy: texture_destroy_proc,
}

Texture_Internal :: union {
    Vk_Texture,
    Gl_Texture
}

texture_internal_new :: proc(buffer: Command_Buffer_Internal, width, height, num_channels: i32, tex_data: [^]u8) -> (internal: Texture_Internal, commands: Texture_Commands) {
    switch b in buffer {
        case ^Gl_Command_Buffer: {
            commands.load = gl_texture_load
            commands.bind = gl_texture_bind
            commands.destroy = gl_texture_destroy
        }
        case ^Vk_Command_Buffer: {

        }
    }

    internal = commands.load(buffer, width, height, num_channels, tex_data)

    return
}