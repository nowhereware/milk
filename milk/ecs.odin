package milk

import ba "core:container/bit_array"
import "core:mem"
import "core:container/queue"
import "core:slice"
import "core:sync"

// An identifier for an entity within the ECS.
Entity :: u64

// A Bit_Array that determines the composition of an entity.
Signature :: ba.Bit_Array

// # World
// The core of the ECS. This keeps track of everything including entity creation, component data storage, and signature storage. The ECS implementation used
// in Milk is primarily based on a sparse-set ideology, where the composition of an entity is stored in its own array while the actual data is stored within
// its own Storage array based on the component type. This was done in order to maximize add/remove operation efficiency while also keeping queries pretty
// fast too.
World :: struct {
	// An array of Storage members, which store component data
	storage_array: [dynamic]Storage,
	// A map mapping a given typeid to its index within the storage array
	comp_map: map[typeid]int,
	// An array mapping a given index to its typeid
	index_map: [dynamic]typeid,

	// Entity storage
	// Stores a list of Signatures that entities are using
	signature_array: [dynamic]Signature,
	// Stores a list of entities corresponding to each signature
	signature_storages: [dynamic]Signature_Storage,
	// Gets the index of a signature in the signature_array from an Entity
	entity_map: map[Entity]int,
	// Stores the latest available entity IDs
	available_ids: queue.Queue(Entity),
	// A count of all entities in the world
	entity_count: u64,
}

// Creates a new ECS world.
world_new :: proc() -> (out: World) {
	out.storage_array = make([dynamic]Storage)
	out.comp_map = {}
	out.index_map = make([dynamic]typeid)

	out.signature_array = make([dynamic]Signature)
	out.signature_storages = make([dynamic]Signature_Storage)
	out.entity_map = {}
	queue.init(&out.available_ids)
	queue.push(&out.available_ids, 0)
	out.entity_count = 0
	return
}

// Destroys a given ECS world.
world_destroy :: proc(world: ^World) {
	for &storage in world.storage_array {
		ecs_storage_destroy(&storage)
	}

	delete(world.storage_array)
	delete(world.comp_map)
	delete(world.index_map)

	for &sig, index in world.signature_array {
		ba.destroy(&sig)
	}

	delete(world.signature_array)

	for &sig_storage in world.signature_storages {
		signature_storage_destroy(&sig_storage)
	}

	delete(world.signature_storages)
	delete(world.entity_map)
	queue.destroy(&world.available_ids)
}

// Gets the component storage of a World from a given type T.
world_get_storage :: proc(world: ^World, $T: typeid, loc := #caller_location) -> ^Storage {
	index := check_component(world, T)

	return &world.storage_array[index]
}

// Creates a new Entity ID.
@(private)
get_new_id :: proc(world: ^World) -> Entity {
	id := queue.pop_front(&world.available_ids)

	if id == world.entity_count {
		// We've received a sequential ID, so we may have run out of recycled IDs. Push a new ID to the back
		// Increase the number of the next ID.
		world.entity_count += 1
		queue.push(&world.available_ids, world.entity_count)
	}

	return id
}

// Searches within the signature array to find a desired signature
@(private)
search_for_signature :: proc(world: ^World, sig: Signature) -> (index: int, ok: bool) {
	sig := sig
	for &iter_sig, iter_index in world.signature_array {
		// SHORTCUT: If the lens don't match, they're obviously not the same
		if ba.len(&iter_sig) != ba.len(&sig) {
			continue
		}

		if slice.equal(iter_sig.bits[:], sig.bits[:]) {
			return iter_index, true
		}
	}
	return 0, false
}

// Checks if a given signature exists within the world. If it doesn't, it's created. Returns index of the signature.
check_signature :: proc(world: ^World, sig: Signature) -> int {
	if index, ok := search_for_signature(world, sig); ok {
		delete(sig.bits)
		return index
	}

	// It doesn't exist, so create it
	append(&world.signature_array, sig)
	append(&world.signature_storages, signature_storage_new(sig))
	return len(world.signature_array) - 1
}

