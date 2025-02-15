package milk

// # System
// A procedure typically run as part of a Module. A System has a limited amount of valid proc signatures, which are stored here.
System :: union {
    proc(world: ^World),
    // Typically an update task
    proc(scene: ^Scene, delta: f64),
    // Typically a draw task
    proc(scene: ^Scene, delta: f64, trans_state: ^Transform_State),
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
    out.t2d = ecs_storage_copy(t2d_ptr)
    out.t3d = ecs_storage_copy(t3d_ptr)
    return
}

// # Task
// A collection of systems designed to be run in order. Ideally, systems should be sorted into tasks based on mutable data access,
// for example all systems that modify a Transform_2D should be in the same task to minimize mutex waiting.
Task :: struct {
    type: Task_Type,
    priority: Task_Priority,
    systems: [dynamic]System,
}

// Creates a new Task given a list of systems, a type, and a priority.
task_new :: proc(systems: ..System, type: Task_Type = .Update, priority: Task_Priority = .Low) -> (out: Task) {
    append_elems(&out.systems, ..systems[:])

    out.type = type
    out.priority = priority

    return
}

// Runs a task given a list of required data.
task_run :: proc(task: ^Task, ctx: ^Context, delta: f64, trans_state: ^Transform_State) {
    for system in task.systems {
        switch t in system {
            case proc(world: ^World): {
                t(&ctx.scene.world)
            }
            case proc(scene: ^Scene, delta: f64): {
                t(ctx.scene, delta)
            }
            case proc(world: ^Scene, delta: f64, trans_state: ^Transform_State): {
                t(ctx.scene, delta, trans_state)
            }
        }
    }
}

// Destroys a given task.
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