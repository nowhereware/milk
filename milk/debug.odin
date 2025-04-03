package milk

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

Profiler :: struct {
    profiles: map[string]Profile
}

// # local_profiler
// A profiler local to each thread. For general usage, this is likely the profiler you'll want to use.
@(thread_local)
local_profiler: Profiler

profiler_new :: proc() -> (out: Profiler) {
    out.profiles = make(map[string]Profile)

    return
}

profiler_destroy :: proc(profiler: ^Profiler) {
    for key, &val in profiler.profiles {
        for name, &step in val.steps {
            step_destroy(&step)
        }
        delete(val.steps)

        if val.min_data != nil {
            delete(val.min_data.(string))
            val.min_data = nil
        }

        if val.max_data != nil {
            delete(val.max_data.(string))
            val.max_data = nil
        }
    }

    delete(profiler.profiles)
}

Profile :: struct {
    runs: int,
    avg: f64,
    min: f64,
    min_data: Maybe(string),
    max: f64,
    max_data: Maybe(string),
    steps: map[string]Step,
    time_start: time.Tick,
    last_step_time: time.Tick,
}

profile_new :: proc() -> (out: Profile) {
    out.runs = 0
    out.avg = 0
    out.min = 0
    out.min_data = nil
    out.max = 0
    out.max_data = nil
    out.steps = {}

    return
}

Step :: struct {
    elapsed_time: f64,
    min: f64,
    min_data: Maybe(string),
    max: f64,
    max_data: Maybe(string),
    current_data: Maybe(string),
    end_time: time.Tick,
}

step_copy :: proc(step: Step) -> (out: Step) {
    if step.min_data != nil {
        out.min_data = strings.clone(step.min_data.(string))
    }
    if step.max_data != nil {
        out.max_data = strings.clone(step.max_data.(string))
    }
    out.elapsed_time = step.elapsed_time
    out.end_time = step.end_time
    out.min = step.min
    out.max = step.max

    return
}

step_destroy :: proc(step: ^Step) {
    if step.min_data != nil {
        delete(step.min_data.(string))
        step.min_data = nil
    }

    if step.max_data != nil {
        delete(step.max_data.(string))
        step.max_data = nil
    }
}

Profile_Handle :: struct {
    name: string,
    profiler: ^Profiler,
    current_data: Maybe(string),
}

profile_handle_new :: proc(profiler: ^Profiler, name: string) -> Profile_Handle {
    return {
        name = name,
        profiler = profiler,
        current_data = nil,
    }
}

profile_handle_get :: proc(handle: ^Profile_Handle) -> ^Profile {
    if handle.name not_in handle.profiler.profiles {
        handle.profiler.profiles[handle.name] = profile_new()
    }

    return &handle.profiler.profiles[handle.name]
}

profile_get :: proc(profiler: ^Profiler, name: string) -> Profile_Handle {
    if name not_in profiler.profiles {
        profiler.profiles[name] = profile_new()
    }

    return profile_handle_new(profiler, name)
}

profile_start :: proc(handle: ^Profile_Handle) {
    prof := profile_handle_get(handle)

    prof.runs += 1
    prof.time_start = time.tick_now()
    prof.last_step_time = prof.time_start
}

// Sets a user-defined data, which is stored and printed for the minimum and maximum runs.
// Useful for profiling the longest and shortest runs and their causes.
profile_set_user_data :: proc(handle: ^Profile_Handle, data: ..any) {
    if handle.current_data != nil {
        delete(handle.current_data.(string))
        handle.current_data = nil
    }

    handle.current_data = fmt.aprint(..data)
}

take_step :: proc(handle: ^Profile_Handle, step_name: string) {
    prof := profile_handle_get(handle)

    start_time := prof.last_step_time
    step: Step

    if step_name in prof.steps {
        step = prof.steps[step_name]
    }

    step.elapsed_time = time.duration_microseconds(time.tick_since(start_time))
    step.end_time = time.tick_now()
    prof.last_step_time = step.end_time

    prof.steps[step_name] = step
}

take_step_with_data :: proc(handle: ^Profile_Handle, step_name: string, data: ..any) {
    prof := profile_handle_get(handle)
    
    start_time := prof.last_step_time
    step: Step

    if step_name in prof.steps {
        step = prof.steps[step_name]
    }

    step.elapsed_time = time.duration_microseconds(time.tick_since(start_time))
    step.end_time = time.tick_now()

    if step.current_data != nil {
        delete(step.current_data.(string))
        step.current_data = nil
    }

    step.current_data = fmt.aprint(..data)
    prof.last_step_time = step.end_time

    prof.steps[step_name] = step
}

