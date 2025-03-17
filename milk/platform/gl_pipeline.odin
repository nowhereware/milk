package milk_platform

import "core:fmt"
import "core:math/linalg/glsl"
import "core:strings"
import gl "vendor:OpenGL"

Gl_Pipeline :: struct {
    program: ^u32,
    uniform_buffer: ^u32,
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
        uniform_buffer: ^u32,
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
        
        gl.CreateBuffers(1, d.uniform_buffer)
        gl.NamedBufferData(d.uniform_buffer^, size_of(Mat4), nil, gl.STATIC_DRAW)

        free(d.vert)
        free(d.frag)

        free(data)
    }

    out.program = new(u32)
    out.uniform_buffer = new(u32)

    submit_data := Submit_Data {
        vert = new_clone(vert),
        frag = new_clone(frag),
        program = out.program,
        uniform_buffer = out.uniform_buffer,
    }

    append(&buffer.commands, Gl_Command { new_clone(submit_data), command })

    return out
}

gl_pipeline_upload_mat4 :: proc(buffer: Command_Buffer_Internal, pipeline: ^Pipeline_Internal, name: string, mat: Mat4) {
    buffer := buffer.(^Gl_Command_Buffer)
    pipeline := pipeline.(Gl_Pipeline)

    Submit_Data :: struct {
        program: ^u32,
        uniform_buffer: ^u32,
        name: cstring,
        mat: ^Mat4,
    }

    submit := Submit_Data {
        program = pipeline.program,
        uniform_buffer = pipeline.uniform_buffer,
        name = strings.clone_to_cstring(name),
        mat = new_clone(mat),
    }

    command :: proc(data: rawptr) {
        d := cast(^Submit_Data)data

        gl.NamedBufferSubData(d.uniform_buffer^, 0, size_of(Mat4), d.mat)

        delete(d.name)
        free(d.mat)
        free(data)
    }

    append(&buffer.commands, Gl_Command { new_clone(submit), command })
}

gl_pipeline_destroy :: proc(buffer: Command_Buffer_Internal, pipeline: ^Pipeline_Internal) {
    buffer := buffer.(^Gl_Command_Buffer)
    pipeline := &pipeline.(Gl_Pipeline)

    gl.DeleteProgram(pipeline.program^)
    gl.DeleteBuffers(1, pipeline.uniform_buffer)

    free(pipeline.program)
    free(pipeline.uniform_buffer)
}