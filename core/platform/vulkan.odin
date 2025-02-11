package milk_gfx_platform

import "core:fmt"
import "core:strings"
import vk "vendor:vulkan"
import SDL "vendor:sdl3"
import "shared:vma"

when ODIN_DEBUG {
    ENABLE_LAYERS :: true
} else {
    ENABLE_LAYERS :: false
}

FRAME_COUNT :: 2
MAX_DESCRIPTOR_SETS :: 10
MAX_DESCRIPTOR_COUNT :: 65536

Vulkan_Graphics_Device :: struct {
    device: vk.PhysicalDevice,
    queue_family_properties: [dynamic]vk.QueueFamilyProperties,
    extension_properties: [dynamic]vk.ExtensionProperties,
    surface_capabilities: vk.SurfaceCapabilitiesKHR,
    surface_formats: [dynamic]vk.SurfaceFormatKHR,
    present_modes: [dynamic]vk.PresentModeKHR,
    mem_properties: vk.PhysicalDeviceMemoryProperties,
    device_properties: vk.PhysicalDeviceProperties,
}

Vulkan_Frame_Data :: struct {
    acquire_semaphore: vk.Semaphore,
    render_complete_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,
}

Vulkan_Image_Type :: enum {
    Swap,
    Depth,
}

Vulkan_Filter_Type :: enum {
    Linear,
    Nearest,
}

Vulkan_Repeat_Type :: enum {
    Repeat,
    Clamp_To_Edge,
    Clamp_To_Border_Clear,
    Clamp_To_Border_Black,
}

Vulkan_Image :: struct {
    image: vk.Image,
    view: vk.ImageView,
    format: vk.Format,
    extent: vk.Extent2D,
    allocation: vma.Allocation,
    sampler: vk.Sampler,
    texture_format: vk.Format,
    levels: u32,
    type: Vulkan_Image_Type,
    filter: Vulkan_Filter_Type,
    repeat: Vulkan_Repeat_Type,
    layout: vk.ImageLayout,
}

graphics_device_destroy :: proc(device: ^Vulkan_Graphics_Device) {
    delete(device.queue_family_properties)
    delete(device.extension_properties)
    delete(device.surface_formats)
    delete(device.present_modes)
}

vulkan_create_instance :: proc(app_info: ^vk.ApplicationInfo, window: ^SDL.Window) -> (layers: [dynamic]cstring, instance: vk.Instance) {
    inst_create_info := vk.InstanceCreateInfo {
        sType = .INSTANCE_CREATE_INFO,
        pApplicationInfo = app_info,
        flags = nil,
    }

    vk.load_proc_addresses_global(cast(rawptr)SDL.Vulkan_GetVkGetInstanceProcAddr())
    assert(vk.CreateInstance != nil)

    // Get desired SDL instance extensions
    inst_ext_count: u32 = 0
    sdl_exts := SDL.Vulkan_GetInstanceExtensions(&inst_ext_count)

    inst_ext_names := make([dynamic]cstring)

    for i in 0..<inst_ext_count {
        append(&inst_ext_names, sdl_exts[i])
    }

    fmt.println("Ran?")

    layers = make([dynamic]cstring)

    if ENABLE_LAYERS {
        append(&inst_ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
        append(&layers, strings.clone_to_cstring("VK_LAYER_KHRONOS_validation", context.temp_allocator))

        layer_count: u32 = 0
        vk.EnumerateInstanceLayerProperties(&layer_count, nil)
        layer_props := make([dynamic]vk.LayerProperties, layer_count)
        vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layer_props))

        outer: for layer in layers {
            for &prop in layer_props {
                layer_name := strings.clone_from_bytes(prop.layerName[:], context.temp_allocator)
                desired_layer := strings.clone_from_cstring(layer, context.temp_allocator)
                if strings.contains(layer_name, desired_layer) {
                    continue outer
                }
            }

            // Layer not found
            panic(fmt.aprintln("Couldn't find validation layer:", layer))
        }

        delete(layer_props)
    }

    inst_create_info.enabledExtensionCount = cast(u32)len(inst_ext_names)
    inst_create_info.ppEnabledExtensionNames = raw_data(inst_ext_names)
    inst_create_info.enabledLayerCount = cast(u32)len(layers)
    inst_create_info.ppEnabledLayerNames = raw_data(layers)

    vkcheck(vk.CreateInstance(&inst_create_info, nil, &instance))

    vk.load_proc_addresses_instance(instance)

    delete(inst_ext_names)

    return
}

vulkan_create_surface :: proc(instance: vk.Instance, surface: ^vk.SurfaceKHR, window: ^SDL.Window) {
    SDL.Vulkan_CreateSurface(window, instance, nil, surface)
}

