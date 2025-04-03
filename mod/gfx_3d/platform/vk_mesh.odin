package milk_gfx_3d_platform

import pt "../../../milk/platform"
import "../../../milk"
import "core:fmt"
import vk "vendor:vulkan"

Vk_Mesh :: struct {

}

vk_mesh_new :: proc(cmd: pt.Command_Buffer_Internal, vertices: []milk.Vertex, indices: []u32) -> Mesh_Internal {
	out: Vk_Mesh

	return out
}

vk_mesh_bind_buffers :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal, pos: ^milk.Transform_3D, cam_pos: ^milk.Transform_3D, cam: ^milk.Camera_3D) {
	cmd := cmd.(^pt.Vk_Command_Buffer)
	mesh := &mesh.(Vk_Mesh)
}

vk_mesh_draw :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal) {
	cmd := cmd.(^pt.Vk_Command_Buffer)
	mesh := &mesh.(Vk_Mesh)
}

vk_mesh_destroy :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal) {
	cmd := cmd.(^pt.Vk_Command_Buffer)
	mesh := &mesh.(Vk_Mesh)
}
