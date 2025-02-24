package milk

import "core:fmt"

Scene_Load_Proc :: #type proc(scene: ^Scene)
Scene_Unload_Proc :: #type proc(scene: ^Scene)

// # Scene
// A user-defined collection of tasks and data to be operated on by the Context. Only one scene can be run at a time,
// although many can be loaded until they are needed to be used.
// ## Usage
// To create a new scene, use the `scene_new` collection of procedures. Generally, the preferred method is to pass the Scene's
// desired load and unload procs using the `scene_new_with_procs` variant, in order to avoid accidentally forgetting the procs
// and not actually loading anything into the Scene.
Scene :: struct {
    // A scene's personal ECS world
    world: World,
    // A pointer to the Context
    ctx: ^Context,
    // The current frame of the run.
    frame_count: u64,
    // The tasks registered to run.
    task_list: [dynamic]Task,

    scene_load: Scene_Load_Proc,
    scene_unload: Scene_Unload_Proc,
}

scene_new :: proc {
    scene_new_empty,
    scene_new_with_procs,
}

// Creates a new scene without any load or unload procedures initialized.
scene_new_empty :: proc() -> (ctx: ^Context, out: ^Scene) {
    out = new(Scene)

    out.world = world_new()
    out.ctx = ctx

    return
}

// Creates a new scene with a load and unload procedure.
scene_new_with_procs :: proc(ctx: ^Context, load: Scene_Load_Proc, unload: Scene_Unload_Proc) -> (out: ^Scene) {
    out = new(Scene)

    out.world = world_new()
    out.ctx = ctx

    out.scene_load = load
    out.scene_unload = unload

    return
}

// Adds a module to the scene's Task list.
scene_add_module :: proc(scene: ^Scene, module: Module) {
    for task in module.tasks {
        append(&scene.task_list, task)
    }
}

// Adds a given task to a scene's module.
scene_add_task :: proc(scene: ^Scene, task: Task) {
    append(&scene.task_list, task)
}

// Destroys a scene.
scene_destroy :: proc(scene: ^Scene) {
    world_destroy(&scene.world)

    for &task in scene.task_list {
        task_destroy(&task)
    }

    delete(scene.task_list)
    free(scene)
}