// Checks if a given component exists within the `storage_array` array. If it doesn't, it's created. Returns index of the array.
check_component :: proc(world: ^World, $T: typeid) -> int {
	id := typeid_of(T)

	if id in world.comp_map {
		return world.comp_map[id]
	}

	append(&world.index_map, id)
	world.comp_map[id] = len(world.index_map) - 1
	append_elem(&world.storage_array, ecs_storage_new(T))
	return world.comp_map[id]
}

// Spawns a new Entity and returns its ID
ecs_spawn :: proc(world: ^World) -> Entity {
	id := get_new_id(world)

	signature: Signature = {}

	index := check_signature(world, signature)
	append(&world.signature_storages[index].index_map, id)
	world.signature_storages[index].entity_map[id] = len(world.signature_storages[index].index_map) - 1
	world.entity_map[id] = index

	return id
}

// Despawns a given Entity, deleting its data
ecs_despawn :: proc(world: ^World, ent: Entity) {
	cur_sig_index := world.entity_map[ent]

	signature_storage_delete_entity(&world.signature_storages[cur_sig_index], ent)

	// Add a command to each component's queue to delete the entity
	iter := ba.make_iterator(&world.signature_array[cur_sig_index])
	for index, ok := ba.iterate_by_set(&iter); ok; index, ok = ba.iterate_by_set(&iter) {
		ecs_storage_add_command(&world.storage_array[index], Command_Delete { entity = ent })
	}

	// Add the entity's ID to the available ID queue
	queue.push(&world.available_ids, ent)
}

// Adds a component to an Entity
ecs_add :: proc(world: ^World, entity: Entity, data: $T) {
	if ecs_has(world, entity, T) {
		ecs_set(world, entity, data)
		return
	}

	storage := world_get_storage(world, T)
	ecs_storage_add_data(storage, entity, data)

	current_sig := world.signature_array[world.entity_map[entity]]
	current_sig.bits = make([dynamic]u64)
	append_elems(&current_sig.bits, ..world.signature_array[world.entity_map[entity]].bits[:])

	// We need to update the signature to match the new composition
	old_index := world.entity_map[entity]
	ba.set(&current_sig, world.comp_map[typeid_of(T)])
	new_index := check_signature(world, current_sig)

	// Delete the entity from old storage
	signature_storage_delete_entity(&world.signature_storages[old_index], entity)

	// Add to new storage
	signature_storage_add_entity(&world.signature_storages[new_index], entity)

	// Map the entity to its new signature
	world.entity_map[entity] = new_index
}

// Removes a component from an Entity
ecs_remove :: proc(world: ^World, entity: Entity, $T: typeid) {
	storage := world_get_storage(world, T)
	ecs_storage_remove_data(storage, T, entity)

	current_sig := world.signature_array[world.entity_map[entity]]
	current_sig.bits = make([dynamic]u64)
	append_elems(&current_sig.bits, ..world.signature_array[world.entity_map[entity]].bits[:])

	// We need to update the signature to match the new composition
	old_index := check_signature(world, current_sig)
	ba.unset(&current_sig, world.comp_map[typeid_of(T)])
	new_index := check_signature(world, current_sig)

	// Delete the entity from old storage
	signature_storage_delete_entity(&world.signature_storages[old_index], entity)

	// Add to new storage
	signature_storage_add_entity(&world.signature_storages[new_index], entity)

	// Map the entity to its new signature
	world.entity_map[entity] = new_index
}

// Returns if an entity has a component
ecs_has :: proc(world: ^World, entity: Entity, $T: typeid) -> bool {
	check_component(world, T)

	id := typeid_of(T)
	ent_sig := world.signature_array[world.entity_map[entity]]

	res, ok := ba.get(&ent_sig, world.comp_map[id])

	return res
}

// Returns an entity's component data for a given component
ecs_get :: proc(world: ^World, ent: Entity, $T: typeid, loc := #caller_location) -> (data: T) {
	if !ecs_has(world, ent, T) {
		panic("Attempted to get nonexistent data from entity!", loc)
	}

	storage := world_get_storage(world, T)
	data = ecs_storage_get_data(storage, T, ent)
	return
}

