package milk

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

Profiler :: struct {
    profiles: map[string]Profile
}

profiler_new :: proc() -> (out: Profiler) {
    out.profiles = make(map[string]Profile)

    return
}

profiler_destroy :: proc(profiler: ^Profiler) {
    for key, &val in profiler.profiles {
        for key, &val in val.steps {
            step_destroy(&val)
        }
        delete(val.steps)
        data_state_delete(&val.data)
    }

    delete(profiler.profiles)
}

Profile :: struct {
    runs: int,
    avg: f64,
    min: f64,
    max: f64,
    data: Data_State,
    steps: map[string]Step,
    time_start: time.Tick,
    last_step_time: time.Tick,
}

profile_new :: proc() -> (out: Profile) {
    out.runs = 0
    out.avg = 0
    out.min = 0
    out.max = 0
    out.steps = {}
    out.data = data_state_new()

    return
}

Data_State :: struct {
    data: Maybe(string),
    min: Maybe(string),
    max: Maybe(string),
}

data_state_new :: proc() -> Data_State {
    return {
        data = nil,
        min = nil,
        max = nil,
    }
}

data_state_copy :: proc(state: Data_State) -> (out: Data_State) {
    if state.data != nil {
        out.data = strings.clone(state.data.(string))
    }
    if state.min != nil {
        out.min = strings.clone(state.min.(string))
    }
    if state.max != nil {
        out.max = strings.clone(state.max.(string))
    }
    return
}

data_state_reset :: proc(state: ^Data_State) {
    if state.data != nil {
        delete(state.data.(string))
        state.data = nil
    }
}

data_state_delete :: proc(state: ^Data_State) {
    if state.data != nil {
        delete(state.data.(string))
        state.data = nil
    }
    if state.min != nil {
        delete(state.min.(string))
        state.min = nil
    }
    if state.max != nil {
        delete(state.max.(string))
        state.max = nil
    }
}

Step :: struct {
    elapsed_time: f64,
    min: f64,
    max: f64,
    end_time: time.Tick,
    data: Data_State,
}

step_copy :: proc(step: Step) -> (out: Step) {
    out.data = data_state_copy(step.data)
    out.elapsed_time = step.elapsed_time
    out.end_time = step.end_time

    return
}

step_destroy :: proc(step: ^Step) {
    data_state_delete(&step.data)
}

profile_get :: proc(profiler: ^Profiler, name: string) -> ^Profile {
    if name not_in profiler.profiles {
        profiler.profiles[name] = profile_new()
    }

    return &profiler.profiles[name]
}

profile_start :: proc(prof: ^Profile) {
    prof.runs += 1
    prof.time_start = time.tick_now()
    prof.last_step_time = prof.time_start
}

// Sets a user-defined data, which is stored and printed for the minimum and maximum runs.
// Useful for profiling the longest and shortest runs and their causes.
profile_set_user_data :: proc(prof: ^Profile, data: ..any) {
    // Delete old data before inputting new data
    data_state_reset(&prof.data)

    prof.data.data = fmt.aprint(..data)
}

