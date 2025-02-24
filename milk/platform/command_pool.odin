package milk_platform

command_buffer_begin_draw_proc :: #type proc(
    rend: ^Renderer_Internal,
    buffer: Command_Buffer_Internal,
)
command_buffer_end_proc :: #type proc(buffer: Command_Buffer_Internal)

Command_Buffer_Internal :: union {
    ^Vk_Command_Buffer,
    ^Gl_Command_Buffer
}

Command_Buffer_Commands :: struct {
    begin_draw: command_buffer_begin_draw_proc,
    end: command_buffer_end_proc,
}

command_buffer_internal_new :: proc(rend: ^Renderer_Internal, pool: ^Command_Pool_Internal) -> (
    internal: Command_Buffer_Internal,
    commands: Command_Buffer_Commands,
) {
    temp_acquire: command_pool_acquire_proc

    switch r in rend {
        case Vk_Renderer: {
            commands.begin_draw = vk_command_buffer_begin_draw
            commands.end = vk_command_buffer_end
            temp_acquire = vk_command_pool_acquire
        }
        case Gl_Renderer: {
            commands.begin_draw = gl_command_buffer_begin_draw
            commands.end = gl_command_buffer_end
            temp_acquire = gl_command_pool_acquire
        }
    }

    internal = temp_acquire(pool)

    return
}

command_pool_new_proc :: #type proc(rend: ^Renderer_Internal) -> Command_Pool_Internal
command_pool_acquire_proc :: #type proc(pool: ^Command_Pool_Internal) -> Command_Buffer_Internal
command_pool_destroy_proc :: #type proc(pool: ^Command_Pool_Internal)

Command_Pool_Internal :: union {
    Vk_Command_Pool,
    Gl_Command_Pool
}

Command_Pool_Commands :: struct {
    new: command_pool_new_proc,
    acquire: command_pool_acquire_proc,
    destroy: command_pool_destroy_proc,
}

command_pool_internal_new :: proc(rend: ^Renderer_Internal) -> (
    internal: Command_Pool_Internal,
    commands: Command_Pool_Commands,
) {
    switch r in rend {
        case Vk_Renderer: {
            commands.new = vk_command_pool_new
            commands.acquire = vk_command_pool_acquire
            commands.destroy = vk_command_pool_destroy
        }
        case Gl_Renderer: {
            commands.new = gl_command_pool_new
            commands.acquire = gl_command_pool_acquire
            commands.destroy = gl_command_pool_destroy
        }
    }

    internal = commands.new(rend)

    return
}