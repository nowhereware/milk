package milk_gfx_platform

import "core:fmt"
import "core:mem"
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

@(private="file")
alloc_counter: u32 = 0

Vulkan_Graphics_Device :: struct {
    device: vk.PhysicalDevice,
    queue_family_properties: [dynamic]vk.QueueFamilyProperties,
    extension_properties: [dynamic]vk.ExtensionProperties,
    surface_capabilities: vk.SurfaceCapabilities2KHR,
    surface_formats: [dynamic]vk.SurfaceFormat2KHR,
    present_modes: [dynamic]vk.PresentModeKHR,
    mem_properties: vk.PhysicalDeviceMemoryProperties,
    device_properties: vk.PhysicalDeviceProperties,
}

Vulkan_Frame_Resources :: struct {
    acquire_semaphore: vk.Semaphore,
    render_complete_semaphore: vk.Semaphore,
    render_fence: vk.Fence,
}

Vulkan_Frame_Data :: struct {
    // Multithreaded: Because we have many worker threads, we store each pool & buffer as a map pointing from the thread id to the
    // pool/buffer
    command_pool: map[int]vk.CommandPool,
    command_buffer: map[int]vk.CommandBuffer,
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

Vulkan_Buffer :: struct {
    buffer: vk.Buffer,
    allocation: vma.Allocation,
    address: vk.DeviceAddress,
}

Vulkan_Image :: struct {
    image: vk.Image,
    type: Vulkan_Image_Type,
    allocation: vma.Allocation,
}

Vulkan_Image_Resource :: struct {
    using vk_image: Vulkan_Image,
    view: vk.ImageView,
    extent: vk.Extent2D,
    layout: vk.ImageLayout,
}

Vulkan_Swap_Image :: struct {
    image: vk.Image,
    view: vk.ImageView,
}

Vulkan_SwapChain :: struct {
    graphics_device: ^Vulkan_Graphics_Device,
    device: vk.Device,
    present_queue: ^Vulkan_Queue_Info,
    graphics_queue: ^Vulkan_Queue_Info,
    surface: vk.SurfaceKHR,
    swapchain: vk.SwapchainKHR,
    image_format: vk.Format,
    command_pool: vk.CommandPool,

    next_images: [dynamic]Vulkan_Swap_Image,
    frame_resources: [dynamic]Vulkan_Frame_Resources,
    current_frame: u32,
    next_image_index: u32,
    need_rebuild: bool,
    max_frames_in_flight: u32,
}

Vulkan_Queue_Info :: struct {
    family_index: u32,
    queue_index: u32,
    queue: vk.Queue,
}

Vulkan_Resource_Allocator :: struct {
    allocator: vma.Allocator,
    device: vk.Device,
    staging_buffers: [dynamic]Vulkan_Buffer,
    leak_id: u32,
}

Vulkan_Sampler_Pool :: struct {
    device: vk.Device,
    sampler_map: map[string]vk.Sampler,
}

Vulkan_G_Buffer_Info :: struct {
    device: vk.Device,
    alloc: ^Vulkan_Resource_Allocator,
    size: vk.Extent2D,
    color_formats: [dynamic]vk.Format,
    depth_format: vk.Format,
    linear_sampler: vk.Sampler,
    sample_count: vk.SampleCountFlags,
}

Vulkan_G_Buffer :: struct {
    color_attachments: [dynamic]Vulkan_Image,
    depth_attachment: Vulkan_Image,
    depth_view: vk.ImageView,
    descriptors: [dynamic]vk.DescriptorImageInfo,
    ui_views: [dynamic]vk.ImageView,
    info: Vulkan_G_Buffer_Info,
    ui_descriptor_sets: [dynamic]vk.DescriptorSet,
}

vulkan_graphics_device_destroy :: proc(device: ^Vulkan_Graphics_Device) {
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

    instance_extensions := vulkan_get_available_instance_extensions()

    // Get desired SDL instance extensions
    inst_ext_count: u32 = 0
    sdl_exts := SDL.Vulkan_GetInstanceExtensions(&inst_ext_count)

    inst_ext_names := make([dynamic]cstring)

    for i in 0..<inst_ext_count {
        vulkan_request_extension(&inst_ext_names, sdl_exts[i], instance_extensions, true)
    }

    // Additional surface extensions
    vulkan_request_extension(&inst_ext_names, vk.EXT_SURFACE_MAINTENANCE_1_EXTENSION_NAME, instance_extensions)
    vulkan_request_extension(&inst_ext_names, vk.KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME, instance_extensions)

    layers = make([dynamic]cstring)

    if ENABLE_LAYERS {
        vulkan_request_extension(&inst_ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME, instance_extensions)
        layer_props := vulkan_get_available_layers()
        vulkan_request_layer(&layers, "VK_LAYER_KHRONOS_validation", layer_props, true)

        delete(layer_props)
    }

    inst_create_info.enabledExtensionCount = cast(u32)len(inst_ext_names)
    inst_create_info.ppEnabledExtensionNames = raw_data(inst_ext_names)
    inst_create_info.enabledLayerCount = cast(u32)len(layers)
    inst_create_info.ppEnabledLayerNames = raw_data(layers)

    vkcheck(vk.CreateInstance(&inst_create_info, nil, &instance))

    vk.load_proc_addresses_instance(instance)

    delete(inst_ext_names)
    delete(instance_extensions)

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
        surface_info := vk.PhysicalDeviceSurfaceInfo2KHR {
            sType = .PHYSICAL_DEVICE_SURFACE_INFO_2_KHR,
            surface = surface
        }

        gpu.surface_capabilities.sType = .SURFACE_CAPABILITIES_2_KHR
        vkcheck(vk.GetPhysicalDeviceSurfaceCapabilities2KHR(gpu.device, &surface_info, &gpu.surface_capabilities))

        {
            // Get supported surface formats
            num_formats: u32 = 0
            vk.GetPhysicalDeviceSurfaceFormats2KHR(gpu.device, &surface_info, &num_formats, nil)
            gpu.surface_formats = make([dynamic]vk.SurfaceFormat2KHR, num_formats)

            for &format in gpu.surface_formats {
                format.sType = .SURFACE_FORMAT_2_KHR
            }

            vk.GetPhysicalDeviceSurfaceFormats2KHR(gpu.device, &surface_info, &num_formats, raw_data(gpu.surface_formats))
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
    graphics_queue: Vulkan_Queue_Info,
    present_queue: Vulkan_Queue_Info,
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
            graphics_queue.family_index = u32(graphics_idx)
            present_queue.family_index = u32(present_idx)
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
    graphics_queue: ^Vulkan_Queue_Info, 
    present_queue: ^Vulkan_Queue_Info, 
    layers: [dynamic]cstring,
    physical_device: vk.PhysicalDevice,
    instance: vk.Instance,
) -> (
    device: vk.Device,
) {
    // Add each family index to a list
    unique_idx := make([dynamic]u32)
    append(&unique_idx, graphics_queue.family_index)
    if graphics_queue.family_index != present_queue.family_index {
        append(&unique_idx, present_queue.family_index)
    }

    dev_queue_info := make([dynamic]vk.DeviceQueueCreateInfo)

    priority: f32 = 1.0
    for id in unique_idx {
        qinfo := vk.DeviceQueueCreateInfo {
            sType = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = id,
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

    extended_dynamic_state_3_feature := vk.PhysicalDeviceExtendedDynamicState3FeaturesEXT {
        sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_3_FEATURES_EXT,
        pNext = nil,
    }

    extended_dynamic_state_2_feature := vk.PhysicalDeviceExtendedDynamicState2FeaturesEXT {
        sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT,
        pNext = &extended_dynamic_state_3_feature,
        extendedDynamicState2 = true,
    }

    extended_dynamic_state_feature := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
        sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
        pNext = &extended_dynamic_state_2_feature,
        extendedDynamicState = true
    }

    shader_object_feature := vk.PhysicalDeviceShaderObjectFeaturesEXT {
        sType = .PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
        pNext = &extended_dynamic_state_feature,
        shaderObject = true,
    }

    device_features_11 := vk.PhysicalDeviceVulkan11Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        pNext = &shader_object_feature,
    }

    device_features_12 := vk.PhysicalDeviceVulkan12Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        descriptorIndexing = true,
        shaderSampledImageArrayNonUniformIndexing = true,
        descriptorBindingSampledImageUpdateAfterBind = true,
        shaderUniformBufferArrayNonUniformIndexing = true,
        descriptorBindingUniformBufferUpdateAfterBind = true,
        shaderStorageBufferArrayNonUniformIndexing = true,
        descriptorBindingStorageBufferUpdateAfterBind = true,
        vulkanMemoryModel = true,
        runtimeDescriptorArray = true,
        timelineSemaphore = true,
        bufferDeviceAddress = true,
        pNext = &device_features_11,
    }

    device_features_13 := vk.PhysicalDeviceVulkan13Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        synchronization2 = true,
        dynamicRendering = true,
        pNext = &device_features_12,
    }

    device_features_14 := vk.PhysicalDeviceVulkan14Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_4_FEATURES,
        pushDescriptor = true,
        maintenance5 = true,
        maintenance6 = true,
        pNext = &device_features_13,
    }

    device_create_info := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        queueCreateInfoCount = cast(u32)len(dev_queue_info),
        pQueueCreateInfos = raw_data(dev_queue_info),
        pEnabledFeatures = &device_features,
        pNext = &device_features_14,
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

    vk.GetDeviceQueue(device, graphics_queue.family_index, 0, &graphics_queue.queue)
    vk.GetDeviceQueue(device, present_queue.family_index, 0, &present_queue.queue)

    delete(unique_idx)
    delete(dev_queue_info)

    return
}

