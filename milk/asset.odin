package milk

import "core:crypto"
import "core:encoding/uuid"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"

ASSET_PREFIX :: "assets/"

asset_loader_proc :: #type proc(scene: ^Scene, path: string)
asset_unloader_proc :: #type proc(scene: ^Scene, path: string)

// # Asset_Server
// A server used to access assets of variable but preregistered types. Stored within the server
// is a dynamic array of Asset_Storage(s), which internally keep track of the assets loaded. To
// access an asset, use `asset_get` and pass either an Asset_Handle (which is usually found within
// component types), or the direct server and a filepath, along with the type of the desired asset.
Asset_Server :: struct {
    type_map: map[typeid]int,
    asset_map: map[string]Asset_Handle,
    suffix_map: map[string]typeid,
    storages: [dynamic]Asset_Storage,
    load_procs: [dynamic]asset_loader_proc,
    unload_procs: [dynamic]asset_unloader_proc,
}

asset_server_new :: proc() -> (out: Asset_Server) {
    out.type_map = {}
    out.asset_map = {}
    out.suffix_map = {}
    out.storages = make([dynamic]Asset_Storage)
    out.load_procs = make([dynamic]asset_loader_proc)
    out.unload_procs = make([dynamic]asset_unloader_proc)

    return
}

asset_server_destroy :: proc(server: ^Asset_Server) {
    delete_map(server.type_map)
    delete_map(server.suffix_map)

    for &storage in server.storages {
        asset_storage_destroy(&storage)
    }

    delete(server.storages)
    delete(server.load_procs)
    delete(server.unload_procs)
    delete(server.asset_map)
}

asset_server_get_storage :: proc {
    asset_server_get_storage_from_type,
    asset_server_get_storage_from_id,
}

asset_server_get_storage_from_type :: proc(server: ^Asset_Server, $T: typeid) -> ^Asset_Storage {
    return &server.storages[server.type_map[typeid_of(T)]]
}

asset_server_get_storage_from_id :: proc(server: ^Asset_Server, id: typeid) -> ^Asset_Storage {
    return &server.storages[server.type_map[id]]
}

asset_register_type :: proc(
    ctx: ^Context, 
    $T: typeid, 
    load_proc: asset_loader_proc, 
    unload_proc: asset_unloader_proc,
    suffixes: []string,
) {
    id := typeid_of(T)
    if id in ctx.asset_server.type_map {
        // Type already is registered, return
        return
    }

    append(&ctx.asset_server.storages, asset_storage_new(T))
    ctx.asset_server.type_map[id] = len(ctx.asset_server.storages) - 1
    append(&ctx.asset_server.load_procs, load_proc)
    append(&ctx.asset_server.unload_procs, unload_proc)

    for suffix in suffixes {
        if suffix in ctx.asset_server.suffix_map {
            panic("Error: attempted to redefine suffix!")
        }

        ctx.asset_server.suffix_map[suffix] = id
    }
}

// Gets a typeid from a passed suffix
asset_suffix_type :: proc(server: ^Asset_Server, suffix: string) -> typeid {
    if suffix not_in server.suffix_map {
        fmt.println(suffix)
        panic("Failed to find suffix!")
    }

    return server.suffix_map[suffix]
}

// # Asset_Handle
// A handle to an asset of an unknown type, via a pointer to its context and its filepath.
// When this handle is actually used, the data given is of the correct type at the path.
Asset_Handle :: struct {
    ctx: ^Context,
    path: string,
    id: typeid,
    allocated_path: bool,
}

// Ensures that a desired asset is loaded and returns an Asset_Handle
asset_load :: proc(scene: ^Scene, path: string, allocated_path := false) -> Asset_Handle {
    if path not_in scene.asset_map {
        scene.asset_map[path] = {}
    }

    if !asset_exists(&scene.ctx.asset_server, path) {
        _asset_load(scene, path)
    }

    handle := &scene.ctx.asset_server.asset_map[path]
    handle.allocated_path = allocated_path

    return scene.ctx.asset_server.asset_map[path]
}

// Ensures that a desired asset is loaded.
asset_preload :: proc(scene: ^Scene, path: string, allocated_path := false) {
    if path not_in scene.asset_map {
        scene.asset_map[path] = {}
    }

    if !asset_exists(&scene.ctx.asset_server, path) {
        _asset_load(scene, path)
    }

    handle := &scene.ctx.asset_server.asset_map[path]
    handle.allocated_path = allocated_path
}

// # Asset Type
// A union determining the type of an asset. Used when hot reloading.
Asset_Type :: union {
    Asset_Dependent,
    Asset_File,
    Asset_Standalone,
}

// # Asset Dependent
// An asset that is typically loaded from and dependent on multiple sub-assets.
Asset_Dependent :: struct {
    dependencies: []Asset_Handle,
}