// Returns a pointer to an entity's component data for a given component
ecs_get_ptr :: proc(world: ^World, ent: Entity, $T: typeid, loc := #caller_location) -> (data: ^T) {
	if !ecs_has(world, ent, T) {
		panic("Attempted to get nonexistent data from entity!", loc)
	}

	storage := world_get_storage(world, T)
	data = ecs_storage_get_data_ptr(storage, T, ent)
	return
}

// Sets an entity's component data for a given component
ecs_set :: proc(world: ^World, ent: Entity, data: $T, loc := #caller_location) {
	if !ecs_has(world, ent, T) {
		ecs_add(world, ent, data)
		return
	}

	storage := world_get_storage(world, T, loc)
	ecs_storage_set_data(storage, ent, data, loc = loc)
	return
}

// # Storage
// The ECS World's internal way of storing component data. Storage is implemented as a sparse set, where the data itself is stored in a
// tightly-packed array `dense_storage` and is indexed by getting indices from the "sparse array" `entity_map`, which takes the form of
// a map type. Storage also contains an `index_map` (actually an array) that corresponds indices to Entity IDs, and the command queue.
Storage :: struct {
	entity_map: map[Entity]int,
	index_map: [dynamic]Entity,
	dense_storage: rawptr,
	element_size: int,
	length: int,
	cap: int,
	command_queue: queue.Queue(Storage_Command),
	mutex: sync.Mutex,
}

// Creates a new Storage, given a valid type T
ecs_storage_new :: proc($T: typeid) -> (out: Storage) {
    out.entity_map = {}
    out.index_map = make([dynamic]Entity)
    out.dense_storage = make_multi_pointer([^]T, 8)
	out.element_size = size_of(T)
	out.length = 0
	out.cap = 8
	queue.init(&out.command_queue)
    return
}

// Destroys a given Storage.
ecs_storage_destroy :: proc(storage: ^Storage) {
	delete_map(storage.entity_map)
	delete(storage.index_map)
	free(storage.dense_storage)
	queue.destroy(&storage.command_queue)
}

// Copies the data of a given Storage into a new storage.
ecs_storage_copy :: proc(storage: ^Storage) -> (out: Storage) {
	for key, val in storage.entity_map {
		out.entity_map[key] = val
	}

	mem.copy_non_overlapping(raw_data(out.index_map), raw_data(storage.index_map), len(storage.index_map) * size_of(Entity))
	mem.copy_non_overlapping(out.dense_storage, storage.dense_storage, storage.length * storage.element_size)
	out.element_size = storage.element_size
	out.length = storage.length
	out.cap = storage.cap
	out.command_queue = storage.command_queue
	out.mutex = {}

	return
}

// A command passed to a Data_Storage (or Component_Storage($T)) that must be run before the data is modified again
Storage_Command :: union {
	Command_Delete,
}

// A command to delete a given entity from the storage.
Command_Delete :: struct {
	entity: Entity
}

// Adds a command to the storage's list of commands to run
ecs_storage_add_command :: proc(storage: ^Storage, command: Storage_Command) {
	queue.append(&storage.command_queue, command)
}

// Validates that the command queue within the storage is empty. If it isn't, we run through the queue
// and run any actions necessary before accessing the data again, ex. deleting an entity
ecs_storage_validate_commands :: proc(storage: ^Storage, $T: typeid) {
	if queue.len(storage.command_queue) == 0 {
		return
	}

	for i := 0; i < queue.len(storage.command_queue); i += 1 {
		command := queue.pop_back(&storage.command_queue)

		switch com in command {
			case Command_Delete: {
				ecs_storage_remove_data(storage, T, com.entity)
			}
		}
	}
}