vulkan_create_transient_command_pool :: proc(queue: ^Vulkan_Queue_Info, device: vk.Device) -> (out: vk.CommandPool) {
    info := vk.CommandPoolCreateInfo {
        sType = .COMMAND_POOL_CREATE_INFO,
        flags = { .TRANSIENT },
        queueFamilyIndex = queue.family_index
    }
    vkcheck(vk.CreateCommandPool(device, &info, nil, &out))
    return
}

vulkan_create_descriptor_pool :: proc(device: vk.Device, gpu: ^Vulkan_Graphics_Device) -> (max_textures: u32, pool: vk.DescriptorPool) {
    safeguard_size: u32 = 2
    max_descriptor_sets: u32 = min(1000, gpu.device_properties.limits.maxDescriptorSetUniformBuffers - safeguard_size)
    max_textures = 10000
    max_textures = min(max_textures, gpu.device_properties.limits.maxDescriptorSetSampledImages - safeguard_size)

    pool_sizes := make([dynamic]vk.DescriptorPoolSize)
    append(&pool_sizes, vk.DescriptorPoolSize {
        type = .COMBINED_IMAGE_SAMPLER,
        descriptorCount = max_textures,
    })

    pool_info := vk.DescriptorPoolCreateInfo {
        sType = .DESCRIPTOR_POOL_CREATE_INFO,
        flags = { .UPDATE_AFTER_BIND, .FREE_DESCRIPTOR_SET },
        maxSets = max_descriptor_sets,
        poolSizeCount = u32(len(pool_sizes)),
        pPoolSizes = raw_data(pool_sizes)
    }
    vkcheck(vk.CreateDescriptorPool(device, &pool_info, nil, &pool))
    return
}

