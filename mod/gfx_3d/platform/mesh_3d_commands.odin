package milk_gfx_3d_platform

import "../../../core/"
import pt "../../../core/platform"

Mesh_New_Proc :: proc(rend: ^core.Renderer_Internal, vertices: []core.Vertex, indices: []u16) -> Mesh_Internal
Mesh_Bind_Buffers_Proc :: proc(rend: ^core.Renderer_Internal, mesh: ^Mesh_Internal)
Mesh_Draw_Proc :: proc(rend: ^core.Renderer_Internal, mesh: ^Mesh_Internal, pos: ^core.Transform_3D, cam_pos: ^core.Transform_3D)
Mesh_Destroy_Proc :: proc(rend: ^core.Renderer_Internal, mesh: ^Mesh_Internal)

Mesh_Commands :: struct {
	new: Mesh_New_Proc,
	bind_buffers: Mesh_Bind_Buffers_Proc,
	draw: Mesh_Draw_Proc,
	destroy: Mesh_Destroy_Proc
}