vulkan_enumerate_physical_devices :: proc(instance: vk.Instance, surface: vk.SurfaceKHR) -> (devices: [dynamic]Vulkan_Graphics_Device) {
    num_devices: u32 = 0
    vkcheck(vk.EnumeratePhysicalDevices(instance, &num_devices, nil))
    device_list: [dynamic]vk.PhysicalDevice = make([dynamic]vk.PhysicalDevice, num_devices)
    vkcheck(vk.EnumeratePhysicalDevices(instance, &num_devices, raw_data(device_list)))

    devices = make([dynamic]Vulkan_Graphics_Device, num_devices)

    // Select the desired device
    for i := 0; i < len(device_list); i += 1 {
        gpu := devices[i]
        gpu.device = device_list[i]

        {
            // Get queues from device
            num_queues: u32 = 0
            vk.GetPhysicalDeviceQueueFamilyProperties(gpu.device, &num_queues, nil)
            gpu.queue_family_properties = make([dynamic]vk.QueueFamilyProperties, num_queues)
            vk.GetPhysicalDeviceQueueFamilyProperties(gpu.device, &num_queues, raw_data(gpu.queue_family_properties))
        }

        {
            // Get extensions supported by device
            num_extensions: u32 = 0
            vk.EnumerateDeviceExtensionProperties(gpu.device, nil, &num_extensions, nil)
            gpu.extension_properties = make([dynamic]vk.ExtensionProperties, num_extensions)
            vk.EnumerateDeviceExtensionProperties(gpu.device, nil, &num_extensions, raw_data(gpu.extension_properties))
        }

        // Get surface capabilities
        vkcheck(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(gpu.device, surface, &gpu.surface_capabilities))

        {
            // Get supported surface formats
            num_formats: u32 = 0
            vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu.device, surface, &num_formats, nil)
            gpu.surface_formats = make([dynamic]vk.SurfaceFormatKHR, num_formats)
            vk.GetPhysicalDeviceSurfaceFormatsKHR(gpu.device, surface, &num_formats, raw_data(gpu.surface_formats))
        }

        {
            // Get supported present modes
            num_present_modes: u32 = 0
            vk.GetPhysicalDeviceSurfacePresentModesKHR(gpu.device, surface, &num_present_modes, nil)
            gpu.present_modes = make([dynamic]vk.PresentModeKHR, num_present_modes)
            vk.GetPhysicalDeviceSurfacePresentModesKHR(gpu.device, surface, &num_present_modes, raw_data(gpu.present_modes))
        }

        // Get memory types supported by device
        vk.GetPhysicalDeviceMemoryProperties(gpu.device, &gpu.mem_properties)

        // Get actual device properties
        vk.GetPhysicalDeviceProperties(gpu.device, &gpu.device_properties)

        devices[i] = gpu
    }

    delete(device_list)

    return
}

