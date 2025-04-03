package milk_platform

import gl "vendor:OpenGL"

Gl_Buffer :: struct {
    buffer: ^u32
}

gl_buffer_new :: proc(rend: ^Renderer_Internal, data: rawptr, size: int) -> Buffer_Internal {
    ren := &rend.(Gl_Renderer)
    out: Gl_Buffer

    out.buffer = new(u32)

    Submit_Data :: struct {
        buffer: ^u32,
        data: rawptr,
        size: int,
    }

    data := Submit_Data {
        buffer = out.buffer,
        data = data,
        size = size,
    }

    command :: proc(data: rawptr) {
        d := cast(^Submit_Data)data

        gl.CreateBuffers(1, d.buffer)
        gl.NamedBufferData(d.buffer^, d.size, d.data, gl.STATIC_DRAW)

        free(data)
    }

    append(&ren.main_pool.buffer.commands, Gl_Command { new_clone(data), command })

    pool := cast(Command_Pool_Internal)ren.main_pool^

    gl_renderer_submit_pool(rend, &pool)

    return out
}