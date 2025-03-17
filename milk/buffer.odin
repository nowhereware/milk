package milk

import pt "platform"

Buffer :: struct {
    internal: pt.Buffer_Internal,
    commands: pt.Buffer_Commands,
}

buffer_new :: proc(rend: ^Renderer, data: $T) -> (out: Buffer) {
    out.internal, out.commands = pt.buffer_internal_new(&rend.internal, &data, size_of(T))

    return
}