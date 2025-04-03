package milk_platform

import "core:fmt"
import vk "vendor:vulkan"

// TODO: Update this
VERTEX_BINDING := vk.VertexInputBindingDescription {
	binding = 0,
	stride = size_of(Vertex),
	inputRate = .VERTEX
}

VERTEX_ATTRIBUTES := [?]vk.VertexInputAttributeDescription {
	{
		binding = 0,
		location = 0,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, position)
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, uv)
	}
}

// # Vk Pipeline
// A "pipeline" for processing a linked series of shaders. Note that this is not actually a pipeline in the literal sense, but rather just a list
// of Shader Objects that are linked together at creation.
Vk_Pipeline :: struct {
	type: Pipeline_Type,
	shaders: [dynamic]vk.ShaderEXT,
	stages: vk.ShaderStageFlags,
	descriptor_set_layout: vk.DescriptorSetLayout,
	pipeline_layout: vk.PipelineLayout,
}

vk_pipeline_graphics_new :: proc(buffer: Command_Buffer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal {
	buffer := buffer.(^Vk_Command_Buffer)
	vert := vert.(Vk_Shader)
	frag := frag.(Vk_Shader)

	out: Vk_Pipeline

	ubo_layout_binding := vk.DescriptorSetLayoutBinding {
		binding = 0,
		descriptorType = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags = {.VERTEX},
		pImmutableSamplers = nil,
	}

	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings = &ubo_layout_binding,
	}

	//result := vk.CreateDescriptorSetLayout(buffer.device, &layout_info, nil, &out.descriptor_set_layout)

	/*
	if result != .SUCCESS {
		fmt.println(result)
		panic("Failed to create descriptor set layout!")
	}
	*/

	shader_create_infos := make([dynamic]vk.ShaderCreateInfoEXT)
	append(&shader_create_infos, vk.ShaderCreateInfoEXT {
		sType = .SHADER_CREATE_INFO_EXT,
		pNext = nil,
		flags = {.LINK_STAGE},
		stage = {.VERTEX},
		nextStage = {.FRAGMENT},
		codeType = .SPIRV,
		codeSize = len(vert.src),
		pCode = &vert.src,
		pName = "main",
		setLayoutCount = 1,
		pSetLayouts = &out.descriptor_set_layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges = nil,
		pSpecializationInfo = nil,
	})

	append(&shader_create_infos, vk.ShaderCreateInfoEXT {
		sType = .SHADER_CREATE_INFO_EXT,
		pNext = nil,
		flags = {.LINK_STAGE},
		stage = {.FRAGMENT},
		nextStage = {},
		codeType = .SPIRV,
		codeSize = len(frag.src),
		pCode = &frag.src,
		pName = "main",
		setLayoutCount = 1,
		pSetLayouts = &out.descriptor_set_layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges = nil,
		pSpecializationInfo = nil
	})

	//vkcheck(vk.CreateShadersEXT(rend.device, 2, raw_data(shader_create_infos), nil, raw_data(out.shaders)), "Failed to create pipeline!")

	out.stages = {
		.VERTEX,
		.FRAGMENT
	}

	return out
}

vk_pipeline_destroy :: proc(buffer: Command_Buffer_Internal, pipeline: ^Pipeline_Internal) {
	buffer := buffer.(^Vk_Command_Buffer)
	pipeline := &pipeline.(Vk_Pipeline)

	//vk.DeviceWaitIdle(rend.device)

	//vk.DestroyDescriptorSetLayout(rend.device, pipeline.descriptor_set_layout, nil)
	
	for shader in pipeline.shaders {
		//vk.DestroyShaderEXT(rend.device, shader, nil)
	}
}