// Adds data of type T to a Storage of type T at a specific Entity
ecs_storage_add_data :: proc(storage: ^Storage, entity: Entity, data: $T, loc := #caller_location) {
	if entity in storage.entity_map {
		panic("Error: Attempted to add component to entity more than once", loc = loc)
	}

	ecs_storage_validate_commands(storage, T)

	append(&storage.index_map, entity)
	index := len(storage.index_map) - 1
	storage.entity_map[entity] = index

	if index == storage.cap {
		// We're about to expand past the cap, time to resize
		error: mem.Allocator_Error
		storage.dense_storage, error = mem.resize(storage.dense_storage, storage.element_size * storage.cap, storage.element_size * (storage.cap * 2))
		storage.cap *= 2
	}

	storage.length += 1

	d := cast([^]T)storage.dense_storage
	d[index] = data
}

// Removes data associated with an entity within a Storage of type T
ecs_storage_remove_data :: proc(storage: ^Storage, $T: typeid, entity: Entity, loc := #caller_location) {
	if entity not_in storage.entity_map {
		panic("Error: Attempted to remove nonexistent entity", loc = loc)
	}

	old_index := storage.entity_map[entity]
	new_entity := storage.index_map[storage.length - 1]
	end_index := storage.length - 1
	data := cast([^]T)storage.dense_storage

	// Remove the old entity from the storage and copy the entity over
	data[old_index] = data[end_index]
	storage.length -= 1

	unordered_remove(&storage.index_map, old_index)
	storage.entity_map[new_entity] = old_index
	delete_key(&storage.entity_map, entity)
}

// Gets a copy/const ref to the data associated with an entity within a Storage
ecs_storage_get_data :: proc(storage: ^Storage, $T: typeid, entity: Entity, loc := #caller_location) -> T {
	if entity not_in storage.entity_map {
		panic("Error: Attempted to get nonexistent entity", loc = loc)
	}

	ecs_storage_validate_commands(storage, T)

	data := cast([^]T)storage.dense_storage

	return data[storage.entity_map[entity]]
}

// Gets a mutable (editable) reference to the data associated with an entity within a Storage
ecs_storage_get_data_ptr :: proc(storage: ^Storage, $T: typeid, entity: Entity) -> ^T {
	if entity not_in storage.entity_map {
		panic("Error: Attempted to get nonexistent entity")
	}

	ecs_storage_validate_commands(storage, T)

	data := cast([^]T)storage.dense_storage

	return &data[storage.entity_map[entity]]
}

// Sets the data associated with an entity within a Component Storage
ecs_storage_set_data :: proc(storage: ^Storage, entity: Entity, data: $T, loc := #caller_location) {
	if entity not_in storage.entity_map {
		panic("Error: Attempted to set data of nonexistent entity", loc = loc)
	}

	ecs_storage_validate_commands(storage, T)

	d := cast([^]T)storage.dense_storage

	d[storage.entity_map[entity]] = data
}

// # Signature Storage
// The ECS World's way of managing Entity compositions. A "signature" is a bit array where each bit corresponds to a typeid (see `type_map` in the World), and the
// corresponding Signature_Storage contains each entity ID that has a composition matching this signature. This is stored in a sparse set format similar to Storage,
// where entities are stored in a dense array `index_map` and can be looked up using the sparse array `entity_map`.
Signature_Storage :: struct {
	entity_map: map[Entity]int,
	index_map: [dynamic]Entity,
}

// Creates a new Signature Storage, given a signature
signature_storage_new :: proc(sig: Signature) -> (out: Signature_Storage) {
	out.entity_map = {}
	out.index_map = make([dynamic]Entity)
	return
}

// Adds an entity to the storage, given an Entity
signature_storage_add_entity :: proc(storage: ^Signature_Storage, ent: Entity) {
    append(&storage.index_map, ent)
    storage.entity_map[ent] = len(storage.index_map) - 1
}

// Deletes an entity from the storage, given an Entity
signature_storage_delete_entity :: proc(storage: ^Signature_Storage, ent: Entity) {
    new_ent_index := len(storage.index_map) - 1
    new_ent := storage.index_map[new_ent_index]
    old_ent_index := storage.entity_map[ent]
    unordered_remove(&storage.index_map, old_ent_index)
    storage.entity_map[new_ent] = old_ent_index
    delete_key(&storage.entity_map, ent)
}