vulkan_select_physical_device :: proc(devices: [dynamic]Vulkan_Graphics_Device, surface: vk.SurfaceKHR) -> (
    device_extensions: [dynamic]cstring,
    graphics_family: int,
    present_family: int,
    physical_device: vk.PhysicalDevice,
    graphics_device: ^Vulkan_Graphics_Device,
) {
    device_extensions = make([dynamic]cstring)
    append(&device_extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
    append(&device_extensions, vk.EXT_SHADER_OBJECT_EXTENSION_NAME)

    for &gpu, index in devices {
        graphics_idx := -1
        present_idx := -1

        // Ensure physical device supports our desired device extensions.
        if !vulkan_check_phys_device_ext_support(gpu, device_extensions) {
            fmt.println("Extension support not matched!")
            continue
        }

        // Ensure we actually have surface formats and present modes
        if len(gpu.surface_formats) == 0 || len(gpu.present_modes) == 0 {
            continue
        }

        // Loop through queue family properties looking for both a graphics and present queue
        // Index could end up being the same, but it's not guaranteed.

        // Find graphics queue family
        for &prop, index in gpu.queue_family_properties {
            if prop.queueCount == 0 {
                continue
            }

            if prop.queueFlags >= { .GRAPHICS } {
                graphics_idx = index
                break
            }
        }

        // Find present family
        for &prop, index in gpu.queue_family_properties {
            if prop.queueCount == 0 {
                continue
            }

            supports_present: b32 = false
            vk.GetPhysicalDeviceSurfaceSupportKHR(gpu.device, cast(u32)index, surface, &supports_present)
            if supports_present {
                present_idx = index
                break
            }
        }

        // If we found a device supporting both graphics and present, it's valid
        if graphics_idx >= 0 && present_idx >= 0 {
            graphics_family = graphics_idx
            present_family = present_idx
            physical_device = gpu.device
            device_name := strings.clone_from_bytes(gpu.device_properties.deviceName[:], context.temp_allocator)
            fmt.println("Selected GPU:", device_name)
            graphics_device = &gpu
            return
        }
    }

    // We can't render or present :(
    panic("Could not find a physical device!")
}

vulkan_create_logical_device_and_queues :: proc(
    extensions: [dynamic]cstring, 
    graphics_family: int, 
    present_family: int, 
    layers: [dynamic]cstring,
    physical_device: vk.PhysicalDevice,
    instance: vk.Instance,
) -> (
    device: vk.Device,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    functions: vma.VulkanFunctions,
    allocator: vma.Allocator,
) {
    // Add each family index to a list
    unique_idx := make([dynamic]int)
    append(&unique_idx, graphics_family)
    if graphics_family != present_family {
        append(&unique_idx, present_family)
    }

    dev_queue_info := make([dynamic]vk.DeviceQueueCreateInfo)

    priority: f32 = 1.0
    for id in unique_idx {
        qinfo := vk.DeviceQueueCreateInfo {
            sType = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = cast(u32)id,
            queueCount = 1,
        }

        qinfo.pQueuePriorities = &priority
        append(&dev_queue_info, qinfo)
    }

    // Enable physical device features
    device_features := vk.PhysicalDeviceFeatures {
        depthClamp = true,
        depthBounds = true,
        fillModeNonSolid = true,
    }

    extended_dynamic_state_feature := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
        sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
        pNext = nil,
        extendedDynamicState = true
    }

    shader_object_feature := vk.PhysicalDeviceShaderObjectFeaturesEXT {
        sType = .PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
        pNext = &extended_dynamic_state_feature,
        shaderObject = true,
    }

    device_features_11 := vk.PhysicalDeviceVulkan11Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        pNext = &shader_object_feature
    }

    device_features_12 := vk.PhysicalDeviceVulkan12Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        descriptorIndexing = true,
        vulkanMemoryModel = true,
        runtimeDescriptorArray = true,
        pNext = &device_features_11,
    }

    device_features_13 := vk.PhysicalDeviceVulkan13Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        synchronization2 = true,
        dynamicRendering = true,
        pNext = &device_features_12,
    }

    device_create_info := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        queueCreateInfoCount = cast(u32)len(dev_queue_info),
        pQueueCreateInfos = raw_data(dev_queue_info),
        pEnabledFeatures = &device_features,
        pNext = &device_features_13,
        enabledExtensionCount = cast(u32)len(extensions),
        ppEnabledExtensionNames = raw_data(extensions),
    }

    if ENABLE_LAYERS {
        device_create_info.enabledLayerCount = cast(u32)len(layers)
        device_create_info.ppEnabledLayerNames = raw_data(layers)
    } else {
        device_create_info.enabledLayerCount = 0
    }

    vkcheck(vk.CreateDevice(physical_device, &device_create_info, nil, &device))

    vk.load_proc_addresses_device(device)

    vk.GetDeviceQueue(device, cast(u32)graphics_family, 0, &graphics_queue)
    vk.GetDeviceQueue(device, cast(u32)present_family, 0, &present_queue)

    // Create VMA Allocator
    functions = vma.create_vulkan_functions()
    allocator_create_info := vma.AllocatorCreateInfo {
        pVulkanFunctions = &functions,
        physicalDevice = physical_device,
        device = device,
        instance = instance,
        vulkanApiVersion = vk.MAKE_VERSION(1, 3, 0),
    }
    vma.CreateAllocator(&allocator_create_info, &allocator)

    delete(unique_idx)
    delete(dev_queue_info)

    return
}

vulkan_create_semaphores :: proc(device: vk.Device, frames: [dynamic]Vulkan_Frame_Data) {
    semaphore_create_info := vk.SemaphoreCreateInfo {
        sType = .SEMAPHORE_CREATE_INFO
    }

    for i in 0..<FRAME_COUNT {
        vkcheck(vk.CreateSemaphore(device, &semaphore_create_info, nil, &frames[i].acquire_semaphore))
        vkcheck(vk.CreateSemaphore(device, &semaphore_create_info, nil, &frames[i].render_complete_semaphore))
    }

    return
}

vulkan_create_command_pool :: proc(graphics_family: int, device: vk.Device, frames: [dynamic]Vulkan_Frame_Data) {
    command_pool_create_info := vk.CommandPoolCreateInfo {
        sType = .COMMAND_POOL_CREATE_INFO,
        flags = { .RESET_COMMAND_BUFFER },
        queueFamilyIndex = cast(u32)graphics_family,
    }

    for i in 0..<FRAME_COUNT {
        vkcheck(vk.CreateCommandPool(device, &command_pool_create_info, nil, &frames[i].command_pool))
    }

    return
}