// Creates the swapchain the first time.
// THIS SHOULD ONLY BE RUN ONCE. For further recreations, run vulkan_swapchain_init/deinit
vulkan_swapchain_create :: proc(
    graphics_device: ^Vulkan_Graphics_Device,
    device: vk.Device,
    graphics_queue: ^Vulkan_Queue_Info,
    present_queue: ^Vulkan_Queue_Info,
    pool: vk.CommandPool,
    surface: vk.SurfaceKHR,
) -> (swapchain: Vulkan_SwapChain) {
    swapchain.graphics_device = graphics_device
    swapchain.device = device
    swapchain.graphics_queue = graphics_queue
    swapchain.present_queue = present_queue
    swapchain.command_pool = pool
    swapchain.surface = surface

    swapchain.current_frame = 0
    swapchain.next_image_index = 0
    swapchain.need_rebuild = false
    swapchain.max_frames_in_flight = 3
    return
}

// Recreates a swapchain, given some data
vulkan_swapchain_init :: proc(
    swapchain: ^Vulkan_SwapChain,
    graphics_device: ^Vulkan_Graphics_Device,
    device: vk.Device,
    graphics_queue: ^Vulkan_Queue_Info,
    present_queue: ^Vulkan_Queue_Info,
    pool: vk.CommandPool,
    surface: vk.SurfaceKHR,
) {
    swapchain.graphics_device = graphics_device
    swapchain.device = device
    swapchain.graphics_queue = graphics_queue
    swapchain.present_queue = present_queue
    swapchain.command_pool = pool
    swapchain.surface = surface
}

