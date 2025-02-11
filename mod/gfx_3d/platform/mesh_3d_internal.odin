package milk_gfx_3d_platform

import pt "../../../core/platform"
import "../../../core/"

Mesh_Internal :: union {
	Mesh_Vulkan
}

mesh_internal_new :: proc(conf: core.Renderer_Type, rend: ^core.Renderer_Internal, vertices: []core.Vertex, indices: []u16) -> (internal: Mesh_Internal, commands: Mesh_Commands) {
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