profile_end :: proc(handle: ^Profile_Handle) {
    prof := profile_handle_get(handle)

    time_elapsed := time.duration_microseconds(time.tick_since(prof.time_start))

    prof.avg = ((prof.avg * cast(f64)(prof.runs - 1)) + time_elapsed) / cast(f64)prof.runs
    
    if time_elapsed < prof.min || prof.min == 0 {
        prof.min = time_elapsed
        if handle.current_data != nil {
            if prof.min_data != nil {
                delete(prof.min_data.(string))
                prof.min_data = nil
            }
            prof.min_data = strings.clone(handle.current_data.(string))
        }

        for _, &step in prof.steps {
            step.min = step.elapsed_time

            if step.current_data != nil {
                if step.min_data != nil {
                    delete(step.min_data.(string))
                    step.min_data = nil
                }
                step.min_data = strings.clone(step.current_data.(string))
            }
        }
    } else if time_elapsed > prof.max {
        prof.max = time_elapsed
        if handle.current_data != nil {
            if prof.max_data != nil {
                delete(prof.max_data.(string))
                prof.max_data = nil
            }
            prof.max_data = strings.clone(handle.current_data.(string))
        }

        for _, &step in prof.steps {
            step.max = step.elapsed_time

            if step.current_data != nil {
                if step.max_data != nil {
                    delete(step.max_data.(string))
                    step.max_data = nil
                }
                step.max_data = strings.clone(step.current_data.(string))
            }
        }
    }

    if handle.current_data != nil {
        delete(handle.current_data.(string))
        handle.current_data = nil
    }

    for _, &step in prof.steps {
        if step.current_data != nil {
            delete(step.current_data.(string))
            step.current_data = nil
        }
    }
}

profile_copy :: proc(profile: Profile) -> (out: Profile) {
    out.runs = profile.runs
    out.min = profile.min

    if profile.min_data != nil {
        out.min_data = strings.clone(profile.min_data.(string))
    }

    out.max = profile.max

    if profile.max_data != nil {
        out.max_data = strings.clone(profile.max_data.(string))
    }

    out.avg = profile.avg
    out.time_start = profile.time_start
    out.last_step_time = profile.last_step_time
    
    for key, val in profile.steps {
        out.steps[key] = step_copy(val)
    }

    return
}

condense_profilers :: proc(profilers: ..Profiler) -> Profiler {
    condensed := profiler_new()

    outer: for profiler in profilers {
        inner: for name, profile in profiler.profiles {
            if name not_in condensed.profiles {
                condensed.profiles[name] = profile_copy(profile)
                continue inner
            }

            prof := condensed.profiles[name]
            prof.avg = ((prof.avg * cast(f64)prof.runs) + (profile.avg * cast(f64)profile.runs)) / cast(f64)(prof.runs + profile.runs)
            prof.runs += profile.runs
            
            if (prof.min > profile.min || prof.min == 0) && profile.min != 0 {
                prof.min = profile.min

                for name, step in profile.steps {
                    temp_copy := prof.steps[name]
                    temp_copy.min = step.min

                    if step.min_data != nil {
                        if temp_copy.min_data != nil {
                            delete(temp_copy.min_data.(string))
                            temp_copy.min_data = nil
                        }
                        temp_copy.min_data = strings.clone(step.min_data.(string))
                    }

                    prof.steps[name] = temp_copy
                }

                if profile.min_data != nil {
                    if prof.min_data != nil {
                        delete(prof.min_data.(string))
                        prof.min_data = nil
                    }

                    prof.min_data = strings.clone(profile.min_data.(string))
                }
            }
            if (prof.max < profile.max) || prof.max == 0 {
                prof.max = profile.max

                for name, step in profile.steps {
                    temp_copy := prof.steps[name]
                    temp_copy.max = step.max

                    if step.max_data != nil {
                        if temp_copy.max_data != nil {
                            delete(temp_copy.max_data.(string))
                            temp_copy.max_data = nil
                        }
                        temp_copy.max_data = strings.clone(step.max_data.(string))
                    }

                    prof.steps[name] = temp_copy
                }

                if profile.max_data != nil {
                    if prof.max_data != nil {
                        delete(prof.max_data.(string))
                        prof.max_data = nil
                    }

                    prof.max_data = strings.clone(profile.max_data.(string))
                }
            }

            condensed.profiles[name] = prof
        }
    }

    return condensed
}

print_profiles :: proc(profiler: ^Profiler) {
    fmt.println("---------------------------")
    for key, val in profiler.profiles {
        fmt.println(key, ":", sep = "")
        fmt.println("Average Duration:", val.avg, "micros")
        fmt.println("Minimum Duration:", val.min, "micros")
        if val.min_data != nil {
            fmt.println("   User data:", val.min_data.(string))
        }

        if len(val.steps) != 0 {
            fmt.println("Steps:")
            for step_name, step in val.steps {
                fmt.println("  ", step_name)
                fmt.println("   Elapsed time:", step.min)
                if step.min_data != nil {
                    fmt.println("   Data:", step.min_data.(string))
                }
            }
        }

        fmt.println("Maximum Duration:", val.max, "micros")
        if val.max_data != nil {
            fmt.println("   User data:", val.max_data.(string))
        }

        if len(val.steps) != 0 {
            fmt.println("Steps:")
            for step_name, step in val.steps {
                fmt.println("  ", step_name)
                fmt.println("   Elapsed time:", step.max)
                if step.max_data != nil {
                    fmt.println("   Data:", step.max_data.(string))
                }
            }
        }

        fmt.println("---------------------------")
    }
}