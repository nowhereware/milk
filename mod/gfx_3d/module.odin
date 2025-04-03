package milk_gfx_3d

import "../../milk"
import "core:fmt"

DRAW_UNTEXTURED_MESHES_TASK :: struct {}

draw_untextured_meshes :: proc(scene: ^milk.Scene, query: milk.Query, alpha: f64, trans_state: ^milk.Transform_State) {
    viewport := milk.gfx_get_primary_viewport(&scene.ctx.renderer)

    if viewport.current == nil {
        return
    }

    cam_ent := viewport.current.(milk.Entity)
    camera := milk.ecs_get(&scene.world, cam_ent, milk.Camera_3D)
    camera_transform := milk.ecs_get(&scene.world, cam_ent, milk.Transform_3D)
    prev_cam_trans := milk.transform_state_get_3d_single(trans_state, cam_ent)
    camera_transform.mat[3].xyz = camera_transform.mat[3].xyz * cast(f32)alpha + prev_cam_trans.mat[3].xyz * cast(f32)(1.0 - alpha)

    qmesh := milk.ecs_query(&scene.world, query, 0)

    meshes := milk.ecs_query_get(&scene.world, &qmesh, Mesh)
    textures := milk.ecs_query_get(&scene.world, &qmesh, milk.Texture)
    mesh_transforms := milk.ecs_query_get(&scene.world, &qmesh, milk.Transform_3D)
    prev_trans := milk.transform_state_get_3d(trans_state, &qmesh)

    pipeline := milk.asset_get(scene, "shaders/raster2d.gfx", milk.Pipeline_Asset)

    buffer := milk.gfx_get_command_buffer(&scene.ctx.renderer)
    milk.gfx_begin_draw(&scene.ctx.renderer, buffer)

    for i in 0..<len(qmesh.entities) {
        interp := mesh_transforms[i]
        interp.mat[3].xyz = mesh_transforms[i].mat[3].xyz * cast(f32)alpha + prev_trans[i].mat[3].xyz * cast(f32)(1.0 - alpha)

        m := milk.asset_get(&meshes[i].handle, Mesh_Asset)
        t := milk.asset_get(&textures[i].handle, milk.Texture_Asset)

        milk.gfx_bind_graphics_pipeline(buffer, pipeline)

        milk.texture_bind(buffer, t)

        mesh_bind_buffers(buffer, &m, &interp, &camera_transform, &camera)

        milk.pipeline_upload(buffer, &pipeline, "Transform", camera.projection * camera_transform.mat * interp.mat)

        mesh_draw(buffer, &m)

        milk.gfx_unbind_graphics_pipeline(buffer, pipeline)
    }
    
    milk.gfx_end_draw(buffer)

    milk.gfx_submit_buffer(buffer)

    delete(prev_trans)
}

load_module :: proc(scene: ^milk.Scene) -> (out: milk.Module) {
    milk.asset_register_type(scene.ctx, Mesh_Asset, mesh_asset_load, mesh_asset_unload, { ".m3d" })

    milk.module_add_task(&out, milk.task_new(
        DRAW_UNTEXTURED_MESHES_TASK, 
        milk.ecs_system(draw_untextured_meshes, milk.ecs_query_def(&scene.world, milk.ecs_with(Mesh), milk.ecs_with(milk.Transform_3D))),
        type = .Draw
    ))
    return
}