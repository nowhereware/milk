package milk_platform

import "core:fmt"
import "core:strings"
import gl "vendor:OpenGL"

Gl_Pipeline :: struct {
    program: ^u32,
}

gl_pipeline_graphics_new :: proc(buffer: Command_Buffer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal {
    buffer := buffer.(^Gl_Command_Buffer)
    vert := vert.(Gl_Shader)
    frag := frag.(Gl_Shader)
    out: Gl_Pipeline

    Submit_Data :: struct {
        vert: ^Gl_Shader,
        frag: ^Gl_Shader,
        program: ^u32,
    }

    command :: proc(data: rawptr) {
        d := cast(^Submit_Data)data

        vert_shader := gl.CreateShader(gl.VERTEX_SHADER)
        gl.ShaderBinary(1, &vert_shader, gl.SHADER_BINARY_FORMAT_SPIR_V, raw_data(d.vert.src), cast(i32)len(d.vert.src))
        gl.SpecializeShader(vert_shader, "main", 0, nil, nil)

        glcheck_shader(vert_shader, gl.COMPILE_STATUS)
        
        frag_shader := gl.CreateShader(gl.FRAGMENT_SHADER)
        gl.ShaderBinary(1, &frag_shader, gl.SHADER_BINARY_FORMAT_SPIR_V, raw_data(d.frag.src), cast(i32)len(d.frag.src))
        gl.SpecializeShader(frag_shader, "main", 0, nil, nil)

        glcheck_shader(frag_shader, gl.COMPILE_STATUS)

        program := gl.CreateProgram()
        gl.AttachShader(program, vert_shader)
        gl.AttachShader(program, frag_shader)

        gl.LinkProgram(program)

        glcheck(.Program, program, gl.LINK_STATUS)

        gl.DetachShader(program, vert_shader)
        gl.DetachShader(program, frag_shader)

        gl.DeleteShader(vert_shader)
        gl.DeleteShader(frag_shader)

        d.program^ = program

        free(d.vert)
        free(d.frag)

        free(data)
    }

    out.program = new(u32)

    submit_data := Submit_Data {
        vert = new_clone(vert),
        frag = new_clone(frag),
        program = out.program,
    }

    append(&buffer.commands, Gl_Command { new_clone(submit_data), command })

    return out
}

gl_pipeline_destroy :: proc(buffer: Command_Buffer_Internal, pipeline: ^Pipeline_Internal) {
    buffer := buffer.(^Gl_Command_Buffer)
    pipeline := &pipeline.(Gl_Pipeline)

    gl.DeleteProgram(pipeline.program^)

    free(pipeline.program)
}