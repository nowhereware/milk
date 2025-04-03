package milk_platform

pipeline_graphics_new_proc :: proc(buffer: Command_Buffer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal
pipeline_upload_mat4_proc :: proc(buffer: Command_Buffer_Internal, pipeline: ^Pipeline_Internal, name: string, mat: Mat4)
pipeline_destroy_proc :: proc(buffer: Command_Buffer_Internal, pipeline: ^Pipeline_Internal)

Pipeline_Commands :: struct {
	graphics_new: pipeline_graphics_new_proc,
	upload_mat4: pipeline_upload_mat4_proc,
	destroy: pipeline_destroy_proc,
}

Pipeline_Internal :: union {
	Vk_Pipeline,
	Gl_Pipeline
}

pipeline_internal_graphics_new :: proc(buffer: Command_Buffer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> (internal: Pipeline_Internal, commands: Pipeline_Commands) {
	switch b in buffer {
	    case ^Vk_Command_Buffer: {
	    	commands.graphics_new = vk_pipeline_graphics_new
	    	commands.destroy = vk_pipeline_destroy
	    }
		case ^Gl_Command_Buffer: {
			commands.graphics_new = gl_pipeline_graphics_new
			commands.upload_mat4 = gl_pipeline_upload_mat4
			commands.destroy = gl_pipeline_destroy
		}
	}

	internal = commands.graphics_new(buffer, vert, frag)

	return
}

Pipeline_Type :: enum {
	Graphics,
	Compute
}