vulkan_swapchain_init_resources :: proc(swapchain: ^Vulkan_SwapChain, vsync: bool = true) -> vk.Extent2D {
    out_window_size: vk.Extent2D

    surface_info_2 := vk.PhysicalDeviceSurfaceInfo2KHR {
        sType = .PHYSICAL_DEVICE_SURFACE_INFO_2_KHR,
        surface = swapchain.surface,
    }
    capabilities_2 := vk.SurfaceCapabilities2KHR {
        sType = .SURFACE_CAPABILITIES_2_KHR
    }
    vk.GetPhysicalDeviceSurfaceCapabilities2KHR(swapchain.graphics_device.device, &surface_info_2, &capabilities_2)

    surface_format := vulkan_choose_surface_format(swapchain.graphics_device.surface_formats[:])
    present_mode := vulkan_choose_present_mode(swapchain.graphics_device.present_modes[:])
    out_window_size = capabilities_2.surfaceCapabilities.currentExtent

    // Adjust number of images in flight within GPU limits
    min_image_count: u32 = capabilities_2.surfaceCapabilities.minImageCount
    preferred_image_count: u32 = max(3, min_image_count)

    max_image_count: u32 = capabilities_2.surfaceCapabilities.maxImageCount == 0 ? preferred_image_count : capabilities_2.surfaceCapabilities.maxImageCount

    swapchain.max_frames_in_flight = clamp(preferred_image_count, min_image_count, max_image_count)

    swapchain.image_format = surface_format.surfaceFormat.format

    swapchain_create_info := vk.SwapchainCreateInfoKHR {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = swapchain.surface,
        minImageCount = swapchain.max_frames_in_flight,
        imageFormat = surface_format.surfaceFormat.format,
        imageColorSpace = surface_format.surfaceFormat.colorSpace,
        imageExtent = capabilities_2.surfaceCapabilities.currentExtent,
        imageArrayLayers = 1,
        imageUsage = { .COLOR_ATTACHMENT, .TRANSFER_DST },
        imageSharingMode = .EXCLUSIVE,
        preTransform = capabilities_2.surfaceCapabilities.currentTransform,
        compositeAlpha = { .OPAQUE },
        presentMode = present_mode,
        clipped = true
    }

    if swapchain.graphics_queue.family_index != swapchain.present_queue.family_index {
        indices: [2]u32 = { swapchain.graphics_queue.family_index, swapchain.present_queue.family_index }

        // Only 2 sharing modes, use this one if they're not exclusive to one queue
        swapchain_create_info.imageSharingMode = .CONCURRENT
        swapchain_create_info.queueFamilyIndexCount = 2
        swapchain_create_info.pQueueFamilyIndices = raw_data(indices[:])
    } else {
        // Same indices, queue can have exclusive access
        swapchain_create_info.imageSharingMode = .EXCLUSIVE
    }

    fmt.println("About to create")

    vkcheck(vk.CreateSwapchainKHR(swapchain.device, &swapchain_create_info, nil, &swapchain.swapchain))

    // Retrieve the swapchain images
    image_count: u32
    vk.GetSwapchainImagesKHR(swapchain.device, swapchain.swapchain, &image_count, nil)
    assert(swapchain.max_frames_in_flight == image_count, "Wrong swapchain setup!")
    swap_images := make([dynamic]vk.Image, image_count)
    vk.GetSwapchainImagesKHR(swapchain.device, swapchain.swapchain, &image_count, raw_data(swap_images))

    fmt.println("Got images")

    resize(&swapchain.next_images, cast(int)swapchain.max_frames_in_flight)
    image_view_create_info := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        viewType = .D2,
        format = swapchain.image_format,
        components = {
            r = .IDENTITY,
            g = .IDENTITY,
            b = .IDENTITY,
            a = .IDENTITY,
        },
        subresourceRange = {
            aspectMask = { .COLOR },
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1
        }
    }

    for i in 0..<swapchain.max_frames_in_flight {
        swapchain.next_images[i].image = swap_images[i]
        image_view_create_info.image = swapchain.next_images[i].image
        vkcheck(vk.CreateImageView(swapchain.device, &image_view_create_info, nil, &swapchain.next_images[i].view))
    }

    fmt.println("Created image views")

    // Initialize frame resources for each frame
    resize(&swapchain.frame_resources, cast(int)swapchain.max_frames_in_flight)
    for i in 0..<swapchain.max_frames_in_flight {
        semaphore_create_info := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }
        vkcheck(vk.CreateSemaphore(swapchain.device, &semaphore_create_info, nil, &swapchain.frame_resources[i].acquire_semaphore))
        vkcheck(vk.CreateSemaphore(swapchain.device, &semaphore_create_info, nil, &swapchain.frame_resources[i].render_complete_semaphore))
    }

    fmt.println("Created semaphores")

    // Transition images to present layout
    {
        cmd := vulkan_begin_single_time_commands(swapchain.device, swapchain.command_pool)
        fmt.println("Got cmd")
        for i in 0..<swapchain.max_frames_in_flight {
            vulkan_transition_image_layout(cmd, swapchain.next_images[i].image, .UNDEFINED, .PRESENT_SRC_KHR)
        }
        fmt.println("Did command")
        vulkan_end_single_time_commands(&cmd, swapchain.device, swapchain.command_pool, swapchain.present_queue.queue)
        fmt.println("Ended commands")
    }

    fmt.println("Conducted commands.")

    delete(swap_images)

    return out_window_size
}

