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

@(private="file")
File_Data :: struct {
	file_name: string,
	files_found: [File_Suffix]string,
	suffixes_found: [dynamic]File_Suffix,
	ctx: runtime.Context,
}

@(private="file")
enumerate_file :: proc "cdecl" (data: rawptr, dirname, fname: cstring) -> SDL.EnumerationResult {
	d := cast(^File_Data)data
	context = d.ctx
	fname_str := strings.clone_from_cstring(fname, context.temp_allocator)

	if strings.contains(fname_str, d.file_name) {
		if strings.has_prefix(fname_str, ".vert.spv") {
			append(&d.suffixes_found, File_Suffix.Vert)
			d.files_found[.Vert] = fname_str
		} else if strings.has_prefix(fname_str, ".frag.spv") {
			append(&d.suffixes_found, File_Suffix.Frag)
			d.files_found[.Frag] = fname_str
		} else if strings.has_prefix(fname_str, ".comp.spv") {
			append(&d.suffixes_found, File_Suffix.Comp)
			d.files_found[.Comp] = fname_str
		} else if strings.has_prefix(fname_str, ".geom.spv") {
			append(&d.suffixes_found, File_Suffix.Geom)
			d.files_found[.Geom] = fname_str
		}
	}

	return .CONTINUE
}

pipeline_asset_load :: proc(server: ^Asset_Server, path: string) {
	file_path := asset_get_full_path(path)
	// Get directory of file
	slash_index := strings.last_index(file_path, "/")
	folder_path, ok := strings.substring_to(file_path, slash_index)
	file_name, file_ok := strings.substring_from(file_path, slash_index + 1)
	folder_path_c := strings.clone_to_cstring(folder_path, context.temp_allocator)
	file_data: File_Data = {
		file_name = file_name,
		ctx = context
	}

	success := SDL.EnumerateDirectory(folder_path_c, enumerate_file, &file_data)

	// Enumerate through the found shaders and create pipeline(s)
	type: Pipeline_Type
	sub_slash_index := strings.last_index(path, "/")
	sub_path, sub_ok := strings.substring_to(path, sub_slash_index)
	outer: for suffix in file_data.suffixes_found {
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
			frag_strings := [?]string { sub_path, "/", file_data.files_found[.Frag] }
			vert_strings := [?]string { sub_path, "/", file_data.files_found[.Vert] }
			frag_path, frag_ok := strings.concatenate(frag_strings[:], context.temp_allocator)
			vert_path, vert_ok := strings.concatenate(vert_strings[:], context.temp_allocator)
			asset_add(server, path, pipeline_graphics_new(&server.ctx.renderer, asset_get(server, frag_path, Shader_Asset), asset_get(server, vert_path, Shader_Asset)))
		}
	}
}