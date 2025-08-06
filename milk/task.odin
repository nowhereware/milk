package milk

import "core:fmt"

// # System_Proc
// A procedure typically run as part of a Module. A System has a limited amount of valid proc signatures, which are stored here.
System_Proc :: union {
    proc(world: ^World),
    // An update task
    proc(scene: ^Scene, delta: f64),
    // An update task with a query
    proc(scene: ^Scene, query: Query, delta: f64),
    // A draw task
    proc(scene: ^Scene, alpha: f64, trans_state: ^Transform_State),
    // A draw task with a query
    proc(scene: ^Scene, query: Query, alpha: f64, trans_state: ^Transform_State),
}

// # System
// A cached system run in a module. Stores the procedure itself (a variant of System_Proc) and a Query relating to the system.
System :: struct {
    execute: System_Proc,
    query: Query,
}

ecs_system :: proc(system: System_Proc, queries: ..Query_ID) -> System {
    out: System
    out.execute = system
    out.query.queries = make([dynamic]Query_ID)
    append_elems(&out.query.queries, ..queries)

    return out
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

// Gets a Transform_2D from a state and a singular entity
transform_state_get_2d_single :: proc(state: ^Transform_State, ent: Entity) -> Transform_2D {
    return ecs_storage_get_data(&state.t2d, Transform_2D, ent)
}

// Gets a Transform_3D from a state and a singular entity
transform_state_get_3d_single :: proc(state: ^Transform_State, ent: Entity) -> Transform_3D {
    return ecs_storage_get_data(&state.t3d, Transform_3D, ent)
}

// # Task
// A collection of systems designed to be run in order. Ideally, systems should be sorted into tasks based on mutable data access,
// for example all systems that modify a Transform_2D should be in the same task to minimize mutex waiting.
Task :: struct {
    name: typeid,
    priority: Task_Priority,
    // A list of tasks this task depends on.
    dependencies: [dynamic]typeid,
    systems: [dynamic]System,
}

// Creates a new Task given a list of systems, a type, and a priority.
task_new :: proc($T: typeid, systems: ..System, dependencies: [dynamic]typeid = nil, priority: Task_Priority = .Low) -> (out: Task) {
    fmt.println("Creating task:", typeid_of(T))
    append_elems(&out.systems, ..systems[:])

    out.name = typeid_of(T)
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
        switch t in system.execute {
            case proc(world: ^World): {
                t(&ctx.scene.world)
            }
            case proc(scene: ^Scene, delta: f64): {
                t(ctx.scene, ctx.update_fps)
            }
            case proc(scene: ^Scene, query: Query, delta: f64): {
                t(ctx.scene, system.query, ctx.update_fps)
            }
            case proc(scene: ^Scene, alpha: f64, trans_state: ^Transform_State): {
                t(ctx.scene, ctx.timestep.alpha, trans_state)
            }
            case proc(scene: ^Scene, query: Query, alpha: f64, trans_state: ^Transform_State): {
                t(ctx.scene, system.query, ctx.timestep.alpha, trans_state)
            }
        }
    }
}

// Destroys a given task.
task_destroy :: proc(task: ^Task) {
    if task.dependencies != nil {
        delete(task.dependencies)
    }

    for sys in task.systems {
        delete(sys.query.queries)
    }

    delete(task.systems)
}

// # Task Pipeline State
Task_Pipeline_State :: enum {
    // The Pipeline is not in use, and ready to be claimed by a Worker.
    Ready,
    // The Pipeline is in use, and cannot be accessed by any other Worker.
    In_Use,
    // The Pipeline is out of Tasks.
    Finished,
}

// # Task Pipeline
// A list of Tasks in order of execution with shared dependencies. When a Task is registered into a Schedule, the Task's access requirements (components it will modify) are checked against
// the list of Task_Pipelines within the Schedule. If a Task's access requirements or dependencies do not already exist, the Task is placed into a new Pipeline. Alternatively, if the Task
// requires access to a component that is already claimed by a Pipeline, the Task will be added to that Pipeline. At runtime, Worker threads read through each Schedule, internally reading
// through each Pipeline within the Schedule. Because Pipelines can only be run in order, Workers will individually claim Pipelines for the duration of the Task before releasing the Pipeline,
// with other Workers moving onto the next Pipeline to begin reading.
Task_Pipeline :: struct {
    state: Task_Pipeline_State,
}

// # Schedule Speed Immediate
// A speed for a schedule, denoting that the Schedule should run immediately (every real frame).
Schedule_Speed_Immediate :: struct {}

// # Schedule Speed Fixed
// A speed for a schedule, denoting that the Schedule should run at a fixed FPS.
Schedule_Speed_Fixed :: struct {
    delta: f64,
}

