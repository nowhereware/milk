package milk

import "core:fmt"
import "core:strings"
import SDL "vendor:sdl3"

// A key correlating to a physical key location on a keyboard (WASD-format).
// Note that this is based on location, not actual value.
Key_Code :: SDL.Scancode

Button_Code :: SDL.GamepadButton

Mouse_Code :: SDL.MouseButtonFlag

Input_Code :: union {
    Key_Code,
    Button_Code,
    Mouse_Code,
}

Mouse_State :: struct {
    previous: SDL.MouseButtonFlags,
    current: SDL.MouseButtonFlags,
    position: Vector2,
}

mouse_state_new :: proc() -> Mouse_State {
    out: Mouse_State
    out.current = SDL.GetMouseState(&out.position.x, &out.position.y)
    out.previous = {}

    return out
}

mouse_state_update :: proc(state: ^Mouse_State) {
    state.previous = state.current
    state.current = SDL.GetMouseState(&state.position.x, &state.position.y)
}

mouse_state_pressed :: proc(state: ^Mouse_State, button: Mouse_Code) -> bool {
    return button in state.current
}

mouse_state_released :: proc(state: ^Mouse_State, button: Mouse_Code) -> bool {
    return button not_in state.current
}

mouse_state_just_pressed :: proc(state: ^Mouse_State, button: Mouse_Code) -> bool {
    return button not_in state.previous && button in state.current
}

mouse_state_just_released :: proc(state: ^Mouse_State, button: Mouse_Code) -> bool {
    return button in state.previous && button not_in state.current
}

Keyboard_State :: struct {
    previous: [dynamic]bool,
    current: [dynamic]bool,
    raw_array: [^]bool,
    state: ^Input_State,
    mouse_state: Mouse_State,
}

keyboard_state_new :: proc() -> Keyboard_State {
    num_keys: i32
    out: Keyboard_State
    out.raw_array = SDL.GetKeyboardState(&num_keys)

    for i in 0..<num_keys {
        append(&out.current, out.raw_array[i])
    }
    resize(&out.previous, num_keys)

    out.mouse_state = mouse_state_new()

    return out
}

keyboard_state_update :: proc(state: ^Keyboard_State) {
    for i in 0..<len(state.current) {
        state.previous[i] = state.current[i]
        state.current[i] = state.raw_array[i]
    }
    mouse_state_update(&state.mouse_state)
}

keyboard_state_destroy :: proc(state: ^Keyboard_State) {
    delete(state.previous)
    delete(state.current)
}

keyboard_state_pressed :: proc(state: ^Keyboard_State, code: Key_Code) -> bool {
    return state.current[code]
}

keyboard_state_released :: proc(state: ^Keyboard_State, code: Key_Code) -> bool {
    return !state.current[code]
}

keyboard_state_just_pressed :: proc(state: ^Keyboard_State, code: Key_Code) -> bool {
    return !state.previous[code] && state.current[code]
}

keyboard_state_just_released :: proc(state: ^Keyboard_State, code: Key_Code) -> bool {
    return state.previous[code] && !state.current[code]
}

Gamepad_State :: struct {
    // The gamepad state of the previous frame
    previous: [dynamic]bool,
    // The accumulated gamepad state that's updated every real frame
    accumulated: [dynamic]bool,
    // The gamepad state of the current frame
    current: [dynamic]bool,
    id: SDL.JoystickID,
    gamepad: ^SDL.Gamepad,
    name: string,
    state: ^Input_State,
}

gamepad_state_new :: proc(id: SDL.JoystickID) -> Gamepad_State {
    out: Gamepad_State
    out.id = id
    out.gamepad = SDL.OpenGamepad(id)

    resize(&out.previous, len(Button_Code))
    resize(&out.accumulated, len(Button_Code))
    resize(&out.current, len(Button_Code))

    out.name = strings.clone_from_cstring(SDL.GetGamepadName(out.gamepad))

    return out
}

gamepad_state_update :: proc(state: ^Gamepad_State) {
    for i in 0..<len(state.current) {
        state.previous[i] = state.current[i]
        state.current[i] = state.accumulated[i]
    }
}

gamepad_state_destroy :: proc(state: ^Gamepad_State) {
    SDL.CloseGamepad(state.gamepad)

    delete(state.previous)
    delete(state.accumulated)
    delete(state.current)
    delete(state.name)
}

gamepad_state_pressed :: proc(state: ^Gamepad_State, code: Button_Code) -> bool {
    return state.current[code]
}

gamepad_state_released :: proc(state: ^Gamepad_State, code: Button_Code) -> bool {
    return !state.current[code]
}

gamepad_state_just_pressed :: proc(state: ^Gamepad_State, code: Button_Code) -> bool {
    return !state.previous[code] && state.current[code]
}

gamepad_state_just_released :: proc(state: ^Gamepad_State, code: Button_Code) -> bool {
    return state.previous[code] && !state.current[code]
}

Input_Method :: union {
    ^Keyboard_State,
    ^Gamepad_State,
}

Input_Method_Type :: enum {
    Keyboard,
    Gamepad,
}

// # Input Method Entry
// A list of identifiers for an input method stored inside the Input State.
Input_Method_Entry :: struct {
    type: Input_Method_Type,
    name: string,
    index: int,
}

// # Input Action
// A custom named action that responds to one or more inputs
Input_Action :: struct {
    keys: [dynamic]Key_Code,
    buttons: [dynamic]Button_Code,
    mouse_buttons: [dynamic]Mouse_Code,
}

