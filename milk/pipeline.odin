package milk

import pt "platform"
import "base:runtime"
import "core:fmt"
import "core:strings"
import SDL "vendor:sdl3"

// # Pipeline Asset
// A pipeline used by the GPU for processing shader code.
Pipeline_Asset :: struct {
	// The type of the Pipeline
	type: pt.Pipeline_Type,
	// A map mapping buffer binding indices to Buffer(s).
	buffer_map: map[int]Buffer,
	internal: pt.Pipeline_Internal,
	commands: pt.Pipeline_Commands
}

pipeline_graphics_new :: proc(buffer: Command_Buffer, vert: Shader_Asset, frag: Shader_Asset) -> (out: Pipeline_Asset) {
	out.type = .Graphics
	out.internal, out.commands = pt.pipeline_internal_graphics_new(buffer.internal, vert.internal, frag.internal)

	return
}

pipeline_destroy :: proc(buffer: Command_Buffer, pipeline: ^Pipeline_Asset) {
	pipeline.commands.destroy(buffer.internal, &pipeline.internal)
}

pipeline_upload :: proc {
	pipeline_upload_mat4,
}

pipeline_upload_mat4 :: proc(buffer: Command_Buffer, pipeline: ^Pipeline_Asset, name: string, mat: Mat4) {
	pipeline.commands.upload_mat4(buffer.internal, &pipeline.internal, name, mat)
}

@(private="file")
File_Suffix :: enum {
	Vert,
	Frag,
	Comp,
	Geom,
}

pipeline_asset_load :: proc(scene: ^Scene, path: string) {
	immediate_parent := file_get_parent_folder(path)
	file_path := asset_get_full_path(path)
	// Get directory of file
	parent_folder := file_get_parent_folder(file_path)
	file_name := file_get_name(file_path)
	matching_files := file_search(parent_folder, file_name)

	source_suffix := file_get_suffix(path)
	type: pt.Pipeline_Type

	if source_suffix == ".gfx" {
		type = .Graphics
	} else if source_suffix == ".comp" {
		type = .Compute
	}

	files: [File_Suffix]string
	suffixes_found: [dynamic]File_Suffix

	for file in matching_files {
		suffix := file_get_suffix(file)
		if suffix == ".gfx.vert" {
			files[.Vert] = strings.concatenate({immediate_parent, file})
			append(&suffixes_found, File_Suffix.Vert)
		} else if suffix == ".gfx.frag" {
			files[.Frag] = strings.concatenate({immediate_parent, file})
			append(&suffixes_found, File_Suffix.Frag)
		} else if suffix == ".comp" {
			files[.Comp] = strings.concatenate({immediate_parent, file})
			append(&suffixes_found, File_Suffix.Comp)
		} else if suffix == ".gfx.geom" {
			files[.Geom] = strings.concatenate({immediate_parent, file})
			append(&suffixes_found, File_Suffix.Geom)
		}
	}

	switch type {
		case .Compute: {
			// TODO: Implement compute pipeline
		}
		case .Graphics: {
			asset_add(
				scene, 
				path, 
				pipeline_graphics_new(
					gfx_get_command_buffer(&scene.ctx.renderer), 
					asset_get(scene, files[.Vert], Shader_Asset, true), 
					asset_get(scene, files[.Frag], Shader_Asset, true)
				),
				Asset_Dependent {
					dependencies = {
						asset_load(scene, files[.Vert], true),
						asset_load(scene, files[.Frag], true)
					}
				}
			)
		}
	}

	delete(suffixes_found)
	delete(matching_files)
}

pipeline_asset_unload :: proc(scene: ^Scene, path: string) {
	pipeline := asset_get(scene, path, Pipeline_Asset)

	buffer := gfx_get_command_buffer(&scene.ctx.renderer)

	pipeline_destroy(buffer, &pipeline)

	storage := asset_server_get_storage(&scene.ctx.asset_server, Pipeline_Asset)

	asset_storage_remove(storage, path, Pipeline_Asset)
}