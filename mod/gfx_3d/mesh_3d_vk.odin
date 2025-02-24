package milk_gfx_3d

import pt "../../milk/platform"
import "../../milk"
import "core:fmt"
import vk "vendor:vulkan"

Mesh_Vulkan :: struct {
	vertex: pt.Buffer_Vulkan,
	index: pt.Buffer_Vulkan,
	uniform_buffers: [pt.FRAME_COUNT]pt.Buffer_Vulkan,
	uniform_buffers_mapped: [pt.FRAME_COUNT]rawptr
}

mesh_vk_new :: proc(rend: ^milk.Renderer_Internal, vertices: []milk.Vertex, indices: []u16) -> Mesh_Internal {
	out: Mesh_Vulkan
	rend := &rend.(milk.Vk_Renderer)

	out.vertex = pt.vk_create_vertex_buffer(rend, vertices)
	out.index = pt.vk_create_index_buffer(rend, indices)
	out.uniform_buffers, out.uniform_buffers_mapped = pt.vk_create_uniform_buffers(rend)

	return out
}

mesh_vk_bind_buffers :: proc(rend: ^milk.Renderer_Internal, mesh: ^Mesh_Internal) {
	rend := &rend.(milk.Vk_Renderer)
	mesh := &mesh.(Mesh_Vulkan)

	vertex_buffers := [?]vk.Buffer{mesh.vertex.buffer}
	offsets := [?]vk.DeviceSize{0}
	vk.CmdBindVertexBuffers(rend.command_buffers[rend.current_frame], 0, 1, &vertex_buffers[0], &offsets[0])
	vk.CmdBindIndexBuffer(rend.command_buffers[rend.current_frame], mesh.index.buffer, 0, .UINT16)
}

mesh_vk_draw :: proc(rend: ^milk.Renderer_Internal, mesh: ^Mesh_Internal, pos: ^milk.Transform_3D, cam_pos: ^milk.Transform_3D, cam: ^Camera_3D) {
	rend := &rend.(milk.Vk_Renderer)
	mesh := &mesh.(Mesh_Vulkan)

	ubo := milk.Uniform_Buffer_Object {
		model = pos.mat,
		view = cam_pos.mat,
		proj = cam.projection
	}

	mesh.uniform_buffers_mapped[rend.swapchain.current_frame] = &ubo

	vk.CmdDrawIndexed(rend.command_buffers[rend.current_frame], cast(u32)mesh.index.length, 1, 0, 0, 0)
}

mesh_vk_destroy :: proc(rend: ^milk.Renderer_Internal, mesh: ^Mesh_Internal) {
	rend := &rend.(milk.Vk_Renderer)
	mesh := &mesh.(Mesh_Vulkan)

	for i := 0; i < rend.frame_count; i += 1 {
		vk.DestroyBuffer(rend.device.ptr, mesh.uniform_buffers[i].buffer, nil)
		vk.FreeMemory(rend.device.ptr, mesh.uniform_buffers[i].memory, nil)
	}

	vk.FreeMemory(rend.device.ptr, mesh.index.memory, nil)
	vk.DestroyBuffer(rend.device.ptr, mesh.index.buffer, nil)

	vk.FreeMemory(rend.device.ptr, mesh.vertex.memory, nil)
	vk.DestroyBuffer(rend.device.ptr, mesh.vertex.buffer, nil)
}
