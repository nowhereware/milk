package milk

import pt "platform"

Command_Buffer :: struct {
    internal: pt.Command_Buffer_Internal,
    commands: pt.Command_Buffer_Commands,
}

Command_Pool :: struct {
    internal: pt.Command_Pool_Internal,
    commands: pt.Command_Pool_Commands,
}

command_pool_new :: proc(rend: ^Renderer) -> (out: Command_Pool) {
    out.internal, out.commands = pt.command_pool_internal_new(&rend.internal)

    return
}

command_pool_acquire :: proc(rend: ^Renderer, pool: ^Command_Pool) -> (out: Command_Buffer) {
    out.internal, out.commands = pt.command_buffer_internal_new(&rend.internal, &pool.internal)
    return
}