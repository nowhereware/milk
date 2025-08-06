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
    // A scene's personal ECS world.
    world: World,
    // A pointer to the Context.
    ctx: ^Context,
    // The current frame of the run.
    frame_count: u64,
    // A map of assets used by the Scene.
    asset_map: map[string]struct {},
    // A list of Schedules registered for the Scene.
    schedules: [dynamic]Schedule,
    // A map mapping Schedule type names to indices in the array.
    schedule_type_map: map[typeid]int,
    // An array mapping indices to Schedule type names.
    schedule_index_map: [dynamic]typeid,

    scene_load: Scene_Load_Proc,
    scene_unload: Scene_Unload_Proc,
}

scene_new :: proc {
    scene_new_empty,
    scene_new_with_procs,
}

// Creates a new scene without any load or unload procedures initialized.
scene_new_empty :: proc(ctx: ^Context) -> (out: ^Scene) {
    out = new(Scene)

    out.world = world_new()
    out.ctx = ctx

    // Add default schedules.
    scene_add_schedule(out, SCHEDULE_DRAW, Schedule_Speed_Immediate {})
    scene_add_schedule(out, SCHEDULE_UPDATE, Schedule_Speed_Fixed { ctx.update_fps })

    return
}

// Creates a new scene with a load and unload procedure.
scene_new_with_procs :: proc(ctx: ^Context, load: Scene_Load_Proc, unload: Scene_Unload_Proc) -> (out: ^Scene) {
    out = new(Scene)

    out.world = world_new()
    out.ctx = ctx

    out.scene_load = load
    out.scene_unload = unload

    // Add default schedules.
    scene_add_schedule(out, SCHEDULE_DRAW, Schedule_Speed_Immediate {})
    scene_add_schedule(out, SCHEDULE_UPDATE, Schedule_Speed_Fixed { ctx.update_fps })

    return
}

// Adds a Schedule to the scene's Schedule list.
scene_add_schedule :: proc(scene: ^Scene, $name: typeid, speed: Schedule_Speed) {
    id := typeid_of(name)
    scene_add_schedule_from_id(scene, id, speed)
}

// Adds a Schedule to the scene's Schedule list.
scene_add_schedule_from_id :: proc(scene: ^Scene, id: typeid, speed: Schedule_Speed) {
    // Ensure a schedule of the same name doesn't exist
    if id in scene.schedule_type_map {
        fmt.eprintln("Error:", id, "already exists in the Scene!")
    }

    // Corrects the indices referred to by the type map, assuming that both schedules and the index map have been updated.
    correct_indices :: proc(scene: ^Scene) {
        for type, index in scene.schedule_index_map {
            scene.schedule_type_map[type] = index
        }
    }

    // Scene schedule array is sorted: Immediate schedules are first, followed by Fixed schedules, which
    // are in ascending order (smallest to largest).
    index := 0
    switch sp in speed {
        case Schedule_Speed_Immediate: {
            // Schedule is simply injected after the last Immediate schedule
            outer: for sched, ind in scene.schedules {
                if type_of(sched.speed) == Schedule_Speed_Fixed {
                    // This is the first index of a Fixed speed, inject here.
                    index = ind
                    break outer
                } else {
                    index += 1
                }
            }
        }
        case Schedule_Speed_Fixed: {
            // Schedule is injected after Immediate schedules and at the index of the first Schedule with a larger speed.
            inner: for sched, ind in scene.schedules {
                if type_of(sched.speed) == Schedule_Speed_Fixed {
                    // Check speed value
                    inner_speed := sched.speed.(Schedule_Speed_Fixed)
                    if inner_speed.delta > sp.delta {
                        // Inject here
                        index = ind
                        break inner
                    }
                } else {
                    index += 1
                }
            }
        }
    }

    // Inject the schedule
    inject_at(&scene.schedules, index, schedule_new(speed))
    inject_at(&scene.schedule_index_map, index, id)
    correct_indices(scene)
}

// Adds a given Task to the given Schedule within the Scene.
scene_add_task_to_schedule :: proc(scene: ^Scene, $name: typeid, task: Task) {
    id := typeid_of(name)

    if id not_in scene.schedule_type_map {
        fmt.eprintln("Error:", id, "is not a valid Schedule!")
    }

    index := scene.schedule_type_map[id]

    schedule_add_task(&scene.schedules[index], task)
}

// Adds a module's Tasks and Schedules to a Scene's Schedules.
scene_add_module :: proc(scene: ^Scene, module: ^Module) {
    // Iter through the module's type map, matching Schedule types.
    for type in module.index_map {
        if type in scene.schedule_type_map {
            // Add tasks from module to scene's corresponding Schedule
            scene_index := scene.schedule_type_map[type]
            module_index := module.type_map[type]
            append_elems(&scene.schedules[scene_index].tasks, ..module.schedules[module_index].tasks[:])
        } else {
            // Schedule does not exist in Scene, add Schedule and all tasks from Schedule.
            module_index := module.type_map[type]
            scene_add_schedule_from_id(scene, type, module.speeds[module_index])
            scene_index := scene.schedule_type_map[type]

            append_elems(&scene.schedules[scene_index].tasks, ..module.schedules[module_index].tasks[:])
        }
    }

    // Delete the module
    module_destroy(module)
}

// Destroys a scene.
scene_destroy :: proc(scene: ^Scene) {
    world_destroy(&scene.world)

    for &schedule in scene.schedules {
        schedule_destroy(&schedule)
    }

    delete(scene.schedules)
    delete(scene.schedule_index_map)
    delete(scene.schedule_type_map)
    delete(scene.asset_map)
    free(scene)
}