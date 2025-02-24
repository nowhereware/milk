package milk_platform

import "core:strings"
import gl "vendor:OpenGL"

Gl_Pipeline :: struct {
    program: u32
}

gl_pipeline_graphics_new :: proc(rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal {
    vert := vert.(Gl_Shader)
    frag := frag.(Gl_Shader)
    out: Gl_Pipeline

    vert_shader := gl.CreateShader(gl.VERTEX_SHADER)
    gl.ShaderBinary(1, &vert_shader, gl.SHADER_BINARY_FORMAT_SPIR_V, &vert.src, cast(i32)len(vert.src))
    gl.SpecializeShader(vert_shader, "main", 0, nil, nil)

    out.program = vert_shader

    return out
}

gl_pipeline_destroy :: proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal) {
    pipeline := &pipeline.(Gl_Pipeline)

    gl.DeleteProgram(pipeline.program)
}