vulkan_swapchain_reinit_resources :: proc(swapchain: ^Vulkan_SwapChain, vsync: bool = true) -> vk.Extent2D {
    // Wait for all frames to finish rendering before recreating the swapchain
    vkcheck(vk.QueueWaitIdle(swapchain.present_queue.queue))

    swapchain.current_frame = 0
    swapchain.need_rebuild = false
    fmt.println("About to deinit")
    vulkan_swapchain_deinit_resources(swapchain)
    fmt.println("About to reinit")
    return vulkan_swapchain_init_resources(swapchain, vsync)
}

vulkan_swapchain_deinit_resources :: proc(swapchain: ^Vulkan_SwapChain) {
    vk.DestroySwapchainKHR(swapchain.device, swapchain.swapchain, nil)
    for data in swapchain.frame_resources {
        vk.DestroySemaphore(swapchain.device, data.acquire_semaphore, nil)
        vk.DestroySemaphore(swapchain.device, data.render_complete_semaphore, nil)
    }
    for image in swapchain.next_images {
        vk.DestroyImageView(swapchain.device, image.view, nil)
    }
}

vulkan_swapchain_acquire_next_image :: proc(swapchain: ^Vulkan_SwapChain) {
    assert(swapchain.need_rebuild == false)

    frame := &swapchain.frame_resources[swapchain.current_frame]

    result := vk.AcquireNextImageKHR(swapchain.device, swapchain.swapchain, max(u64), frame.acquire_semaphore, frame.render_fence, &swapchain.next_image_index)

    if result == .ERROR_OUT_OF_DATE_KHR {
        swapchain.need_rebuild = true
    } else {
        assert(result == .SUCCESS || result == .SUBOPTIMAL_KHR)
    }
}

vulkan_swapchain_present_frame :: proc(swapchain: ^Vulkan_SwapChain) {
    frame := swapchain.frame_resources[swapchain.current_frame]

    present_info := vk.PresentInfoKHR {
        sType = .PRESENT_INFO_KHR,
        waitSemaphoreCount = 1,
        pWaitSemaphores = &frame.render_complete_semaphore,
        swapchainCount = 1,
        pSwapchains = &swapchain.swapchain,
        pImageIndices = &swapchain.next_image_index,
    }

    result := vk.QueuePresentKHR(swapchain.present_queue.queue, &present_info)
    if result == .ERROR_OUT_OF_DATE_KHR {
        swapchain.need_rebuild = true
    } else {
        assert(result == .SUCCESS || result == .SUBOPTIMAL_KHR)
    }

    swapchain.current_frame = (swapchain.current_frame + 1) % swapchain.max_frames_in_flight
}

vulkan_swapchain_destroy :: proc(swapchain: ^Vulkan_SwapChain) {
    vulkan_swapchain_deinit_resources(swapchain)
    delete(swapchain.next_images)
    delete(swapchain.frame_resources)
}

vulkan_create_frame_submission :: proc(num_frames: u32, device: vk.Device, frame_data: ^[dynamic]Vulkan_Frame_Data) -> (semaphore: vk.Semaphore) {
    resize(frame_data, num_frames)

    // Create timeline semaphore with numframes - 1
    initial_value: u64 = cast(u64)num_frames - 1

    timeline_create_info := vk.SemaphoreTypeCreateInfo {
        sType = .SEMAPHORE_TYPE_CREATE_INFO,
        pNext = nil,
        semaphoreType = .TIMELINE,
        initialValue = initial_value
    }

    semaphore_create_info := vk.SemaphoreCreateInfo {
        sType = .SEMAPHORE_CREATE_INFO,
        pNext = &timeline_create_info,
    }

    vkcheck(vk.CreateSemaphore(device, &semaphore_create_info, nil, &semaphore))
    return
}

