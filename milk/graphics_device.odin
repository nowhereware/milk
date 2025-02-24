package milk

import pt "platform"

Graphics_Device :: struct {
    internal: pt.Graphics_Device_Internal,
    commands: pt.Graphics_Device_Commands,
    type: pt.Graphics_Device_Type,
    features: pt.Graphics_Device_Features,
    name: string,
}

graphics_device_destroy :: proc(device: ^Graphics_Device) {
    device.commands.destroy(&device.internal)
    delete(device.name)
}