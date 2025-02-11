#+feature dynamic-literals

package milk_core

import "platform"

import "core:fmt"
import vk "vendor:vulkan"

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
		offset = cast(u32)offset_of(Vertex, pos)
	},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, color)
	}
}

Uniform_Buffer_Object :: struct {
	model: Mat4,
	view: Mat4,
	proj: Mat4
}

// NEW PIPELINE IMPLEMENTATION
// Despite being called a pipeline, because we use Shader Objects and Dynamic Rendering this is a pipeline in name only. Think of this more
// as just a linked set of shaders.
Pipeline_Vulkan :: struct {
	type: Pipeline_Type,
	shaders: [dynamic]vk.ShaderEXT,
	stages: vk.ShaderStageFlags,
	descriptor_set_layout: vk.DescriptorSetLayout,
	pipeline_layout: vk.PipelineLayout,
}

pipeline_vulkan_graphics_new :: proc(rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal {
	rend := &rend.(Renderer_Vulkan)
	vert := vert.(Shader_Vulkan)
	frag := frag.(Shader_Vulkan)

	out: Pipeline_Vulkan

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

	result := vk.CreateDescriptorSetLayout(rend.device, &layout_info, nil, &out.descriptor_set_layout)

	if result != .SUCCESS {
		fmt.println(result)
		panic("Failed to create descriptor set layout!")
	}

	shader_create_infos := [dynamic]vk.ShaderCreateInfoEXT {
		{
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
		},
		{
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
		}
	}

	platform.vkcheck(vk.CreateShadersEXT(rend.device, 2, raw_data(shader_create_infos), nil, raw_data(out.shaders)), "Failed to create pipeline!")

	out.stages = {
		.VERTEX,
		.FRAGMENT
	}

	return out
}

pipeline_vulkan_destroy :: proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal) {
	rend := &rend.(Renderer_Vulkan)
	pipeline := &pipeline.(Pipeline_Vulkan)

	vk.DeviceWaitIdle(rend.device)

	vk.DestroyDescriptorSetLayout(rend.device, pipeline.descriptor_set_layout, nil)
	
	for shader in pipeline.shaders {
		vk.DestroyShaderEXT(rend.device, shader, nil)
	}
}