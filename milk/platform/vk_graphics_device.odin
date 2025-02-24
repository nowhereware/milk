package milk_platform

import "core:fmt"
import "core:strings"
import vk "vendor:vulkan"

Vk_Graphics_Device :: struct {
    name: string,
    type: Graphics_Device_Type,
    gpu_features: Graphics_Device_Features,
    device: vk.PhysicalDevice,
    extensions: [dynamic]vk.ExtensionProperties,
    features: Vk_Features,
    properties: vk.PhysicalDeviceProperties2,
    depth_formats: [dynamic]vk.Format,
    surface_caps: vk.SurfaceCapabilitiesKHR,
    surface_formats: [dynamic]vk.SurfaceFormatKHR,
    present_modes: [dynamic]vk.PresentModeKHR,
}

vk_interpret_device_type :: proc(type: vk.PhysicalDeviceType) -> Graphics_Device_Type {
    switch type {
        case .DISCRETE_GPU: {
            return .Dedicated
        }
        case .INTEGRATED_GPU: {
            return .Integrated
        }
        case .CPU: {
            fallthrough
        }
        case .VIRTUAL_GPU: {
            return .Software
        }
        case .OTHER: {
            return .External
        }
    }

    return .Dedicated
}

vk_graphics_device_enumerate :: proc(rend: ^Vk_Renderer) -> [dynamic]Graphics_Device_Internal {
    count: u32 = 0
    vk.EnumeratePhysicalDevices(rend.instance, &count, nil)
    phys_device_list := make([dynamic]vk.PhysicalDevice, count)
    vk.EnumeratePhysicalDevices(rend.instance, &count, raw_data(phys_device_list))

    desired_type := Graphics_Device_Type.Dedicated

    out := make([dynamic]Vk_Graphics_Device)

    resize(&out, count)
    for i in 0..<count {
        device := phys_device_list[i]
        props: vk.PhysicalDeviceProperties
        vk.GetPhysicalDeviceProperties(device, &props)
        device_type := vk_interpret_device_type(props.deviceType)

        dev_vulkan := Vk_Graphics_Device {
            device = device
        }
        dev_vulkan.name = strings.clone_from_bytes(props.deviceName[:])
        dev_vulkan.type = device_type

        ext_count: u32 = 0
        vk.EnumerateDeviceExtensionProperties(dev_vulkan.device, nil, &ext_count, nil)
        resize(&dev_vulkan.extensions, ext_count)
        vk.EnumerateDeviceExtensionProperties(dev_vulkan.device, nil, &ext_count, raw_data(dev_vulkan.extensions))

        features_14 := vk.PhysicalDeviceVulkan14Features {
            sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
            pNext = nil,
        }
        features_13 := vk.PhysicalDeviceVulkan13Features {
            sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
            pNext = &features_14,
        }
        features_12 := vk.PhysicalDeviceVulkan12Features {
            sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
            pNext = &features_13
        }
        features_11 := vk.PhysicalDeviceVulkan11Features {
            sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
            pNext = &features_12
        }
        features_10 := vk.PhysicalDeviceFeatures2 {
            sType = .PHYSICAL_DEVICE_FEATURES_2,
            pNext = &features_11
        }

        vk.GetPhysicalDeviceFeatures2(dev_vulkan.device, &features_10)
        dev_vulkan.features = Vk_Features {
            features_10 = features_10,
            features_11 = features_11,
            features_12 = features_12,
            features_13 = features_13,
            features_14 = features_14,
        }
        dev_vulkan.properties.sType = .PHYSICAL_DEVICE_PROPERTIES_2
        vk.GetPhysicalDeviceProperties2(dev_vulkan.device, &dev_vulkan.properties)

        dev_vulkan.gpu_features.acceleration_structure = vk_has_extension(dev_vulkan.extensions, vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME)
        dev_vulkan.gpu_features.ray_tracing = vk_has_extension(dev_vulkan.extensions, vk.KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME)

        vk_query_surface_capabilities(rend, &dev_vulkan)

        out[i] = dev_vulkan
    }

    retlist := make([dynamic]Graphics_Device_Internal)
    for dev in out {
        append(&retlist, cast(Graphics_Device_Internal)dev)
    }

    delete(phys_device_list)

    return retlist
}

// Chooses a preferred graphics device from the list. This is the default runner, so we typically prefer a dedicated GPU.
vk_graphics_device_select :: proc(devices: [dynamic]Graphics_Device_Internal) -> ^Vk_Graphics_Device {
    preferred_index := 0
    max_score := 0

    for device, index in devices {
        device := device.(Vk_Graphics_Device)

        if !vk_has_extension(device.extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME) {
            continue
        }

        score := 0
        if device.type == .Dedicated {
            score += 50
        }

        for _ in device.extensions {
            score += 5
        }

        for _ in device.present_modes {
            score += 5
        }

        for _ in device.depth_formats {
            score += 5
        }

        if score > max_score {
            preferred_index = index
        }
    }

    return &devices[preferred_index].(Vk_Graphics_Device)
}

vk_graphics_device_destroy :: proc(device: ^Graphics_Device_Internal) {
    device := &device.(Vk_Graphics_Device)
    delete(device.extensions)
    delete(device.depth_formats)
    delete(device.present_modes)
    delete(device.surface_formats)
}