// # Schedule Speed
// Determines the speed at which a given Schedule should run. Union of two types, devolves down to either `Immediate` or a `Fixed` speed.
Schedule_Speed :: union {
    Schedule_Speed_Immediate,
    Schedule_Speed_Fixed,
}

// # Schedule State
// Determines the current state of the Schedule.
Schedule_State :: enum {
    // No tasks are running, and the start proc has not run
    Ready_To_Start,
    // The start proc is running
    Starting,
    // Tasks are running, and tasks are available
    Running,
    // Tasks are running, but no more tasks are available
    Ready_To_End,
    // No tasks are running, and the end proc is running
    Ending,
}

// # Schedule
// Stores a list of tasks, grouped together and sorted under a specific speed. At runtime, tasks are run based on when the Schedule they're in
// has been determined to run at a given frame. To access a Schedule, run `scene_add_task_to_schedule` given a Scene and a Schedule name, which
// is a type name. Milk exposes a default SCHEDULE_DRAW and SCHEDULE_UPDATE, which correspond to an Immediate speed and a speed matching the
// Context's framerate value, respectively.
Schedule :: struct {
    // A list of task pipelines intended to run at the Schedule's specified speed, taking the speed value as a `delta` parameter.
    delta_tasks: [dynamic]Task_Pipeline,
    // A list of task pipelines intended to run in between the frames at which the Schedule runs, taking the value of (accumulator % speed) as an `alpha` parameter.
    alpha_tasks: [dynamic]Task_Pipeline,
    // The speed at which the Schedule is intended to run; how much time should ideally accumulate before the Schedule runs again.
    speed: Schedule_Speed,
    // The current state of the Schedule.
    state: Schedule_State,
    // The local accumulator (time since last run) for the Schedule.
    accumulator: f64,
    // The local alpha (time remainder (modulo) from the accumulator) for the Schedule.
    alpha: f64,
}

schedule_new :: proc(speed: Schedule_Speed) -> Schedule {
    return {
        tasks = make([dynamic]Task),
        speed = speed,
    }
}

schedule_add_task :: proc(schedule: ^Schedule, task: Task) {
    append(&schedule.tasks, task)
}

schedule_destroy :: proc(schedule: ^Schedule) {
    for &task in schedule.tasks {
        task_destroy(&task)
    }

    delete(schedule.tasks)
}

// # SCHEDULE_DEFAULT
// A marker type indicating the default Schedule. Delta tasks will run at the speed specified within the Context.
SCHEDULE_DEFAULT :: struct {}

// # Module
// A collection of Schedules to be added to a Scene.
// To create a module, you'll need a Module type with your desired Schedules as well as a "tag" struct named after your module.
// ## Example:
// ```
// Example_Module_Type :: struct {}
// Example_Schedule_Type :: struct {}
// module: milk.Module
// milk.module_add_schedule(&module, Example_Schedule_Type, Schedule_Speed_Immediate {})
// milk.module_add_task_to_schedule(&module, Example_Schedule_Type, example_task)
// milk.add_module(&ctx, module, Example_Module_Type)
// milk.remove_module(&ctx, Example_Module_Type)
// ```
Module :: struct {
    schedules: [dynamic]Schedule,
    speeds: [dynamic]Schedule_Speed,
    type_map: map[typeid]int,
    index_map: [dynamic]typeid,
}

module_new :: proc(scene: ^Scene) -> (out: Module) {
    out.schedules = make([dynamic]Schedule)
    out.speeds = make([dynamic]Schedule_Speed)
    out.index_map = make([dynamic]typeid)

    // Add default schedule
    module_add_schedule(&out, SCHEDULE_DEFAULT, Schedule_Speed_Fixed { scene.ctx.update_fps })

    return
}

module_add_schedule :: proc(module: ^Module, $name: typeid, speed: Schedule_Speed) {
    id := typeid_of(name)

    if id in module.type_map {
        fmt.eprintln("Error:", id, "already exists in module!")
        return
    }

    append(&module.schedules, schedule_new(speed))
    append(&module.speeds, speed)
    append(&module.index_map, id)
    module.type_map[id] = len(module.schedules) - 1
}

module_add_task_to_schedule :: proc(module: ^Module, $name: typeid, task: Task) {
    id := typeid_of(name)

    if id not_in module.type_map {
        fmt.eprintln("Error:", id, "doesn't exist in module!")
    }

    index := module.type_map[id]

    append(&module.schedules[index].tasks, task)
}

module_destroy :: proc(module: ^Module) {
    for &schedule in module.schedules {
        schedule_destroy(&schedule)
    }

    delete(module.schedules)
    delete(module.speeds)
    delete(module.type_map)
    delete(module.index_map)
}