take_step :: proc(prof: ^Profile, step_name: string) {
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

take_step_with_data :: proc(prof: ^Profile, step_name: string, data: ..any) {
    start_time := prof.last_step_time
    step: Step

    if step_name in prof.steps {
        step = prof.steps[step_name]
    }

    step.elapsed_time = time.duration_microseconds(time.tick_since(start_time))
    step.end_time = time.tick_now()

    data_state_reset(&step.data)

    step.data.data = fmt.aprint(..data)
    prof.last_step_time = step.end_time

    prof.steps[step_name] = step
}

profile_end :: proc(prof: ^Profile) {
    time_elapsed := time.duration_microseconds(time.tick_since(prof.time_start))

    prof.avg = ((prof.avg * cast(f64)(prof.runs - 1)) + time_elapsed) / cast(f64)prof.runs
    
    if time_elapsed < prof.min || prof.min == 0 {
        prof.min = time_elapsed
        if prof.data.data != nil {
            if prof.data.min != nil {
                delete(prof.data.min.(string))
                prof.data.min = nil
            }
            prof.data.min = strings.clone(prof.data.data.(string))
        }

        for _, &step in prof.steps {
            step.min = step.elapsed_time

            if step.data.data != nil {
                if step.data.min != nil {
                    delete(step.data.min.(string))
                    step.data.min = nil
                }
                step.data.min = strings.clone(step.data.data.(string))
            }
        }
    } else if time_elapsed > prof.max {
        prof.max = time_elapsed
        if prof.data.data != nil {
            if prof.data.max != nil {
                delete(prof.data.max.(string))
                prof.data.max = nil
            }
            prof.data.max = strings.clone(prof.data.data.(string))
        }

        for _, &step in prof.steps {
            step.max = step.elapsed_time

            if step.data.data != nil {
                if step.data.max != nil {
                    delete(step.data.max.(string))
                    step.data.max = nil
                }
                step.data.max = strings.clone(step.data.data.(string))
            }
        }
    }

    data_state_reset(&prof.data)

    for _, &step in prof.steps {
        data_state_reset(&step.data)
    }
}

profile_copy :: proc(profile: Profile) -> (out: Profile) {
    out.runs = profile.runs
    out.min = profile.min
    out.max = profile.max
    out.avg = profile.avg
    out.time_start = profile.time_start
    out.last_step_time = profile.last_step_time
    out.data = data_state_copy(profile.data)
    
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

                for key, val in profile.steps {
                    temp_copy := prof.steps[key]
                    temp_copy.min = val.min

                    if val.data.min != nil {
                        if temp_copy.data.min != nil {
                            delete(temp_copy.data.min.(string))
                            temp_copy.data.min = nil
                        }
                        temp_copy.data.min = strings.clone(val.data.min.(string))
                    }

                    prof.steps[key] = temp_copy
                }

                if prof.data.min != nil {
                    delete(prof.data.min.(string))
                    prof.data.min = nil
                }
                if profile.data.min != nil {
                    prof.data.min = strings.clone(profile.data.min.(string))
                }
            }
            if (prof.max < profile.max) || prof.max == 0 {
                prof.max = profile.max

                for key, val in profile.steps {
                    temp_copy := prof.steps[key]
                    temp_copy.max = val.max

                    if val.data.max != nil {
                        if temp_copy.data.max != nil {
                            delete(temp_copy.data.max.(string))
                            temp_copy.data.max = nil
                        }
                        temp_copy.data.max = strings.clone(val.data.max.(string))
                    }

                    prof.steps[key] = temp_copy
                }

                if prof.data.max != nil {
                    delete(prof.data.max.(string))
                    prof.data.max = nil
                }
                if profile.data.max != nil {
                    prof.data.max = strings.clone(profile.data.max.(string))
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
        if val.data.min != nil {
            fmt.println("   User data:", val.data.min.(string))
        }

        if len(val.steps) != 0 {
            fmt.println("Steps:")
            for step_name, step in val.steps {
                fmt.println("  ", step_name)
                fmt.println("   Elapsed time:", step.min)
                if step.data.min != nil {
                    fmt.println("   Data:", step.data.min.(string))
                }
            }
        }

        fmt.println("Maximum Duration:", val.max, "micros")
        if val.data.max != nil {
            fmt.println("   User data:", val.data.max.(string))
        }

        if len(val.steps) != 0 {
            fmt.println("Steps:")
            for step_name, step in val.steps {
                fmt.println("  ", step_name)
                fmt.println("   Elapsed time:", step.max)
                if step.data.max != nil {
                    fmt.println("   Data:", step.data.max.(string))
                }
            }
        }

        fmt.println("---------------------------")
    }
}

thread_profiler_pool: map[int]Profiler

thread_profiler :: proc() -> ^Profiler {
    if os.current_thread_id() not_in thread_profiler_pool {
        thread_profiler_pool[os.current_thread_id()] = profiler_new()
    }

    return &thread_profiler_pool[os.current_thread_id()]
}