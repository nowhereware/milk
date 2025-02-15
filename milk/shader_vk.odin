package milk

import "core:fmt"
import vk "vendor:vulkan"

Shader_Vulkan :: struct {
    src: []u8,
}

shader_vulkan_new :: proc(rend: ^Renderer_Internal, src: []u8) -> Shader_Internal {
    rend := &rend.(Renderer_Vulkan)
    out: Shader_Vulkan

    out.src = src

    return out
}