package milk

import "core:fmt"
import "core:os"
import "core:strings"

@(private="file")
_handle_error :: proc(error: os.Error, loc := #caller_location) {
    if error != nil {
        panic(fmt.aprint(error), loc)
    }
}

// Loads a file and returns its bytes, given a *complete* relative path.
file_get :: proc(path: string, allocator := context.allocator) -> []u8 {
    slice, err := os.read_entire_file_from_filename(path, allocator)

    if !err {
        fmt.println("Failed to get file:", path)
    }

    return slice
}

// Deletes a slice of file data grabbed from `file_get`
file_close :: proc(data: []u8) {
    delete(data)
}

// Searches a given directory for files of the given name, and returns a list of matching file paths
file_search :: proc(dir, name: string, allocator := context.allocator) -> (matches: []string) {
    // Open the dir
    dir_handle, dir_err := os.open(dir)
    _handle_error(dir_err)

    // TODO: Calc dir file count
    file_infos, file_errs := os.read_dir(dir_handle, -1, allocator)
    _handle_error(file_errs)

    matches_arr := make([dynamic]string)

    for info in file_infos {
        if strings.contains(info.name, name) {
            append_elem(&matches_arr, info.name)
        }

        os.file_info_delete(info)
    }

    os.close(dir_handle)

    matches = matches_arr[:]

    delete(file_infos)
    return
}

// Returns the suffix of the file
file_get_suffix :: proc(file: string) -> string {
    dot_index := strings.index_rune(file, '.')
    suffix, ok := strings.substring_from(file, dot_index)

    if !ok {
        panic("Failed to find the suffix!")
    }

    return suffix
}

// Returns the last suffix of the file
file_get_last_suffix :: proc(file: string) -> string {
    dot_index := strings.last_index(file, ".")
    suffix, ok := strings.substring_from(file, dot_index)

    if !ok {
        panic("Failed to find the last suffix!")
    }

    return suffix
}

// Returns lowest parent folder of a given path
file_get_parent_folder :: proc(path: string) -> string {
    slash_index := strings.last_index(path, "/")
    parent, ok := strings.substring(path, 0, slash_index + 1)

    if !ok {
        panic("Failed to get parent folder!")
    }

    return parent
}

// Returns a file's name given a full path
file_get_name :: proc(path: string) -> string {
    slash_index := strings.last_index(path, "/")
    file, ok := strings.substring_from(path, slash_index + 1)

    if !ok {
        panic("Failed to get file name!")
    }

    return file
}