vulkan_resource_allocator_new :: proc(allocator_info: vma.AllocatorCreateInfo) -> (out: Vulkan_Resource_Allocator) {
    allocator_info := allocator_info
    allocator_info.flags += { .BUFFER_DEVICE_ADDRESS }

    out.device = allocator_info.device
    functions := vma.create_vulkan_functions()
    allocator_info.pVulkanFunctions = &functions
    vma.CreateAllocator(&allocator_info, &out.allocator)
    return
}

vulkan_resource_allocator_destroy :: proc(allocator: ^Vulkan_Resource_Allocator) {
    if len(allocator.staging_buffers) != 0 {
        fmt.println("Staging buffers were not freed before destroying allocator!")
    }
    vulkan_free_staging_buffers(allocator)
    vma.DestroyAllocator(allocator.allocator)
}

vulkan_create_buffer :: proc(
    allocator: ^Vulkan_Resource_Allocator,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags2,
    memory_usage: vma.MemoryUsage = vma.MemoryUsage.AUTO,
    flags: vma.AllocationCreateFlags = {}
) -> Vulkan_Buffer {
    buffer_usage_flags_2_create_info := vk.BufferUsageFlags2CreateInfo {
        sType = .BUFFER_USAGE_FLAGS_2_CREATE_INFO,
        usage = usage + { .SHADER_DEVICE_ADDRESS }
    }

    buffer_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        pNext = &buffer_usage_flags_2_create_info,
        size = size,
        usage = {},
        sharingMode = .EXCLUSIVE,
    }

    alloc_info := vma.AllocationCreateInfo { flags = flags, usage = memory_usage }
    dedicated_memory_min_size: vk.DeviceSize = 64 * 1024
    if size > dedicated_memory_min_size {
        alloc_info.flags += { .DEDICATED_MEMORY }
    }

    result_buffer: Vulkan_Buffer
    alloc_info_out: vma.AllocationInfo
    vkcheck(vma.CreateBuffer(allocator.allocator, &buffer_info, &alloc_info, &result_buffer.buffer, &result_buffer.allocation, &alloc_info_out))

    info := vk.BufferDeviceAddressInfo {
        sType = .BUFFER_DEVICE_ADDRESS_INFO,
        buffer = result_buffer.buffer
    }
    result_buffer.address = vk.GetBufferDeviceAddress(allocator.device, &info)

    {
        vma.SetAllocationName(allocator.allocator, result_buffer.allocation, strings.clone_to_cstring(fmt.tprint("allocID:", alloc_counter)))
        alloc_counter += 1
    }

    return result_buffer
}

vulkan_destroy_buffer :: proc(allocator: ^Vulkan_Resource_Allocator, buffer: Vulkan_Buffer) {
    vma.DestroyBuffer(allocator.allocator, buffer.buffer, buffer.allocation)
}

vulkan_create_staging_buffer :: proc(allocator: ^Vulkan_Resource_Allocator, vector_data: ^[dynamic]$T) -> Vulkan_Buffer {
    buffer_size: vk.DeviceSize = size_of(T) * len(vector_data)

    staging_buffer := vulkan_create_buffer(allocator, buffer_size, { .TRANSFER_SRC }, .CPU_TO_GPU, { .HOST_ACCESS_SEQUENTIAL_WRITE })

    append(&allocator.staging_buffers, staging_buffer)

    data: rawptr
    vma.MapMemory(allocator.allocator, staging_buffer.allocation, &data)
    mem.copy(data, raw_data(vector_data), buffer_size)
    vma.UnmapMemory(allocator.allocator, staging_buffer.allocation)
    return staging_buffer
}

vulkan_create_buffer_and_upload_data :: proc(
    cmd: vk.CommandBuffer,
    vector_data: ^[dynamic]$T,
    usage_flags: vk.BufferUsageFlags2
) -> Vulkan_Buffer {
    // Create staging buffer and upload data
    staging_buffer := vulkan_create_staging_buffer(allocator, vector_data)

    // Create final buffer in GPU memory
    buffer_size: vk.DeviceSize = size_of(T) * len(vector_data)
    buffer := vulkan_create_buffer(allocator, buffer_size, usage_flags + { .TRANSFER_DST }, .GPU_ONLY)

    copy_region := make([dynamic]vk.BufferCopy, 1)
    append(&copy_region, vk.BufferCopy {
        size = buffer_size
    })
    vk.CmdCopyBuffer(cmd, staging_buffer.buffer, buffer.buffer, u32(len(copy_region)), raw_data(copy_region))

    return buffer
}