// # Asset File
// An asset that is typically loaded from a file.
Asset_File :: struct {
    last_time: os.File_Time,
    full_path: string,
    id: typeid,
}

// # Asset Standalone
// An asset that is typically loaded at runtime and is not dependent on any pre-existing data.
Asset_Standalone :: struct {}

// Creates an allocated name string using a UUID. Should ideally be only used with Asset_Standalone(s).
asset_generate_name :: proc() -> string {
    id: uuid.Identifier

    {
        context.random_generator = crypto.random_generator()
        id = uuid.generate_v7()
    }

    out: string
    err: mem.Allocator_Error

    {
        context.allocator = context.temp_allocator
        out, err = uuid.to_string_allocated(id, context.temp_allocator)
    }

    if err != .None {
        fmt.println(err)
        panic("Failed to generate unique name!")
    }

    return strings.clone(out)
}

// TODO: Implement hot-reloading
Asset_Tracker :: struct {
    index: int,
    mutex: sync.Mutex,
    type: Asset_Type,
    id: typeid,
}

@(private)
_asset_load :: proc(scene: ^Scene, path: string, loc := #caller_location) {
    suffix := file_get_last_suffix(path)
    id := asset_suffix_type(&scene.ctx.asset_server, suffix)

    if id not_in scene.ctx.asset_server.type_map {
        panic("Error, asset types must be registered before use!", loc = loc)
    }

    storage := asset_server_get_storage(&scene.ctx.asset_server, id)
    outer: if path not_in storage.path_map {
        for !sync.mutex_try_lock(&storage.access_mutex) {
            if path in storage.path_map {
                break outer
            }
        }

        storage.path_map[path] = {}
        tracker := &storage.path_map[path]
        
        sync.mutex_unlock(&storage.access_mutex)
        // Load the asset
        for !sync.mutex_try_lock(&tracker.mutex) {
            if path in storage.path_map {
                break outer
            }
        }

        scene.ctx.asset_server.load_procs[scene.ctx.asset_server.type_map[id]](scene, path)

        sync.mutex_unlock(&tracker.mutex)
    }
}

@(private)
_asset_reload :: proc(scene: ^Scene, tracker: ^Asset_Tracker) {
    sync.mutex_lock(&tracker.mutex)

    switch type in tracker.type {
        case Asset_Dependent: {

        }
        case Asset_File: {
            scene.ctx.asset_server.load_procs[scene.ctx.asset_server.type_map[tracker.id]](scene, scene.ctx.asset_server.storages[scene.ctx.asset_server.type_map[tracker.id]].index_map[tracker.index])
        }
        case Asset_Standalone: {

        }
    }

    sync.mutex_unlock(&tracker.mutex)
}

// # Asset_Storage
// Stores loaded assets of a given type, although this type is not known to the storage until a
// procedure is called. Assets should not be accessed using the storage directly, instead you'll
// want to use `asset_get` which operates on the overarching server.
Asset_Storage :: struct {
    data: rawptr,
    length: int,
    elem_size: int,
    cap: int,
    id: typeid,
    path_map: map[string]Asset_Tracker,
    index_map: [dynamic]string,
    access_mutex: sync.Mutex,
}

asset_storage_new :: proc($T: typeid) -> (out: Asset_Storage) {
    out.data = make_multi_pointer([^]T, 8)
    out.length = 0
    out.elem_size = size_of(T)
    out.cap = 8
    out.id = typeid_of(T)
    out.path_map = {}
    out.index_map = make([dynamic]string)
    return
}

asset_storage_destroy :: proc(storage: ^Asset_Storage) {
    free(storage.data)
    delete(storage.path_map)
    delete(storage.index_map)
}

asset_storage_add :: proc(storage: ^Asset_Storage, path: string, data: $T, type: Asset_Type = Asset_File {}) {
    if path in storage.path_map {
        // Data already exists, just update the data at the path instead.
        asset_storage_update(storage, path, data)
    }

    index := storage.length
    tracker := storage.path_map[path]
    tracker.index = index
    tracker.id = storage.id
    storage.path_map[path] = tracker

    type := type
    switch &t in type {
        case Asset_File: {
            t.id = typeid_of(T)
            err: os.Error
            t.last_time, err = os.last_write_time_by_name(t.full_path)

            if err != nil {
                fmt.println(err)
                panic("Error: failed to get last write time!")
            }

            tracker.type = t
        }
        case Asset_Dependent: {
            tracker.type = type
        }
        case Asset_Standalone: {
            tracker.type = type
        }
    }

    if index == storage.cap {
        // About to expand past the cap, time to resize
        error: mem.Allocator_Error
        storage.data, error = mem.resize(storage.data, storage.elem_size * storage.cap, storage.elem_size * (storage.cap * 2))
        storage.cap *= 2
    }

    storage.length += 1

    d := cast([^]T)storage.data
    d[index] = data
    append(&storage.index_map, path)
}

