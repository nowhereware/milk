package milk_platform

import gl "vendor:OpenGL"

Gl_Check_Type :: enum {
    Shader,
    Program,
}

glcheck :: proc(type: Gl_Check_Type, prog: u32, name: u32, loc := #caller_location) {
    switch type {
        case .Shader: {
            glcheck_shader(prog, name, loc)
        }
        case .Program: {
            glcheck_program(prog, name, loc)
        }
    }
}

glcheck_shader :: proc(shader: u32, name: u32, loc := #caller_location) {
    ok: i32
    gl.GetShaderiv(shader, name, &ok)

    if ok == 0 {
        panic("Error in glcheck shader!", loc)
    }
}

glcheck_program :: proc(prog: u32, name: u32, loc := #caller_location) {
    ok: i32
    gl.GetProgramiv(prog, name, &ok)

    if ok == 0 {
        panic("Error in glcheck program!", loc)
    }
}