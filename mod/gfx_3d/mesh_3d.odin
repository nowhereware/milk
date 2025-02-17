package milk_gfx_3d

import "../../milk/"
import "../../milk/platform"

Mesh_New_Proc :: proc(rend: ^milk.Renderer_Internal, vertices: []milk.Vertex, indices: []u16) -> Mesh_Internal
Mesh_Bind_Buffers_Proc :: proc(rend: ^milk.Renderer_Internal, mesh: ^Mesh_Internal)
Mesh_Draw_Proc :: proc(rend: ^milk.Renderer_Internal, mesh: ^Mesh_Internal, pos: ^milk.Transform_3D, cam_pos: ^milk.Transform_3D)
Mesh_Destroy_Proc :: proc(rend: ^milk.Renderer_Internal, mesh: ^Mesh_Internal)

Mesh_Commands :: struct {
	new: Mesh_New_Proc,
	bind_buffers: Mesh_Bind_Buffers_Proc,
	draw: Mesh_Draw_Proc,
	destroy: Mesh_Destroy_Proc
}

Mesh_Internal :: union {
	Mesh_Vulkan
}

mesh_internal_new :: proc(conf: milk.Renderer_Type, rend: ^milk.Renderer_Internal, vertices: []milk.Vertex, indices: []u16) -> (internal: Mesh_Internal, commands: Mesh_Commands) {
	switch conf {
	case .Vulkan: {
		commands.new = mesh_vulkan_new
		commands.bind_buffers = mesh_vulkan_bind_buffers
		commands.draw = mesh_vulkan_draw
		commands.destroy = mesh_vulkan_destroy
	}
	}

	internal = commands.new(rend, vertices, indices)

	return
}


// # Mesh
// A mesh in 3D space. Internally, this only stores an Asset_Handle to the actual Mesh_Asset, which is
// either loaded or accessed upon usage.
Mesh_3D :: struct {
	internal: Mesh_Internal,
	commands: Mesh_Commands
}

mesh_new :: proc(rend: ^milk.Renderer, vertices: []milk.Vertex, indices: []u16) -> (out: Mesh_3D) {
	out.internal, out.commands = mesh_internal_new(rend.type, &rend.internal, vertices, indices)

	return
}

mesh_draw :: proc(rend: ^milk.Renderer, mesh: ^Mesh_3D, pos: ^milk.Transform_3D, cam_pos: ^milk.Transform_3D, cam: ^Camera_3D) {
	mesh.commands.bind_buffers(&rend.internal, &mesh.internal)
	mesh.commands.draw(&rend.internal, &mesh.internal, pos, cam_pos, cam)
}

mesh_destroy :: proc(rend: ^milk.Renderer, mesh: ^Mesh_3D) {
	mesh.commands.destroy(&rend.internal, &mesh.internal)
}

// Mesh primitives


// Creates a primitive triangle in 2D. NOTE: Position list must be ordered in counter-clockwise!
primitive_triangle_new :: proc(rend: ^milk.Renderer, positions: [3]milk.Point_2D, color: milk.Color) -> (out: Mesh_3D) {
	vertices: [3]milk.Vertex
	col := milk.color_as_percent(color).value

	for i := 0; i < len(positions); i += 1 {
		vertices[i] = {positions[i], {col.r, col.g, col.b}}
	}

	indices: []u16 = {0, 1, 2}

	out.internal, out.commands = mesh_internal_new(rend.type, &rend.internal, vertices[:], indices)

	return
}