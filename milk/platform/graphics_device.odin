package milk_platform

graphics_device_destroy_proc :: #type proc(device: ^Graphics_Device_Internal)

Graphics_Device_Internal :: union {
    Vk_Graphics_Device
}

Graphics_Device_Commands :: struct {
    destroy: graphics_device_destroy_proc
}

Graphics_Device_Features :: struct {
    acceleration_structure: bool,
    ray_tracing: bool,
}

Graphics_Device_Type :: enum {
    Dedicated,
    Integrated,
    External,
    Software,
}