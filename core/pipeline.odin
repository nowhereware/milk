package milk_core

import "platform"

Pipeline_Graphics_New_Proc :: proc(rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal
Pipeline_Destroy_Proc :: proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal)

Pipeline_Commands :: struct {
	graphics_new: Pipeline_Graphics_New_Proc,
	destroy: Pipeline_Destroy_Proc
}

Pipeline_Internal :: union {
	Pipeline_Vulkan
}

pipeline_internal_graphics_new :: proc(conf: Renderer_Type, rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> (internal: Pipeline_Internal, commands: Pipeline_Commands) {
	switch conf {
	case .Vulkan: {
		commands.graphics_new = pipeline_vulkan_graphics_new
		commands.destroy = pipeline_vulkan_destroy
	}
	}

	internal = commands.graphics_new(rend, vert, frag)

	return
}

Pipeline_Type :: enum {
	Graphics,
	Compute
}

Pipeline :: struct {
	type: Pipeline_Type,
	internal: Pipeline_Internal,
	commands: Pipeline_Commands
}

pipeline_graphics_new :: proc(rend: ^Renderer, vert: Shader_Asset, frag: Shader_Asset) -> (out: Pipeline) {
	out.type = .Graphics
	out.internal, out.commands = pipeline_internal_graphics_new(rend.type, &rend.internal, vert.internal, frag.internal)

	return
}

pipeline_destroy :: proc(rend: ^Renderer, pipeline: ^Pipeline) {
	pipeline.commands.destroy(&rend.internal, &pipeline.internal)
}