vulkan_create_command_buffer :: proc(device: vk.Device, frames: [dynamic]Vulkan_Frame_Data) {
    for i in 0..<FRAME_COUNT {
        command_buffer_allocate_info := vk.CommandBufferAllocateInfo {
            sType = .COMMAND_BUFFER_ALLOCATE_INFO,
            level = .PRIMARY,
            commandPool = frames[i].command_pool,
            commandBufferCount = FRAME_COUNT,
        }

        vkcheck(vk.AllocateCommandBuffers(device, &command_buffer_allocate_info, &frames[i].command_buffer))

        fence_create_info := vk.FenceCreateInfo {
            sType = .FENCE_CREATE_INFO
        }

        vkcheck(vk.CreateFence(device, &fence_create_info, nil, &frames[i].render_fence))
    }

    return
}

vulkan_create_swapchain :: proc(
    graphics_device: ^Vulkan_Graphics_Device,
    device: vk.Device,
    size: [2]u32,
    surface: vk.SurfaceKHR,
    graphics_family: int,
    present_family: int,
    frame_count: int,
) -> (
    swapchain: vk.SwapchainKHR,
    format: vk.Format,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    images: [dynamic]Vulkan_Image,
) {
    surface_format := vulkan_choose_surface_format(graphics_device.surface_formats[:])
    present_mode = vulkan_choose_present_mode(graphics_device.present_modes[:])
    extent = vulkan_choose_surface_extent(size, &graphics_device.surface_capabilities)

    images = make([dynamic]Vulkan_Image, frame_count)

    info := vk.SwapchainCreateInfoKHR {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = surface,
        minImageCount = FRAME_COUNT,
        imageFormat = surface_format.format,
        imageColorSpace = surface_format.colorSpace,
        imageExtent = extent,
        imageArrayLayers = 1,
        // Rendering into a Color image, copying the image somewhere later
        imageUsage = { .COLOR_ATTACHMENT, .TRANSFER_SRC }
    }

    if graphics_family != present_family {
        indices: [2]u32 = { cast(u32)graphics_family, cast(u32)present_family }

        // Only 2 sharing modes, use this one if they're not exclusive to one queue
        info.imageSharingMode = .CONCURRENT
        info.queueFamilyIndexCount = 2
        info.pQueueFamilyIndices = raw_data(indices[:])
    } else {
        // Same indices, queue can have exclusive access
        info.imageSharingMode = .EXCLUSIVE
    }

    info.preTransform = { .IDENTITY }
    info.compositeAlpha = { .OPAQUE }
    info.presentMode = present_mode

    format = surface_format.format

    // Allow discarding operations outside renderable space
    info.clipped = true

    // Create swapchain
    vkcheck(vk.CreateSwapchainKHR(device, &info, nil, &swapchain))

    // Retrieve swapchain images from device
    num_images: u32 = 0
    vkcheck(vk.GetSwapchainImagesKHR(device, swapchain, &num_images, nil))
    swapchain_images := make([dynamic]vk.Image, num_images)
    vkcheck(vk.GetSwapchainImagesKHR(device, swapchain, &num_images, raw_data(swapchain_images)))

    // Create image views
    for i := 0; i < FRAME_COUNT; i += 1 {
        image_view_create_info := vk.ImageViewCreateInfo {
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = swapchain_images[i],
            viewType = .D2,
            format = format,
            components = {
                r = .R,
                g = .G,
                b = .B,
                a = .A,
            },
            subresourceRange = {
                aspectMask = { .COLOR },
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1,
            },
            flags = {}
        }

        image_view: vk.ImageView
        vkcheck(vk.CreateImageView(device, &image_view_create_info, nil, &image_view))
        images[i] = Vulkan_Image {
            image = swapchain_images[i],
            view = image_view,
            format = surface_format.format,
            extent = extent,
            texture_format = .R8G8B8A8_UNORM,
            levels = 1,
            type = .Swap,
        }
    }

    delete(swapchain_images)

    return
}

vulkan_create_render_targets :: proc(physical_device: vk.PhysicalDevice, device: vk.Device, extent: vk.Extent2D, allocator: vma.Allocator) -> (depth_image: Vulkan_Image) {
    {
        formats := [?]vk.Format {
            .D32_SFLOAT_S8_UINT,
            .D24_UNORM_S8_UINT
        }

        depth_image.format = vulkan_choose_supported_format(physical_device, formats[:], .OPTIMAL, { .DEPTH_STENCIL_ATTACHMENT })
    }

    depth_image.extent = extent
    depth_image.filter = .Linear
    depth_image.levels = 1
    depth_image.repeat = .Repeat
    depth_image.type = .Depth
    
    vulkan_alloc_image(device, allocator, &depth_image)

    return
}