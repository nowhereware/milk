package milk

import "platform"
import "base:runtime"
import "core:strings"
import SDL "vendor:sdl3"

Pipeline_Graphics_New_Proc :: proc(rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> Pipeline_Internal
Pipeline_Destroy_Proc :: proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal)

Pipeline_Commands :: struct {
	graphics_new: Pipeline_Graphics_New_Proc,
	destroy: Pipeline_Destroy_Proc
}

Pipeline_Internal :: union {
	Pipeline_Vulkan
}

pipeline_internal_graphics_new :: proc(conf: Renderer_Type, rend: ^Renderer_Internal, vert: Shader_Internal, frag: Shader_Internal) -> (internal: Pipeline_Internal, commands: Pipeline_Commands) {
	switch conf {
	case .Vulkan: {
		commands.graphics_new = pipeline_vulkan_graphics_new
		commands.destroy = pipeline_vulkan_destroy
	}
	}

	internal = commands.graphics_new(rend, vert, frag)

	return
}

Pipeline_Type :: enum {
	Graphics,
	Compute
}

Pipeline_Asset :: struct {
	type: Pipeline_Type,
	internal: Pipeline_Internal,
	commands: Pipeline_Commands
}

pipeline_graphics_new :: proc(rend: ^Renderer, vert: Shader_Asset, frag: Shader_Asset) -> (out: Pipeline_Asset) {
	out.type = .Graphics
	out.internal, out.commands = pipeline_internal_graphics_new(rend.type, &rend.internal, vert.internal, frag.internal)

	return
}

pipeline_destroy :: proc(rend: ^Renderer, pipeline: ^Pipeline_Asset) {
	pipeline.commands.destroy(&rend.internal, &pipeline.internal)
}

@(private="file")
File_Suffix :: enum {
	Vert,
	Frag,
	Comp,
	Geom,
}

pipeline_asset_load :: proc(server: ^Asset_Server, path: string) {
	file_path := asset_get_full_path(path)
	// Get directory of file
	parent_folder := file_get_parent_folder(file_path)
	file_name := file_get_name(file_path)
	matching_files := file_search(parent_folder, file_name)

	files: [File_Suffix]string
	suffixes_found: [dynamic]File_Suffix

	for file in matching_files {
		suffix := file_get_suffix(file)
		if suffix == ".vert.spv" {
			files[.Vert] = file
			append(&suffixes_found, File_Suffix.Vert)
		} else if suffix == ".frag.spv" {
			files[.Frag] = file
			append(&suffixes_found, File_Suffix.Frag)
		} else if suffix == ".comp.spv" {
			files[.Comp] = file
			append(&suffixes_found, File_Suffix.Comp)
		} else if suffix == ".geom.spv" {
			files[.Geom] = file
			append(&suffixes_found, File_Suffix.Geom)
		}
	}

	// Enumerate through the found shaders and create pipeline(s)
	type: Pipeline_Type
	outer: for suffix in suffixes_found {
		switch suffix {
			case .Comp: {
				type = .Compute
				break outer
			}
			case .Vert: {
				fallthrough
			}
			case .Frag: {
				// Found a fragment, vertex should exist too
				type = .Graphics
				break outer
			}
			case .Geom: {
				// TODO: Implement geometry shader
			}
		}
	}

	switch type {
		case .Compute: {
			// TODO: Implement compute pipeline
		}
		case .Graphics: {
			asset_add(server, path, pipeline_graphics_new(&server.ctx.renderer, asset_get(server, files[.Frag], Shader_Asset), asset_get(server, files[.Vert], Shader_Asset)))
		}
	}
}