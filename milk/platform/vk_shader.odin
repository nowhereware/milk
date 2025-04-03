package milk_platform

import "core:fmt"
import vk "vendor:vulkan"

Vk_Shader :: struct {
    src: []u8,
}

vk_shader_new :: proc(rend: ^Renderer_Internal, src: []u8) -> Shader_Internal {
    out: Vk_Shader

    out.src = src

    return out
}