// # Input State
// The state of all inputs to the application. Contains the current keyboard state (we only support one keyboard connection) and all
// gamepad states.
Input_State :: struct {
    keyboard: Keyboard_State,
    gamepads: [dynamic]Gamepad_State,
    gamepad_map: map[SDL.JoystickID]int,
    input_map: map[string]Input_Action,
}

input_state_new :: proc() -> Input_State {
    out: Input_State
    out.keyboard = keyboard_state_new()
    out.keyboard.state = &out

    num_gamepads: i32
    raw_gamepads := SDL.GetGamepads(&num_gamepads)

    for i in 0..<num_gamepads {
        append(&out.gamepads, gamepad_state_new(raw_gamepads[i]))
        out.gamepad_map[raw_gamepads[i]] = len(out.gamepads) - 1
        out.gamepads[len(out.gamepads) - 1].state = &out
    }

    return out
}

input_state_register_input :: proc(state: ^Input_State, name: string, codes: []Input_Code) {
    action: Input_Action 

    for code in codes {
        switch c in code {
            case Key_Code: {
                append(&action.keys, c)
            }
            case Button_Code: {
                append(&action.buttons, c)
            }
            case Mouse_Code: {
                append(&action.mouse_buttons, c)
            }
        }
    }

    state.input_map[name] = action
}

input_state_destroy :: proc(state: ^Input_State) {
    keyboard_state_destroy(&state.keyboard)
    
    for &pad in state.gamepads {
        gamepad_state_destroy(&pad)
    }

    delete_map(state.gamepad_map)
    
    for _, input in state.input_map {
        delete(input.buttons)
        delete(input.keys)
        delete(input.mouse_buttons)
    }
    delete_map(state.input_map)
}

input_state_update :: proc(state: ^Input_State) {
    keyboard_state_update(&state.keyboard)

    for &pad in state.gamepads {
        gamepad_state_update(&pad)
    }
}

input_state_add_gamepad :: proc(state: ^Input_State, id: SDL.JoystickID) {
    if id in state.gamepad_map {
        return
    }

    append(&state.gamepads, gamepad_state_new(id))
    state.gamepad_map[id] = len(state.gamepads) - 1
}

input_state_remove_gamepad :: proc(state: ^Input_State, id: SDL.JoystickID) {
    old_index := state.gamepad_map[id]
    gamepad_state_destroy(&state.gamepads[old_index])
    new_gamepad := state.gamepads[len(state.gamepads) - 1]
    unordered_remove(&state.gamepads, old_index)
    state.gamepad_map[new_gamepad.id] = old_index
    delete_key(&state.gamepad_map, id)
}

input_state_enumerate_methods :: proc(state: ^Input_State) -> (out: [dynamic]Input_Method_Entry) {
    // Start with keyboard
    append(&out, Input_Method_Entry {
        name = "Keyboard",
        type = .Keyboard,
        index = -1
    })

    for pad, index in state.gamepads {
        append(&out, Input_Method_Entry {
            name = pad.name,
            type = .Gamepad,
            index = index
        })
    }

    return
}

input_state_get_keyboard :: proc(state: ^Input_State) -> Input_Method {
    state.keyboard.state = state
    return &state.keyboard
}

input_pressed :: proc(method: Input_Method, name: string) -> bool {
    switch &m in method {
        case ^Keyboard_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for key in action.keys {
                if keyboard_state_pressed(m, key) {
                    return true
                }
            }

            for button in action.mouse_buttons {
                if mouse_state_pressed(&m.mouse_state, button) {
                    return true
                }
            }
        }
        case ^Gamepad_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for button in action.buttons {
                if gamepad_state_pressed(m, button) {
                    return true
                }
            }
        }
    }

    return false
}

input_released :: proc(method: Input_Method, name: string) -> bool {
    switch &m in method {
        case ^Keyboard_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for key in action.keys {
                if keyboard_state_released(m, key) {
                    return true
                }
            }

            for button in action.mouse_buttons {
                if mouse_state_released(&m.mouse_state, button) {
                    return true
                }
            }
        }
        case ^Gamepad_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for button in action.buttons {
                if gamepad_state_released(m, button) {
                    return true
                }
            }
        }
    }

    return false
}

input_just_pressed :: proc(method: Input_Method, name: string) -> bool {
    switch &m in method {
        case ^Keyboard_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for key in action.keys {
                if keyboard_state_just_pressed(m, key) {
                    return true
                }
            }

            for button in action.mouse_buttons {
                if mouse_state_just_pressed(&m.mouse_state, button) {
                    return true
                }
            }
        }
        case ^Gamepad_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for button in action.buttons {
                if gamepad_state_just_pressed(m, button) {
                    return true
                }
            }
        }
    }

    return false
}

input_just_released :: proc(method: Input_Method, name: string) -> bool {
    switch &m in method {
        case ^Keyboard_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for key in action.keys {
                if keyboard_state_just_released(m, key) {
                    return true
                }
            }

            for button in action.mouse_buttons {
                if mouse_state_just_released(&m.mouse_state, button) {
                    return true
                }
            }
        }
        case ^Gamepad_State: {
            if name not_in m.state.input_map {
                return false
            }

            action := m.state.input_map[name]

            for button in action.buttons {
                if gamepad_state_just_released(m, button) {
                    return true
                }
            }
        }
    }

    return false
}

input_get_vector :: proc(method: Input_Method, left, right, up, down: string) -> Vector2 {
    input_left: f32 = input_pressed(method, left) ? 1.0 : 0
    input_right: f32 = input_pressed(method, right) ? 1.0 : 0
    input_up: f32 = input_pressed(method, up) ? 1.0 : 0
    input_down: f32 = input_pressed(method, down) ? 1.0 : 0

    return Vector2 { input_right - input_left, input_up - input_down }
}