vulkan_create_image :: proc(allocator: ^Vulkan_Resource_Allocator, image_info: ^vk.ImageCreateInfo) -> Vulkan_Image {
    create_info := vma.AllocationCreateInfo {
        usage = .GPU_ONLY
    }

    image: Vulkan_Image
    alloc_info: vma.AllocationInfo
    vkcheck(vma.CreateImage(allocator.allocator, image_info, &create_info, &image.image, &image.allocation, &alloc_info))
    return image
}

vulkan_destroy_image :: proc(allocator: ^Vulkan_Resource_Allocator, image: ^Vulkan_Image) {
    vma.DestroyImage(allocator.allocator, image.image, image.allocation)
}

vulkan_destroy_image_resource :: proc(allocator: ^Vulkan_Resource_Allocator, image_resource: ^Vulkan_Image_Resource) {
    vulkan_destroy_image(allocator, image_resource)
    vk.DestroyImageView(allocator.device, image_resource.view, nil)
}

vulkan_create_image_and_upload_data :: proc(
    allocator: ^Vulkan_Resource_Allocator,
    cmd: vk.CommandBuffer,
    vector_data: ^[dynamic]$T,
    image_info: ^vk.ImageCreateInfo,
    final_layout: vk.ImageLayout,
) -> Vulkan_Image_Resource {
    staging_buffer := vulkan_create_staging_buffer(allocator, vector_data)

    image_info := image_info^
    image_info.usage += { .TRANSFER_DST }
    image := vulkan_create_image(allocator, &image_info)

    vulkan_transition_image_layout(cmd, image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL)

    // Copy buffer data to image
    copy_region := make([dynamic]vk.BufferImageCopy, 1)
    append(&copy_region, vk.BufferImageCopy {
        imageSubresource = {
            aspectMask = { .COLOR },
            layerCount = 1,
        },
        imageExtent = image_info.extent
    })

    vk.CmdCopyBufferToImage(cmd, staging_buffer.buffer, image.image, .TRANSFER_DST_OPTIMAL, u32(len(copy_region)), raw_data(copy_region))

    // Transition image layout to final layout
    vulkan_transition_image_layout(cmd, image.image, .TRANSFER_DST_OPTIMAL, final_layout)

    result_image: Vulkan_Image_Resource = image
    result_image.layout = final_layout
    return result_image
}

vulkan_free_staging_buffers :: proc(allocator: ^Vulkan_Resource_Allocator) {
    for &buffer in allocator.staging_buffers {
        vulkan_destroy_buffer(allocator, buffer)
    }
    clear(&allocator.staging_buffers)
}

vulkan_sampler_pool_new :: proc(device: vk.Device) -> Vulkan_Sampler_Pool {
    return {
        device = device,
        sampler_map = {},
    }
}

vulkan_sampler_pool_destroy :: proc(pool: ^Vulkan_Sampler_Pool) {
    for _, val in pool.sampler_map {
        vk.DestroySampler(pool.device, val, nil)
    }
    clear_map(&pool.sampler_map)
}

vulkan_acquire_sampler :: proc(pool: ^Vulkan_Sampler_Pool, info: ^vk.SamplerCreateInfo) -> vk.Sampler {
    hash := vulkan_create_sampler_hash(info^)

    if hash in pool.sampler_map {
        return pool.sampler_map[hash]
    }

    new_sampler := vulkan_create_sampler(pool.device, info)
    pool.sampler_map[hash] = new_sampler
    return new_sampler
}

vulkan_release_sampler :: proc(pool: ^Vulkan_Sampler_Pool, sampler: vk.Sampler) {
    for key, val in pool.sampler_map {
        if val == sampler {
            vk.DestroySampler(pool.device, val, nil)
            delete_key(&pool.sampler_map, key)
        }
    }
}

vulkan_g_buffer_new :: proc(info: Vulkan_G_Buffer_Info, cmd: vk.CommandBuffer) -> (out: Vulkan_G_Buffer) {
    out.info = info

    vulkan_g_buffer_create(&out, cmd)
    return
}