// Destroys the signature storage
signature_storage_destroy :: proc(storage: ^Signature_Storage) {
	delete(storage.entity_map)
	delete(storage.index_map)
}

// # Query Term Filter
// A filter given to a specific query. This simply determines what kind of operation we want to perform on a component we're searching for,
// which is stored inside the overarching struct `Query_Term`.
Query_Term_Filter :: enum {
    With,
    With_Ptr,
    Without,
}

// # Query Term
// A "term" for a query run on the ECS world. Contains a Query_Term_Filter `filter`, which determines how we want to filter the type contained,
// and a type of a component in the term `id`. When a query is run, it uses the terms provided to determine what components are desired, how
// they're going to be used, and what components are explicitly *not* wanted.
Query_Term :: struct {
    filter: Query_Term_Filter,
    id: typeid
}

// # Query Result
// Contains the output of a query, which is a list of entities matching the query.
Query_Result :: struct {
    entities: [dynamic]Entity,
}

// A query term to find entities that have a component T
ecs_with :: proc($T: typeid) -> Query_Term {
    return {
        filter = .With,
        id = typeid_of(T)
    }
}

// A query term to gain mutable access to pointers with a component T
ecs_with_ptr :: proc($T: typeid) -> Query_Term {
    return {
        filter = .With_Ptr,
        id = typeid_of(T)
    }
}

// A query term to find entities that do not have a component T
ecs_without :: proc($T: typeid) -> Query_Term {
    return {
        filter = .Without,
        id = typeid_of(T)
    }
}

// Queries through the World for entities matching a set of Query_Terms, and returns the result (A list of entities)
ecs_query :: proc(world: ^World, terms: ..Query_Term) -> (out: Query_Result) {
    out.entities = make([dynamic]Entity, context.temp_allocator)

    // Turn our terms into a signature
    query_sig: Signature = {}
    mutable_accessors := make([dynamic]^sync.Mutex, context.temp_allocator)
    for term in terms {
        switch term.filter {
            case .With: {
                ba.set(&query_sig, world.comp_map[term.id], true, context.temp_allocator)
            }
            case .With_Ptr: {
                ba.set(&query_sig, world.comp_map[term.id], true, context.temp_allocator)
                append(&mutable_accessors, &world.storage_array[world.comp_map[term.id]].mutex)
            }
            case .Without: {
                ba.set(&query_sig, world.comp_map[term.id], false, context.temp_allocator)
            }
        }
    }

    // Get the signatures matching our query
    sig_search_prof := profile_get(thread_profiler(), "ECS_SIG_SEARCH")

    profile_set_user_data(sig_search_prof, "Signature Search Size:", ba.len(&query_sig))
    profile_start(sig_search_prof)

    indices_arr := make([dynamic]int, context.temp_allocator)

    take_step(sig_search_prof, "ARR_MADE")

    query_iter := ba.make_iterator(&query_sig)
    next_bit, ok := ba.iterate_by_set(&query_iter)

    if ok {
        for &sig, index in world.signature_array {
            res, ok := ba.get(&sig, next_bit)
            if res && ok {
                append(&indices_arr, index)
            }
        }
    }

    take_step_with_data(sig_search_prof, "INDICES_CREATE_NUMS", "Sig Size:", len(world.signature_array))
    
    for next_bit, ok = ba.iterate_by_set(&query_iter); ok; next_bit, ok = ba.iterate_by_set(&query_iter) {
        remove_indices := make([dynamic]int, context.temp_allocator)

        for &sig_index, index in indices_arr {
            res, ok := ba.get(&world.signature_array[sig_index], next_bit)
            if !res || !ok {
                // Don't use this signature
                append(&remove_indices, index)
            }
        }

        for i := len(remove_indices) - 1; i >= 0; i -= 1 {
            unordered_remove(&indices_arr, remove_indices[i])
        }
    }

    take_step(sig_search_prof, "SIGNATURE_ITER")

    // Add the entities in said signature indices to our result
    for index in indices_arr {
        append_elems(&out.entities, ..world.signature_storages[index].index_map[:])
    }

    take_step_with_data(sig_search_prof, "APPENDED_ELEMS", "Indices Arr Size:", len(indices_arr))

    profile_end(sig_search_prof)

    // Done.
    return
}

