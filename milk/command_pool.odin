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

command_pool_destroy :: proc(pool: ^Command_Pool) {
    pool.commands.destroy(&pool.internal)
}

gfx_begin_draw :: proc(
    rend: ^Renderer,
    buffer: Command_Buffer,
) {
    buffer.commands.begin_draw(&rend.internal, buffer.internal)
}

gfx_bind_graphics_pipeline :: proc(buffer: Command_Buffer, pipeline: Pipeline_Asset) {
    buffer.commands.bind_graphics_pipeline(buffer.internal, pipeline.internal)
}

gfx_unbind_graphics_pipeline :: proc(buffer: Command_Buffer, pipeline: Pipeline_Asset) {
    buffer.commands.unbind_graphics_pipeline(buffer.internal, pipeline.internal)
}

gfx_end_draw :: proc(buffer: Command_Buffer) {
    buffer.commands.end_draw(buffer.internal)
}

gfx_submit_buffer :: proc(buffer: Command_Buffer) {
    // End the buffer
    buffer.commands.end(buffer.internal)
}