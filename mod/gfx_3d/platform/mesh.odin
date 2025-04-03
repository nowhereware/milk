package milk_gfx_3d_platform

import "../../../milk"
import pt "../../../milk/platform"

mesh_new_proc :: proc(cmd: pt.Command_Buffer_Internal, vertices: []milk.Vertex, indices: []u32) -> Mesh_Internal
mesh_bind_buffers_proc :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal, pos: ^milk.Transform_3D, cam_pos: ^milk.Transform_3D, cam: ^milk.Camera_3D)
mesh_draw_proc :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal)
mesh_destroy_proc :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal)

Mesh_Commands :: struct {
	new: mesh_new_proc,
	bind_buffers: mesh_bind_buffers_proc,
	draw: mesh_draw_proc,
	destroy: mesh_destroy_proc
}

Mesh_Internal :: union {
	Vk_Mesh,
    Gl_Mesh,
}

mesh_internal_new :: proc(cmd: pt.Command_Buffer_Internal, vertices: []milk.Vertex, indices: []u32) -> (internal: Mesh_Internal, commands: Mesh_Commands) {
	switch c in cmd {
	    case ^pt.Vk_Command_Buffer: {
	    	commands.new = vk_mesh_new
	    	commands.bind_buffers = vk_mesh_bind_buffers
	    	commands.draw = vk_mesh_draw
	    	commands.destroy = vk_mesh_destroy
	    }
        case ^pt.Gl_Command_Buffer: {
            commands.new = gl_mesh_new
            commands.bind_buffers = gl_mesh_bind_buffers
            commands.draw = gl_mesh_draw
			commands.destroy = gl_mesh_destroy
        }
	}

	internal = commands.new(cmd, vertices, indices)

	return
}