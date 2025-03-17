package milk_platform

buffer_new_proc :: #type proc(rend: ^Renderer_Internal, data: rawptr, size: int) -> Buffer_Internal

Buffer_Commands :: struct {
    new: buffer_new_proc,
}

Buffer_Internal :: union {
    Gl_Buffer,
}

buffer_internal_new :: proc(rend: ^Renderer_Internal, data: rawptr, size: int) -> (internal: Buffer_Internal, commands: Buffer_Commands) {
    switch r in rend {
        case Gl_Renderer: {
            commands.new = gl_buffer_new
        }
        case Vk_Renderer: {

        }
    }

    internal = commands.new(rend, data, size)

    return
}