asset_storage_update :: proc(storage: ^Asset_Storage, path: string, data: $T) {
    if path not_in storage.path_map {
        // Data doesn't exist, we need to add it
        asset_storage_add(storage, path, data)
    }

    d := cast([^]T)storage.data
    d[storage.path_map[path].index] = data
}

asset_storage_get :: proc(storage: ^Asset_Storage, path: string, $T: typeid, loc := #caller_location) -> T {
    if path not_in storage.path_map {
        // We should have already loaded the asset
        panic("Asset is not loaded!", loc = loc)
    }

    d := cast([^]T)storage.data
    return d[storage.path_map[path].index]
}

asset_storage_get_ptr :: proc(storage: ^Asset_Storage, path: string, $T: typeid, loc := #caller_location) -> ^T {
    if path not_in storage.path_map {
        // We should have already loaded the asset
        panic("Asset is not loaded!", loc = loc)
    }

    d := cast([^]T)storage.data
    return &d[storage.path_map[path].index]
}

asset_storage_remove :: proc(storage: ^Asset_Storage, path: string, $T: typeid) {
    if path not_in storage.path_map {
        // Asset doesn't exist, return
        fmt.println("Warning: Tried to remove nonexistent asset:", path)
        return
    }

    old_index := storage.path_map[path].index
    end_index := storage.length - 1
    new_asset := storage.index_map[end_index]
    d := cast([^]T)storage.data

    // Remove old asset from storage and copy asset over
    d[old_index] = d[end_index]
    storage.length -= 1

    unordered_remove(&storage.index_map, old_index)
    new_asset_tracker := storage.path_map[new_asset]
    new_asset_tracker.index = old_index
    storage.path_map[new_asset] = new_asset_tracker

    #partial switch t in storage.path_map[path].type {
        case Asset_Standalone: {
            fmt.println("Deleting path:", path)
            delete(path)
        }
    }

    delete_key(&storage.path_map, path)
}

asset_get :: proc {
    asset_get_from_handle,
    asset_get_from_path,
}

asset_get_from_handle :: proc(handle: ^Asset_Handle, $T: typeid, loc := #caller_location) -> T {
    return asset_get_from_path(handle.ctx.scene, handle.path, T, loc = loc)
}

asset_get_from_path :: proc(scene: ^Scene, path: string, $T: typeid, allocated_path := false, loc := #caller_location) -> T {
    if path not_in scene.asset_map {
        fmt.println("Loaded path:", path)
        scene.asset_map[path] = {}
    }

    if !asset_exists(&scene.ctx.asset_server, path) {
        _asset_load(scene, path)
    }

    handle := &scene.ctx.asset_server.asset_map[path]
    handle.allocated_path = allocated_path

    storage := &scene.ctx.asset_server.storages[scene.ctx.asset_server.type_map[typeid_of(T)]]

    return asset_storage_get(storage, path, T, loc)
}

asset_add :: proc(scene: ^Scene, path: string, data: $T, type: Asset_Type = Asset_File {}, loc := #caller_location) {
    id := typeid_of(T)

    if id not_in scene.ctx.asset_server.type_map {
        panic("Error, asset types must be registered before use!", loc = loc)
    }

    storage := &scene.ctx.asset_server.storages[scene.ctx.asset_server.type_map[id]]
    asset_storage_add(storage, path, data, type)

    scene.ctx.asset_server.asset_map[path] = Asset_Handle {
        ctx = scene.ctx,
        path = path,
        id = id,
        allocated_path = false,
    }
}

asset_update :: proc(server: ^Asset_Server, path: string, data: $T, loc := #caller_location) {
    id := typeid_of(T)

    if id not_in server.type_map {
        panic("Error, asset types must be registered before use!", loc = loc)
    }

    storage := &server.storages[server.type_map[id]]
    asset_storage_update(storage, path, data)
}

asset_get_full_path :: proc(path: string, allocator := context.temp_allocator) -> (full_path: string) {
    // Find the file.
    path_slice := [?]string { ASSET_PREFIX, path }
    return strings.concatenate(path_slice[:], allocator)
}

asset_exists :: proc(server: ^Asset_Server, path: string, loc := #caller_location) -> bool {
    if path not_in server.asset_map {
        return false
    }

    id := server.asset_map[path].id

    if id not_in server.type_map {
        panic("Error, asset types must be registered before use!", loc)
    }

    storage := server.storages[server.type_map[id]]

    if path not_in storage.path_map {
        return false
    }

    return true
}

asset_unload :: proc(scene: ^Scene, path: string) {
    if path not_in scene.ctx.asset_server.asset_map {
        return
    }

    scene.ctx.asset_server.unload_procs[scene.ctx.asset_server.type_map[scene.ctx.asset_server.asset_map[path].id]](scene, path)

    if scene.ctx.asset_server.asset_map[path].allocated_path {
        defer delete(path)
    }

    delete_key(&scene.ctx.asset_server.asset_map, path)
}