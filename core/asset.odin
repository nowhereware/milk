package milk_core

import "core:mem"
import "core:os"
import "core:sync"

ASSET_PREFIX :: "assets/"

asset_load_proc :: #type proc(server: ^Asset_Server, path: string)

// # Asset_Handle
// A handle to an asset of an unknown type, via a pointer to its server and its filepath.
// When this handle is actually used, the data given is of the correct type at the path.
Asset_Handle :: struct {
    server: ^Asset_Server,
    path: string,
}

// # Asset_Server
// A server used to access assets of variable but preregistered types. Stored within the server
// is a dynamic array of Asset_Storage(s), which internally keep track of the assets loaded. To
// access an asset, use `asset_get` and pass either an Asset_Handle (which is usually found within
// component types), or the direct server and a filepath, along with the type of the desired asset.
Asset_Server :: struct {
    type_map: map[typeid]int,
    storages: [dynamic]Asset_Storage,
    load_procs: [dynamic]asset_load_proc,
}

asset_server_new :: proc() -> (out: Asset_Server) {
    out.type_map = {}
    out.storages = make([dynamic]Asset_Storage)
    out.load_procs = make([dynamic]asset_load_proc)

    return
}

asset_server_destroy :: proc(server: ^Asset_Server) {
    delete_map(server.type_map)

    for &storage in server.storages {
        asset_storage_destroy(&storage)
    }

    delete(server.storages)
    delete(server.load_procs)
}

asset_server_register_type :: proc(server: ^Asset_Server, $T: typeid, load_proc: asset_load_proc) {
    id := typeid_of(T)
    if id in server.type_map {
        // Type already is registered, return
        return
    }

    append(&server.storages, asset_storage_new(T))
    server.type_map[id] = len(server.storages) - 1
    append(&server.load_procs, load_proc)
}

// TODO: Implement hot-reloading
Asset_Tracker :: struct {
    index: int,
    mutex: sync.Mutex,
    // The last time this asset was edited. If the time returned by the OS function is different, then we reload the asset.
    last_time: os.File_Time,
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
    path_map: map[string]Asset_Tracker,
    index_map: [dynamic]string,
}

asset_storage_new :: proc($T: typeid) -> (out: Asset_Storage) {
    out.data = make_multi_pointer([^]T, 8)
    out.length = 0
    out.elem_size = size_of(T)
    out.cap = 8
    out.path_map = {}
    out.index_map = make([dynamic]string)
}

asset_storage_destroy :: proc(storage: ^Asset_Storage) {
    free(storage.data)
    delete(storage.path_map)
    delete(storage.index_map)
}

asset_storage_add :: proc(storage: ^Asset_Storage, path: string, data: $T) {
    if path in storage.path_map {
        // Data already exists, just update the data at the path instead.
        asset_storage_update(storage, path, data)
    }

    index := storage.length
    storage.path_map[path] = index

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
    storage.path_map[new_asset] = old_index
    delete_key(&storage.path_map, path)
}

asset_get :: proc {
    asset_get_from_handle,
    asset_get_from_path,
}

asset_get_from_handle :: proc(handle: ^Asset_Handle, $T: typeid, loc := #caller_location) -> T {
    return asset_get_from_path(handle.server, handle.path, T, loc)
}

asset_get_from_path :: proc(server: ^Asset_Server, path: string, $T: typeid, loc := #caller_location) -> T {
    id := typeid_of(T)

    if id not_in server.type_map {
        panic("Error, asset types must be registered before use!", loc = loc)
    }

    storage := server.storages[server.type_map[id]]
    outer: if path not_in storage.path_map {
        // Load the asset
        for !sync.try_lock(&storage.path_map[path].mutex) {
            if path in storage.path_map {
                break outer
            }
        }

        server.load_procs[id](server, path)

        sync.unlock(&storage.path_map[path].mutex)
    }

    return asset_storage_get(&storage, path, T, loc)
}

asset_add :: proc(server: ^Asset_Server, path: string, data: $T, loc := #caller_location) {
    id := typeid_of(T)

    if id not_in server.type_map {
        panic("Error, asset types must be registered before use!", loc = loc)
    }

    storage := &server.storages[server.type_map[id]]
    asset_storage_add(storage, path, data)
}

asset_update :: proc(server: ^Asset_Server, path: string, data: $T, loc := #caller_location) {
    id := typeid_of(T)

    if id not_in server.type_map {
        panic("Error, asset types must be registered before use!", loc = loc)
    }

    storage := &server.storages[server.type_map[id]]
    asset_storage_update(storage, path, data)
}