// Returns a list of constant data of type T given a World, Query_Result, and the type desired
ecs_query_get :: proc(world: ^World, query: ^Query_Result, $T: typeid) -> (out: [dynamic]T) {
    out = make([dynamic]T, context.temp_allocator)

    storage := world_get_storage(world, T)

    for ent in query.entities {
        append(&out, ecs_storage_get_data(storage, T, ent))
    }

    return
}

// Returns a list of mutable data of type T given a World, Query_Result, and the type desired
ecs_query_get_ptr :: proc(world: ^World, query: ^Query_Result, $T: typeid) -> (out: [dynamic]^T) {
    out = make([dynamic]^T, context.temp_allocator)

    storage := world_get_storage(world, T)

    for ent in query.entities {
        append(&out, ecs_storage_get_data_ptr(storage, T, ent))
    }

    return
}

// # Parent
// A component signifying that a given entity is a child of the entity stored in `id`.
Parent :: struct {
    id: Entity
}

// # Children
// A component signifying that a given entity has a list of children stored in the `ids` array.
Children :: struct {
    ids: [dynamic]Entity
}

ecs_add_child :: proc(world: ^World, parent: Entity, child: Entity) {
    if ecs_has(world, parent, Children) {
        // Parent already has a children struct
        children := ecs_get_ptr(world, parent, Children)
        append(&children.ids, child)
    }
}

// Moves an entity `ent` to be a child of another entity `parent`, either from a prior parent or uninherited.
ecs_reparent :: proc(world: ^World, ent: Entity, parent: Entity) {
    if ecs_has(world, ent, Parent) {
        // We need to get the global transforms from the entity's relative transforms
        prev_par := ecs_get(world, ent, Parent).id

        // For each transform type, update it to be a global transform
        if ecs_has(world, prev_par, Transform_2D) && ecs_has(world, ent, Transform_2D) {
            prev_par_trans_2d := ecs_get(world, prev_par, Transform_2D)
            ent_trans_2d := ecs_get_ptr(world, ent, Transform_2D)
            ent_trans_2d.position += prev_par_trans_2d.position
        }

        if ecs_has(world, prev_par, Transform_3D) && ecs_has(world, ent, Transform_3D) {
            prev_par_trans_3d := ecs_get(world, prev_par, Transform_3D)
            ent_trans_3d := ecs_get_ptr(world, ent, Transform_3D)
            // TODO: Need to add rotations as well
            transform_translate(ent_trans_3d, prev_par_trans_3d.mat[3].xyz)
        }

        // Delete the child from the parent
        parent_children := ecs_get_ptr(world, prev_par, Children)
        for child, index in parent_children.ids {
            if child == ent {
                unordered_remove(&parent_children.ids, index)
                break
            }
        }

		ecs_remove(world, ent, Parent)
		// ent is now freshly unparented
    }

	// Parent ent to its new parent
	ecs_add(world, ent, Parent { id = parent })

	// Add ent to parent's children
	if ecs_has(world, parent, Children) {
		children := ecs_get_ptr(world, parent, Children)
		append(&children.ids, ent)
	} else {
		children := make([dynamic]Entity)
		append(&children, ent)
		ecs_add(world, parent, Children { ids = children })
	}

	if ecs_has(world, ent, Transform_2D) && ecs_has(world, parent, Transform_2D) {
		parent_trans := ecs_get(world, parent, Transform_2D)
		ent_trans := ecs_get_ptr(world, ent, Transform_2D)
		ent_trans.position -= parent_trans.position
	}

	if ecs_has(world, ent, Transform_3D) && ecs_has(world, parent, Transform_3D) {
		parent_trans := ecs_get(world, parent, Transform_3D)
		ent_trans := ecs_get_ptr(world, ent, Transform_3D)
		// TODO: Incorrect rotation logic
		transform_translate(ent_trans, -parent_trans.mat[3].xyz)
	}
}