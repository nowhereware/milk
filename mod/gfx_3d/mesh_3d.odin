package milk_gfx_3d

import pt3d "platform"

import "../../core/"
import "../../core/platform"

// # Mesh
// A mesh in 3D space. Internally, this only stores an Asset_Handle to the actual Mesh_Asset, which is
// either loaded or accessed upon usage.
Mesh_3D :: struct {
	internal: pt3d.Mesh_Internal,
	commands: pt3d.Mesh_Commands
}

mesh_new :: proc(rend: ^core.Renderer, vertices: []core.Vertex, indices: []u16) -> (out: Mesh_3D) {
	out.internal, out.commands = pt3d.mesh_internal_new(rend.type, &rend.internal, vertices, indices)

	return
}

mesh_draw :: proc(rend: ^core.Renderer, mesh: ^Mesh_3D, pos: ^core.Transform_3D, cam_pos: ^core.Transform_3D, cam: ^Camera_3D) {
	mesh.commands.bind_buffers(&rend.internal, &mesh.internal)
	mesh.commands.draw(&rend.internal, &mesh.internal, pos, cam_pos, cam)
}

mesh_destroy :: proc(rend: ^core.Renderer, mesh: ^Mesh_3D) {
	mesh.commands.destroy(&rend.internal, &mesh.internal)
}

// Mesh primitives


// Creates a primitive triangle in 2D. NOTE: Position list must be ordered in counter-clockwise!
primitive_triangle_new :: proc(rend: ^core.Renderer, positions: [3]core.Point_2D, color: core.Color) -> (out: Mesh_3D) {
	vertices: [3]math.Vertex
	col := math.color_as_percent(color).value

	for i := 0; i < len(positions); i += 1 {
		vertices[i] = {positions[i], {col.r, col.g, col.b}}
	}

	indices: []u16 = {0, 1, 2}

	out.internal, out.commands = platform_3d.mesh_internal_new(rend.type, &rend.internal, vertices[:], indices)

	return
}