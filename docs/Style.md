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