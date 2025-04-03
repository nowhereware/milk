# Style

We gladly accept new contributions to the engine, with just a few guidelines in terms of style.

## General

Types and functions generally follow the overarching style of Odin itself, using `Ada_Case` for types and `snake_case` for procedures.

## Objects

When creating a type with associated procedures (aka an Object), the type generally must have a creation and deletion procedure, named here as
`{type_name}_new` and `{type_name_}_destroy`. For the new function, the returned object is named within the function as `out` and is part of the
procedure's signature in the return type, e.g. `thing_new :: proc() -> (out: Thing)`.

### Platform-specific

For objects that are platform-specific, there are a few more style subrules. Generally, most platform-specific types are designed to support multiple
platforms, in which case the top-level version is placed at the top of the engine, followed by two additional types: `{Type_Name}_Internal` and
`{Type_Name}_Commands`. Type_Name_Internal is a union of all platform implementations of the type, and Type_Name_Commands is a struct containing procedure pointers
for specific commands to be run on the type's underlying implementation. Type_Name itself usually just consists of a struct containing Type_Name_Internal and
Type_Name_Commands. For the platform implementation itself, it is placed alongside the commands and internal types in the `platform/` folder. For the platform implementation,
the name typically follows the style of `{Type_Name}_{Platform}`, and must implement each procedure defined in `{Type_Name}_Commands`. These procedures typically follow the
style of `{type_name}_{platform}_{command_name}`. For additional procedures that are not defined as a required command, they must be named as `{platform}_{procedure_name}`.

## Namespacing

Within the core milk/ folder, any procedures or types that are not platform-specific should ideally be located in the same package as the rest of Milk. The reason for this is that we try to avoid
the overuse of subpackages as it regularly leads to issues with import recursion. Instead, you should name your types and procedures like so:
- As stated in the #Objects section, any procedures that create, destroy, or run over a type specifically should be prefixed with the objects name, ex. `{type_name}_{proc_name}`
- Procedures that are designed to be more general, even if they run over a specific type, should be prefixed using a desired "package" name. For example, multiple procedures in renderer.odin
and command_pool.odin are prefixed using `gfx_` instead of `renderer_` or `command_pool_`, because they're designed to be generally used in the context of the program and not specifically in
regards to the Renderer or Command Buffer, respectively.

Types and procedures within modules in the /mod subfolders generally don't need to follow the second rule, as they're already stored in subpackages and thus already have a namespace specifier.

## Functionality

Milk is designed to be highly extensible and highly concurrent, and as such when adding functionality to Milk there's 2 primary considerations: platform support and thread safety.
As stated above, any functionality that's designed to have different implementations for different platforms should follow the platform-specific guidelines, using a union for each platform implementation
and a struct containing a v-table of procedures that run over the union, which at runtime is filled in with the platform-specific procedures. For thread safety, what needs to be considered is that any and every task
can and will run on separate threads. As such, any code that should be accessed by a task needs to ensure that data modified as a result of the task is safely guarded. For example, both ECS storages and Asset storages utilize
mutexes to ensure that multiple tasks don't modify a given storage at a time as that may invalidate the given storage's dense storage array for another task. Alternatively, data that needs to only exist for a specific
worker thread may utilize a global `@(thread_local)` variable to ensure that the worker only accesses its specific data. This practice can be seen in the debug Profiler, where each worker has a thread local profiler
that it can access. The advantage of using a global variable for this over a local variable inside the Worker_Thread_Data struct is that a global can be accessed within any task, whereas local thread data is not passed to tasks and as such cannot be directly accessed when needed.