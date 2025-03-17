package milk_platform

import "core:fmt"
import gl "vendor:OpenGL"

gl_execute_proc :: proc(data: rawptr)

Gl_Command :: struct {
    data: rawptr,
    execute: gl_execute_proc,
}

Gl_Command_Buffer :: struct {
    commands: [dynamic]Gl_Command,
}

gl_command_buffer_begin_draw :: proc(rend: ^Renderer_Internal, buffer: Command_Buffer_Internal) {
    
}

gl_command_buffer_bind_graphics_pipeline :: proc(buffer: Command_Buffer_Internal, pipeline: Pipeline_Internal) {
    buffer := buffer.(^Gl_Command_Buffer)
    pipeline := pipeline.(Gl_Pipeline)

    command :: proc(data: rawptr) {
        d := cast(^Gl_Pipeline)data

        gl.UseProgram(d.program^)
        gl.BindBufferBase(gl.UNIFORM_BUFFER, 1, d.uniform_buffer^)

        free(data)
    }

    append(&buffer.commands, Gl_Command { new_clone(pipeline), command })
}

gl_command_buffer_unbind_graphics_pipeline :: proc(buffer: Command_Buffer_Internal, pipeline: Pipeline_Internal) {
    buffer := buffer.(^Gl_Command_Buffer)
    pipeline := pipeline.(Gl_Pipeline)

    command :: proc(data: rawptr) {
        gl.UseProgram(0)
    }

    append(&buffer.commands, Gl_Command { nil, command })
}

gl_command_buffer_end_draw :: proc(buffer: Command_Buffer_Internal) {
    buffer := buffer.(^Gl_Command_Buffer)
}

gl_command_buffer_end :: proc(buffer: Command_Buffer_Internal) {
    
}

Gl_Command_Pool :: struct {
    buffer: Gl_Command_Buffer,
}

gl_command_pool_new :: proc(rend: ^Renderer_Internal) -> Command_Pool_Internal {
    rend := &rend.(Gl_Renderer)
    out: Gl_Command_Pool
    out.buffer = {}

    return out
}

gl_command_pool_acquire :: proc(pool: ^Command_Pool_Internal) -> Command_Buffer_Internal {
    pool := &pool.(Gl_Command_Pool)

    return &pool.buffer
}

gl_command_pool_destroy :: proc(pool: ^Command_Pool_Internal) {
    pool := &pool.(Gl_Command_Pool)

    delete(pool.buffer.commands)
}