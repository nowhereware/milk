package milk_platform

pipeline_graphics_new_proc :: proc(rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal
pipeline_destroy_proc :: proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal)

Pipeline_Commands :: struct {
	graphics_new: pipeline_graphics_new_proc,
	destroy: pipeline_destroy_proc
}

Pipeline_Internal :: union {
	Vk_Pipeline,
	Gl_Pipeline
}

pipeline_internal_graphics_new :: proc(rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> (internal: Pipeline_Internal, commands: Pipeline_Commands) {
	switch r in rend {
	    case Vk_Renderer: {
	    	commands.graphics_new = vk_pipeline_graphics_new
	    	commands.destroy = vk_pipeline_destroy
	    }
		case Gl_Renderer: {
			commands.graphics_new = gl_pipeline_graphics_new
			commands.destroy = gl_pipeline_destroy
		}
	}

	internal = commands.graphics_new(rend, vert, frag)

	return
}

Pipeline_Type :: enum {
	Graphics,
	Compute
}