vulkan_g_buffer_create :: proc(buffer: ^Vulkan_G_Buffer, cmd: vk.CommandBuffer) {
    layout: vk.ImageLayout = .GENERAL

    num_color := cast(u32)len(buffer.info.color_formats)

    resize(&buffer.color_attachments, num_color)
    resize(&buffer.descriptors, num_color)
    resize(&buffer.ui_views, num_color)
    resize(&buffer.ui_descriptor_sets, num_color)

    for i in 0..<num_color {
        {
            // Color image
            usage: vk.ImageUsageFlags = { .COLOR_ATTACHMENT, .SAMPLED, .STORAGE, .TRANSFER_SRC, .TRANSFER_DST }
            info := vk.ImageCreateInfo {
                sType = .IMAGE_CREATE_INFO,
                imageType = .D2,
                format = buffer.info.color_formats[i],
                extent = { buffer.info.size.width, buffer.info.size.height, 1 },
                mipLevels = 1,
                arrayLayers = 1,
                samples = buffer.info.sample_count,
                usage = usage
            }
            buffer.color_attachments[i] = vulkan_create_image(buffer.info.alloc, &info)
        }
        {
            // Image color view
            info := vk.ImageViewCreateInfo {
                sType = .IMAGE_VIEW_CREATE_INFO,
                image = buffer.color_attachments[i].image,
                viewType = .D2,
                format = buffer.info.color_formats[i],
                subresourceRange = { aspectMask = { .COLOR }, levelCount = 1, layerCount = 1 }
            }
            vk.CreateImageView(buffer.info.device, &info, nil, &buffer.descriptors[i].imageView)

            // UI Image color view
            info.components.a = .ONE
            vk.CreateImageView(buffer.info.device, &info, nil, &buffer.ui_views[i])
        }

        // Set sampler
        buffer.descriptors[i].sampler = buffer.info.linear_sampler
    }

    if buffer.info.depth_format != .UNDEFINED {
        // Depth buffer
        info := vk.ImageCreateInfo {
            sType = .IMAGE_CREATE_INFO,
            imageType = .D2,
            format = buffer.info.depth_format,
            extent = { buffer.info.size.width, buffer.info.size.height, 1 },
            mipLevels = 1,
            arrayLayers = 1,
            samples = buffer.info.sample_count,
            usage = { .DEPTH_STENCIL_ATTACHMENT, .SAMPLED }
        }
        buffer.depth_attachment = vulkan_create_image(buffer.info.alloc, &info)

        // Image depth view
        view_info := vk.ImageViewCreateInfo {
            sType = .IMAGE_VIEW_CREATE_INFO,
            image = buffer.depth_attachment.image,
            viewType = .D2,
            format = buffer.info.depth_format,
            subresourceRange = { aspectMask = { .DEPTH }, levelCount = 1, layerCount = 1 }
        }
        vk.CreateImageView(buffer.info.device, &view_info, nil, &buffer.depth_view)
    }

    {
        // Change color image layout
        for i in 0..<num_color {
            vulkan_transition_image_layout(cmd, buffer.color_attachments[i].image, .UNDEFINED, layout)
            buffer.descriptors[i].imageLayout = layout

            // Clear to avoid garbage data
            clear_value := vk.ClearColorValue { float32 = { 0, 0, 0, 1 } }
            range := vk.ImageSubresourceRange { aspectMask = { .COLOR }, levelCount = 1, layerCount = 1 }
            vk.CmdClearColorImage(cmd, buffer.color_attachments[i].image, layout, &clear_value, 1, &range)
        }
    }

    // IMGUI Descriptor set would go here
}

vulkan_g_buffer_destroy :: proc(buffer: ^Vulkan_G_Buffer) {
    for &image in buffer.color_attachments {
        vulkan_destroy_image(buffer.info.alloc, &image)
    }

    if buffer.depth_attachment.image != 0 {
        vulkan_destroy_image(buffer.info.alloc, &buffer.depth_attachment)
    }

    vk.DestroyImageView(buffer.info.device, buffer.depth_view, nil)

    for desc in buffer.descriptors {
        vk.DestroyImageView(buffer.info.device, desc.imageView, nil)
    }

    for view in buffer.ui_views {
        vk.DestroyImageView(buffer.info.device, view, nil)
    }
}

vulkan_g_buffer_update :: proc(buffer: ^Vulkan_G_Buffer, cmd: vk.CommandBuffer, new_size: vk.Extent2D) {
    if new_size.width == buffer.info.size.width && new_size.height == buffer.info.size.height {
        return
    }

    vulkan_g_buffer_destroy(buffer)
    buffer.info.size = new_size
    vulkan_g_buffer_create(buffer, cmd)
}