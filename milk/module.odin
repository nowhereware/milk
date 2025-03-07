package milk

import "core:fmt"

// # System
// A procedure typically run as part of a Module. A System has a limited amount of valid proc signatures, which are stored here.
System :: union {
    proc(world: ^World),
    // Typically an update task
    proc(scene: ^Scene, delta: f64),
    // Typically a draw task
    proc(scene: ^Scene, alpha: f64, trans_state: ^Transform_State),
}

// # Task Type
// The type of a task. An Update task will run based on a fixed timestep system, while a draw task will not.
Task_Type :: enum {
    Update,
    Draw
}

// # Task Priority
// The priority of the task. High priority tasks should be stored and run first, followed by the other priorities in order.
// Note that tasks of the same priority are not the only tasks that will run at the same time, they just start first. A high
// priority task that takes long enough may run at the same time as a medium or even low priority task.
Task_Priority :: enum {
    High,
    Medium,
    Low
}

// # Transform State
// The prior state of each Transform in the World, used for interpolating rendering.
// Stored in the form of each type's component storage.
Transform_State :: struct {
    t2d: Storage,
    t3d: Storage
}

// Creates a new Transform state by copying the old Transform state.
transform_state_new :: proc(t2d_ptr: ^Storage, t3d_ptr: ^Storage) -> (out: Transform_State) {
    ecs_storage_copy(t2d_ptr, &out.t2d)
    ecs_storage_copy(t3d_ptr, &out.t3d)
    return
}

transform_state_update :: proc(world: ^World, state: ^Transform_State) {
    ecs_storage_copy(world_get_storage(world, Transform_2D), &state.t2d)
    ecs_storage_copy(world_get_storage(world, Transform_3D), &state.t3d)
}

transform_state_destroy :: proc(state: ^Transform_State) {
    ecs_storage_destroy(&state.t2d)
    ecs_storage_destroy(&state.t3d)
}

// Gets a list of Transform_2D(s) from a state and a list of query entities.
transform_state_get_2d :: proc(state: ^Transform_State, query: ^Query_Result) -> (out: [dynamic]Transform_2D) {
    for ent in query.entities {
        append(&out, ecs_storage_get_data(&state.t2d, Transform_2D, ent))
    }
    
    return
}

// Gets a list of Transform_3D(s) from a state and a list of query entities.
transform_state_get_3d :: proc(state: ^Transform_State, query: ^Query_Result) -> (out: [dynamic]Transform_3D) {
    for ent in query.entities {
        append(&out, ecs_storage_get_data(&state.t3d, Transform_3D, ent))
    }

    return
}

// # Task
// A collection of systems designed to be run in order. Ideally, systems should be sorted into tasks based on mutable data access,
// for example all systems that modify a Transform_2D should be in the same task to minimize mutex waiting.
Task :: struct {
    name: typeid,
    type: Task_Type,
    priority: Task_Priority,
    // A list of tasks this task depends on.
    dependencies: [dynamic]typeid,
    systems: [dynamic]System,
}

// Creates a new Task given a list of systems, a type, and a priority.
task_new :: proc($T: typeid, systems: ..System, dependencies: [dynamic]typeid = nil, type: Task_Type = .Update, priority: Task_Priority = .Low) -> (out: Task) {
    fmt.println("Creating task:", typeid_of(T))
    append_elems(&out.systems, ..systems[:])

    out.name = typeid_of(T)
    out.type = type
    out.priority = priority

    if out.dependencies == nil {
        out.dependencies = make([dynamic]typeid)
    } else {
        out.dependencies = dependencies
    }

    return
}

// Runs a task given a list of required data.
task_run :: proc(task: ^Task, ctx: ^Context, trans_state: ^Transform_State) {
    for system in task.systems {
        switch t in system {
            case proc(world: ^World): {
                t(&ctx.scene.world)
            }
            case proc(scene: ^Scene, delta: f64): {
                t(ctx.scene, ctx.update_fps)
            }
            case proc(scene: ^Scene, alpha: f64, trans_state: ^Transform_State): {
                t(ctx.scene, ctx.timestep.alpha, trans_state)
            }
        }
    }
}

// Destroys a given task.
task_destroy :: proc(task: ^Task) {
    if task.dependencies != nil {
        delete(task.dependencies)
    }
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

module_add_task :: proc(module: ^Module, task: Task) {
    append(&module.tasks, task)
}

module_destroy :: proc(module: ^Module) {
    for &task in module.tasks {
        task_destroy(&task)
    }

    delete(module.tasks)
}