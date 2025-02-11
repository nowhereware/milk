package milk_core

System :: union {
    proc(world: ^World),
    // Typically an update task
    proc(world: ^Scene, delta: f64),
    // Typically a draw task
    proc(world: ^World, delta: f64, trans_state: ^Transform_State),
}

Task_Type :: enum {
    Update,
    Draw
}

Task_Priority :: enum {
    High,
    Medium,
    Low
}

Task :: struct {
    type: Task_Type,
    priority: Task_Priority,
    systems: [dynamic]System,
}

// The prior state of each Transform in the World, used for interpolating rendering
// Stored in the form of each type's component storage
Transform_State :: struct {
    t2d: Storage,
    t3d: Storage
}

transform_state_new :: proc(t2d_ptr: ^Storage, t3d_ptr: ^Storage) -> (out: Transform_State) {
    out.t2d = t2d_ptr^
    out.t3d = t3d_ptr^
    return
}

task_new :: proc(systems: ..System, type: Task_Type = .Update, priority: Task_Priority = .Low) -> (out: Task) {
    append_elems(&out.systems, ..systems[:])

    out.type = type
    out.priority = priority

    return
}

task_run :: proc(task: ^Task, ctx: ^Context, delta: f64, trans_state: ^Transform_State) {
    for system in task.systems {
        switch t in system {
            case proc(world: ^World): {
                t(&ctx.scene.world)
            }
            case proc(scene: ^Scene, delta: f64): {
                t(ctx.scene, delta)
            }
            case proc(world: ^World, delta: f64, trans_state: ^Transform_State): {
                t(&ctx.scene.world, delta, trans_state)
            }
        }
    }
}

task_destroy :: proc(task: ^Task) {
    delete(task.systems)
}

// # Module
// A collection of Tasks to be operated on at runtime.
// To create a module, you'll need a Module type with your desired tasks as well as a "tag" struct named after your module.
// ## Example:
// ```
// Example_Module_Type :: struct {}
// module := Module { tasks = task_list }
// core.add_module(&ctx, module, Example_Module_Type)
// core.remove_module(&ctx, Example_Module_Type)
// ```
Module :: struct {
    tasks: [dynamic]Task,
}

module_new :: proc {
    module_new_empty,
    module_new_with_tasks,
}

module_new_empty :: proc() -> (out: Module) {
    out.tasks = make([dynamic]Task)

    return
}

module_new_with_tasks :: proc(task_list: [dynamic]Task) -> (out: Module) {
    out.tasks = task_list

    return
}

module_destroy :: proc(module: ^Module) {
    for &task in module.tasks {
        task_destroy(&task)
    }

    delete(module.tasks)
}