package milk_platform

import "core:fmt"
import "core:strings"
import "vendor:stb/image"
import gl "vendor:OpenGL"

Gl_Texture :: struct {
    texture: ^u32,
}

gl_texture_load :: proc(cmd: Command_Buffer_Internal, width, height, num_channels: i32, tex_data: [^]u8) -> Texture_Internal {
    cmd := cmd.(^Gl_Command_Buffer)
    out: Gl_Texture

    out_width := new_clone(width)
    out_height := new_clone(height)
    out_num_channels := new_clone(num_channels)
    out.texture = new(u32)

    Submit_Data :: struct {
        tex_data: [^]u8,
        width, height, num_channels: ^i32,
        texture: ^u32,
    }

    submit_data := Submit_Data {
        tex_data = tex_data,
        width = out_width,
        height = out_height,
        num_channels = out_num_channels,
        texture = out.texture
    }

    command :: proc(data: rawptr) {
        d := cast(^Submit_Data)data

        gl.CreateTextures(gl.TEXTURE_2D, 1, d.texture)

        gl.TextureParameteri(d.texture^, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
        gl.TextureParameteri(d.texture^, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
        gl.TextureParameteri(d.texture^, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
        gl.TextureParameteri(d.texture^, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

        internal_format: u32
        image_format: u32

        if d.num_channels^ == 3 {
            internal_format = gl.RGB8
            image_format = gl.RGB
        } else if d.num_channels^ == 4 {
            internal_format = gl.RGBA8
            image_format = gl.RGBA
        } else {
            panic("Unhandled channel number!")
        }

        gl.TextureStorage2D(d.texture^, 1, internal_format, d.width^, d.height^)
        gl.TextureSubImage2D(d.texture^, 0, 0, 0, d.width^, d.height^, image_format, gl.UNSIGNED_BYTE, d.tex_data)

        gl.GenerateTextureMipmap(d.texture^)

        image.image_free(d.tex_data)

        free(d.width)
        free(d.height)
        free(d.num_channels)
        free(data)
    }

    append(&cmd.commands, Gl_Command { new_clone(submit_data), command })

    return out
}

gl_texture_bind :: proc(cmd: Command_Buffer_Internal, texture: Texture_Internal) {
    cmd := cmd.(^Gl_Command_Buffer)
    texture := texture.(Gl_Texture)

    command :: proc(data: rawptr) {
        d := cast(^u32)data

        gl.BindTextureUnit(0, d^)
    }

    append(&cmd.commands, Gl_Command { texture.texture, command })
}

gl_texture_destroy :: proc(cmd: Command_Buffer_Internal, texture: ^Texture_Internal) {
    texture := &texture.(Gl_Texture)

    gl.DeleteTextures(1, texture.texture)

    free(texture.texture)
}