package milk_gfx_3d

import "core:fmt"
import "../../milk/"
import pt "../../milk/platform"
import pt3d "platform"
import "core:crypto"
import "core:encoding/uuid"

// # Mesh
// A mesh in 3D space. Internally, this only stores an Asset_Handle to the actual Mesh_Asset, which is
// either loaded or accessed upon usage.
Mesh :: struct {
	handle: milk.Asset_Handle,
}

// # Mesh_Asset
// A platform-dependent implementation of a 3D mesh. This is an asset type stored within an asset server,
// and should be accessed by running `asset_get` on either a handle or a path.
Mesh_Asset :: struct {
	internal: pt3d.Mesh_Internal,
	commands: pt3d.Mesh_Commands
}

mesh_new :: proc(cmd: milk.Command_Buffer, vertices: []milk.Vertex, indices: []u32) -> (out: Mesh_Asset) {
	out.internal, out.commands = pt3d.mesh_internal_new(cmd.internal, vertices, indices)

	return
}

mesh_bind_buffers :: proc(cmd: milk.Command_Buffer, mesh: ^Mesh_Asset, pos: ^milk.Transform_3D, cam_pos: ^milk.Transform_3D, cam: ^milk.Camera_3D) {
	mesh.commands.bind_buffers(cmd.internal, &mesh.internal, pos, cam_pos, cam)
}

mesh_draw :: proc(cmd: milk.Command_Buffer, mesh: ^Mesh_Asset) {
	mesh.commands.draw(cmd.internal, &mesh.internal)
}

mesh_destroy :: proc(cmd: milk.Command_Buffer, mesh: ^Mesh_Asset) {
	mesh.commands.destroy(cmd.internal, &mesh.internal)
}

// Mesh primitives

// Creates a primitive triangle in 2D. NOTE: Position list must be ordered in counter-clockwise!
primitive_triangle_new :: proc(scene: ^milk.Scene, positions: [3]milk.Point_3D) -> (out: Mesh) {
	vertices: [3]milk.Vertex

	for i := 0; i < len(positions); i += 1 {
		vertices[i] = {
			position = positions[i], 
			normal = { 0.0, 0.0, 0.0 }
		}
	}

	indices: []u32 = { 0, 1, 2 }

	buffer := milk.gfx_get_command_buffer(&scene.ctx.renderer)

	asset: Mesh_Asset
	asset.internal, asset.commands = pt3d.mesh_internal_new(buffer.internal, vertices[:], indices)

	// Submit the buffer
	milk.gfx_submit_buffer(buffer)
	
	triangle_name := milk.asset_generate_name()

	milk.asset_add(scene, triangle_name, asset, milk.Asset_Standalone {})

	out.handle = milk.asset_load(scene, triangle_name, Mesh_Asset, true)

	return
}

primitive_quad_new :: proc(scene: ^milk.Scene, width, height: f32) -> (out: Mesh) {
	vertices := [4]milk.Vertex {
		{
			// Top right
			position = { width / 2, height / 2, 0 },
			normal = { 1, 0, 0 }
		},
		{
			// Bottom right
			position = { width / 2, -height / 2, 0 },
			normal = { 0, 0, 1 }
		},
		{
			// Bottom left
			position = { -width / 2, -height / 2, 0 },
			normal = { 0, 1, 0 }
		},
		{
			// Top left
			position = { -width / 2, height / 2, 0 },
			normal = { 0, 0, 0 }
		}
	}

	indices := [?]u32 {
		0, 1, 3,
		1, 2, 3
	}

	buffer := milk.gfx_get_command_buffer(&scene.ctx.renderer)

	asset: Mesh_Asset
	asset.internal, asset.commands = pt3d.mesh_internal_new(buffer.internal, vertices[:], indices[:])

	// Submit buffer
	milk.gfx_submit_buffer(buffer)

	quad_name := milk.asset_generate_name()

	milk.asset_add(scene, quad_name, asset, milk.Asset_Standalone {})

	out.handle = milk.asset_load(scene, quad_name, Mesh_Asset, true)

	return
}

mesh_asset_load :: proc(scene: ^milk.Scene, path: string) {
	// TODO
}

mesh_asset_unload :: proc(scene: ^milk.Scene, path: string) {
	storage := milk.asset_server_get_storage(&scene.ctx.asset_server, Mesh_Asset)

    mesh := milk.asset_storage_get_ptr(storage, path, Mesh_Asset)

	buffer := milk.gfx_get_command_buffer(&scene.ctx.renderer)

    mesh_destroy(buffer, mesh)

    milk.asset_storage_remove(storage, path, Mesh_Asset)
}