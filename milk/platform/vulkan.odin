package milk_platform

import odin_queue "core:container/queue"
import "core:fmt"
import "core:mem"
import "core:strings"
import vk "vendor:vulkan"
import SDL "vendor:sdl3"
import "../../lib/vma"

when ODIN_DEBUG {
    ENABLE_LAYERS :: true
} else {
    ENABLE_LAYERS :: false
}

Vk_Features :: struct {
    features_10: vk.PhysicalDeviceFeatures2,
    features_11: vk.PhysicalDeviceVulkan11Features,
    features_12: vk.PhysicalDeviceVulkan12Features,
    features_13: vk.PhysicalDeviceVulkan13Features,
    features_14: vk.PhysicalDeviceVulkan14Features,
}

Vk_Queue :: struct {
    family_index: u32,
    queue: vk.Queue,
}

Vk_Color_Space :: enum {
    SRGB_LINEAR,
    SRGB_NONLINEAR,
}

Vk_Viewport :: struct {
    position: Vector2,
    size: Vector2,
    depth: Vector2,
}

Vk_Scissor_Rect :: struct {
    position: UVector2,
    size: UVector2,
}

Vk_Compare_Op :: enum {
    Never,
    Less,
    Equal,
    Less_Equal,
    Greater,
    Not_Equal,
    Greater_Equal,
    Always_Pass,
}

Vk_Depth_State :: struct {
    compare_op: Vk_Compare_Op,
    is_depth_write_enabled: bool,
}

vk_create_instance :: proc(rend: ^Vk_Renderer, app_info: ^vk.ApplicationInfo) {
    inst_create_info := vk.InstanceCreateInfo {
        sType = .INSTANCE_CREATE_INFO,
        pApplicationInfo = app_info,
        flags = nil,
    }

    vk.load_proc_addresses_global(cast(rawptr)SDL.Vulkan_GetVkGetInstanceProcAddr())
    assert(vk.CreateInstance != nil)

    instance_extensions := vk_get_available_instance_extensions()

    // Get desired SDL instance extensions
    inst_ext_count: u32 = 0
    sdl_exts := SDL.Vulkan_GetInstanceExtensions(&inst_ext_count)

    inst_ext_names := make([dynamic]cstring)

    for i in 0..<inst_ext_count {
        vk_request_extension(&inst_ext_names, sdl_exts[i], instance_extensions, true)
    }

    // Additional surface extensions
    vk_request_extension(&inst_ext_names, vk.EXT_SURFACE_MAINTENANCE_1_EXTENSION_NAME, instance_extensions)
    vk_request_extension(&inst_ext_names, vk.KHR_GET_SURFACE_CAPABILITIES_2_EXTENSION_NAME, instance_extensions)

    rend.validation_layers = make([dynamic]cstring)

    if ENABLE_LAYERS {
        vk_request_extension(&inst_ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME, instance_extensions)

        layer_props := vk_get_available_layers()
        vk_request_layer(&rend.validation_layers, "VK_LAYER_KHRONOS_validation", layer_props, true)

        delete(layer_props)
    }

    inst_create_info.enabledExtensionCount = cast(u32)len(inst_ext_names)
    inst_create_info.ppEnabledExtensionNames = raw_data(inst_ext_names)
    inst_create_info.enabledLayerCount = cast(u32)len(rend.validation_layers)
    inst_create_info.ppEnabledLayerNames = raw_data(rend.validation_layers)

    vkcheck(vk.CreateInstance(&inst_create_info, nil, &rend.instance))

    vk.load_proc_addresses_instance(rend.instance)

    delete(inst_ext_names)
    delete(instance_extensions)

    return
}

vk_create_surface :: proc(rend: ^Vk_Renderer, window: ^SDL.Window) {
    SDL.Vulkan_CreateSurface(window, rend.instance, nil, &rend.surface)
}

vk_has_extension :: proc(exts: [dynamic]vk.ExtensionProperties, name: cstring) -> bool {
    search := strings.clone_from_cstring(name, context.temp_allocator)
    for &ext in exts {
        ext_name := strings.clone_from_bytes(ext.extensionName[:], context.temp_allocator)
        if strings.contains(ext_name, search) {
            return true
        }
    }
    return false
}

vk_add_optional_extension :: proc(exts: [dynamic]vk.ExtensionProperties, name: cstring, names: ^[dynamic]cstring, create_info: ^rawptr = nil, features: rawptr = nil) -> bool {
    if !vk_has_extension(exts, name) {
        return false
    }

    append(names, name)

    if create_info != nil && features != nil {
        feats := cast(^vk.BaseOutStructure)features
        feats.pNext = cast(^vk.BaseOutStructure)create_info^
        create_info^ = features
    }
    return true
}

vk_create_device :: proc(rend: ^Vk_Renderer) {
    // Create queues
    rend.graphics_queue.family_index = cast(u32)vk_find_queue_family_index(rend.graphics_device.device, { .GRAPHICS })
    rend.compute_queue.family_index = cast(u32)vk_find_queue_family_index(rend.graphics_device.device, { .COMPUTE })
    queue_priority: f32 = 1.0
    ci_queue := [2]vk.DeviceQueueCreateInfo {
        {
            sType = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = rend.graphics_queue.family_index,
            queueCount = 1,
            pQueuePriorities = &queue_priority
        },
        {
            sType = .DEVICE_QUEUE_CREATE_INFO,
            queueFamilyIndex = rend.compute_queue.family_index,
            queueCount = 1,
            pQueuePriorities = &queue_priority,
        }
    }

    num_queues: u32 = rend.graphics_queue.family_index == rend.compute_queue.family_index ? 1 : 2

    // Create features
    features := rend.graphics_device.features
    device_features_10 := vk.PhysicalDeviceFeatures {
        geometryShader = features.features_10.features.geometryShader,
        tessellationShader = features.features_10.features.tessellationShader,
        sampleRateShading = true,
        multiDrawIndirect = true,
        drawIndirectFirstInstance = true,
        depthBiasClamp = true,
        fillModeNonSolid = features.features_10.features.fillModeNonSolid,
        samplerAnisotropy = true,
        textureCompressionBC = features.features_10.features.textureCompressionBC,
        vertexPipelineStoresAndAtomics = features.features_10.features.vertexPipelineStoresAndAtomics,
        fragmentStoresAndAtomics = true,
        shaderImageGatherExtended = true,
        shaderInt64 = features.features_10.features.shaderInt64,
    }
    device_features_11 := vk.PhysicalDeviceVulkan11Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        pNext = nil,
        storageBuffer16BitAccess = true,
        samplerYcbcrConversion = features.features_11.samplerYcbcrConversion,
        shaderDrawParameters = true,
    }
    device_features_12 := vk.PhysicalDeviceVulkan12Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        pNext = &device_features_11,
        drawIndirectCount = features.features_12.drawIndirectCount,
        storageBuffer8BitAccess = features.features_12.storageBuffer8BitAccess,
        uniformAndStorageBuffer8BitAccess = features.features_12.uniformAndStorageBuffer8BitAccess,
        shaderFloat16 = features.features_12.shaderFloat16,
        descriptorIndexing = true,
        shaderSampledImageArrayNonUniformIndexing = true,
        descriptorBindingSampledImageUpdateAfterBind = true,
        descriptorBindingStorageImageUpdateAfterBind = true,
        descriptorBindingUpdateUnusedWhilePending = true,
        descriptorBindingPartiallyBound = true,
        descriptorBindingVariableDescriptorCount = true,
        runtimeDescriptorArray = true,
        scalarBlockLayout = true,
        uniformBufferStandardLayout = true,
        hostQueryReset = features.features_12.hostQueryReset,
        timelineSemaphore = true,
        bufferDeviceAddress = true,
        vulkanMemoryModel = features.features_12.vulkanMemoryModel,
        vulkanMemoryModelDeviceScope = features.features_12.vulkanMemoryModelDeviceScope,
    }
    device_features_13 := vk.PhysicalDeviceVulkan13Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        pNext = &device_features_12,
        subgroupSizeControl = true,
        synchronization2 = true,
        dynamicRendering = true,
        maintenance4 = true,
    }

    create_info_next: rawptr = &device_features_13

    // Create optional extensions
    device_extension_names := make([dynamic]cstring)
    append(&device_extension_names, vk.KHR_SWAPCHAIN_EXTENSION_NAME)

    accel_structure_features := vk.PhysicalDeviceAccelerationStructureFeaturesKHR {
        sType = .PHYSICAL_DEVICE_ACCELERATION_STRUCTURE_FEATURES_KHR,
        accelerationStructure = true,
        accelerationStructureCaptureReplay = false,
        accelerationStructureIndirectBuild = false,
        accelerationStructureHostCommands = false,
        descriptorBindingAccelerationStructureUpdateAfterBind = true,
    }

    ray_tracing_features := vk.PhysicalDeviceRayTracingPipelineFeaturesKHR {
        sType = .PHYSICAL_DEVICE_RAY_TRACING_PIPELINE_FEATURES_KHR,
        rayTracingPipeline = true,
        rayTracingPipelineShaderGroupHandleCaptureReplay = false,
        rayTracingPipelineShaderGroupHandleCaptureReplayMixed = false,
        rayTracingPipelineTraceRaysIndirect = true,
        rayTraversalPrimitiveCulling = false,
    }

    ray_query_features := vk.PhysicalDeviceRayQueryFeaturesKHR {
        sType = .PHYSICAL_DEVICE_RAY_QUERY_FEATURES_KHR,
        rayQuery = true,
    }

    index_type_uint8_features := vk.PhysicalDeviceIndexTypeUint8Features {
        sType = .PHYSICAL_DEVICE_INDEX_TYPE_UINT8_FEATURES,
        indexTypeUint8 = true,
    }

    vk_add_optional_extension(
        rend.graphics_device.extensions, 
        vk.KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, 
        &device_extension_names, 
        &create_info_next, 
        &accel_structure_features
    )

    vk_add_optional_extension(
        rend.graphics_device.extensions,
        vk.KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME,
        &device_extension_names,
    )

    vk_add_optional_extension(
        rend.graphics_device.extensions,
        vk.KHR_RAY_QUERY_EXTENSION_NAME,
        &device_extension_names,
        &create_info_next,
        &ray_query_features
    )

    vk_add_optional_extension(
        rend.graphics_device.extensions,
        vk.KHR_RAY_TRACING_PIPELINE_EXTENSION_NAME,
        &device_extension_names,
        &create_info_next,
        &ray_tracing_features,
    )

    vk_add_optional_extension(
        rend.graphics_device.extensions,
        vk.EXT_INDEX_TYPE_UINT8_EXTENSION_NAME,
        &device_extension_names,
        &create_info_next,
        &index_type_uint8_features,
    )

    for name in device_extension_names {
        fmt.println(name)
    }

    info := vk.DeviceCreateInfo {
        sType = .DEVICE_CREATE_INFO,
        pNext = create_info_next,
        queueCreateInfoCount = num_queues,
        pQueueCreateInfos = raw_data(ci_queue[:]),
        enabledExtensionCount = cast(u32)len(device_extension_names),
        ppEnabledExtensionNames = raw_data(device_extension_names),
        pEnabledFeatures = &device_features_10,
    }
    vkcheck(vk.CreateDevice(rend.graphics_device.device, &info, nil, &rend.device))

    vk.load_proc_addresses_device(rend.device)

    vk.GetDeviceQueue(rend.device, rend.graphics_queue.family_index, 0, &rend.graphics_queue.queue)
    vk.GetDeviceQueue(rend.device, rend.compute_queue.family_index, 0, &rend.compute_queue.queue)

    delete(device_extension_names)
}

Handle_Id :: u64

Vk_Handle :: struct($T: typeid) {
    id: Handle_Id
}

Vk_Pool :: struct($T: typeid) {
    data: [dynamic]T,
    id_map: map[Handle_Id]int,
    index_map: [dynamic]Handle_Id,
    available_ids: odin_queue.Queue(Handle_Id),
    id_count: u64
}

vk_pool_new :: proc($T: typeid) -> (out: Vk_Pool(T)) {
    out.data = make([dynamic]T)
    out.id_map = {}
    odin_queue.init(&out.available_ids)
    odin_queue.push(&out.available_ids, 0)
    return
}

vk_pool_get_new_id :: proc(pool: ^Vk_Pool($T)) -> Handle_Id {
    out := odin_queue.pop_back(&pool.available_ids)
    if out == pool.id_count {
        // Possibly ran out of recycled ids, add a new id to the queue
        pool.id_count += 1
        odin_queue.push(&pool.available_ids, pool.id_count)
    }
    return out
}

vk_pool_create :: proc(pool: ^Vk_Pool($T), data: T) -> Vk_Handle(T) {
    id := vk_pool_get_new_id(pool)

    append(&pool.data, data)
    pool.id_map[id] = len(pool.data) - 1
    append(&pool.index_map, id)

    return {
        id = id
    }
}

vk_pool_get :: proc(pool: ^Vk_Pool($T), handle: Vk_Handle(T)) -> T {
    index := pool.id_map[handle.id]
    return pool.data[index]
}

vk_pool_get_ptr :: proc(pool: ^Vk_Pool($T), handle: Vk_Handle(T)) -> ^T {
    index := pool.id_map[handle.id]
    return &pool.data[index]
}

vk_pool_remove :: proc(pool: ^Vk_Pool($T), handle: Vk_Handle(T)) {
    old_index := pool.id_map[handle.id]

    new_handle := pool.index_map[len(pool.index_map) - 1]

    unordered_remove(&pool.data, old_index)
    unordered_remove(&pool.index_map, old_index)
    pool.id_map[new_handle] = old_index

    delete_key(&pool.id_map, handle.id)

    odin_queue.push(&pool.available_ids, handle.id)
}

vk_pool_destroy :: proc(pool: ^Vk_Pool($T)) {
    delete(pool.data)
    delete(pool.id_map)
    delete(pool.index_map)
    odin_queue.destroy(&pool.available_ids)
}

Vk_Image :: struct {
    image: vk.Image,
    usage_flags: vk.ImageUsageFlags,
    memory: [3]vk.DeviceMemory,
    allocation: vma.Allocation,
    format_properties: vk.FormatProperties,
    extent: vk.Extent3D,
    type: vk.ImageType,
    image_format: vk.Format,
    samples: vk.SampleCountFlags,
    mapped_ptr: rawptr,
    is_swapchain_image: bool,
    is_owning_vk_image: bool,
    num_levels: u32,
    num_layers: u32,
    is_depth_format: bool,
    is_stencil_format: bool,
    image_layout: vk.ImageLayout,
    // Precached image views
    image_view: vk.ImageView, // Default view with all mip-levels
    image_view_storage: vk.ImageView, // Default view with identity swizzle (all mip-levels)
    image_view_for_framebuffer: [6][MAX_MIP_LEVELS]vk.ImageView, // Max 6 faces for cubemap rendering
}

vk_image_create_image_view :: proc(
    image: ^Vk_Image,
    device: vk.Device,
    type: vk.ImageViewType,
    format: vk.Format,
    aspect_mask: vk.ImageAspectFlags,
    base_level: u32,
    num_levels: u32,
    base_layer: u32,
    num_layers: u32,
    mapping: vk.ComponentMapping = {
        r = .IDENTITY,
        g = .IDENTITY,
        b = .IDENTITY,
        a = .IDENTITY,
    },
    ycbcr: ^vk.SamplerYcbcrConversionInfo = nil,
) -> vk.ImageView {
    info := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        pNext = ycbcr,
        image = image.image,
        viewType = type,
        format = format,
        components = mapping,
        subresourceRange = {
            aspectMask = aspect_mask,
            baseMipLevel = base_level,
            levelCount = num_levels != 0 ? num_levels : image.num_levels,
            baseArrayLayer = base_layer,
            layerCount = num_layers
        }
    }

    out: vk.ImageView
    vkcheck(vk.CreateImageView(device, &info, nil, &out))

    return out
}

MAX_SWAPCHAIN_IMAGES :: 16
MAX_MIP_LEVELS :: 16

Vk_Swapchain :: struct {
    swapchain: vk.SwapchainKHR,
    renderer: ^Vk_Renderer,
    device: ^Vk_Graphics_Device,
    graphics_queue: ^Vk_Queue,
    extent: vk.Extent2D,
    format: vk.SurfaceFormatKHR,
    images: [dynamic]vk.Image,
    wait_values: [MAX_SWAPCHAIN_IMAGES]u64,
    current_frame_index: u64,
    current_image_index: u32,
    timeline_semaphore: vk.Semaphore,
    acquire_semaphores: [MAX_SWAPCHAIN_IMAGES]vk.Semaphore,
    swapchain_textures: [MAX_SWAPCHAIN_IMAGES]Vk_Texture,
}

vk_create_swapchain :: proc(rend: ^Vk_Renderer, width, height: u32) {
    swapchain := Vk_Swapchain {
        renderer = rend,
        device = rend.graphics_device,
        graphics_queue = &rend.graphics_queue,
        extent = { width = width, height = height }
    }

    surface_format := vk_choose_swap_surface_format(swapchain.device.surface_formats, rend.color_space)
    swapchain.format = surface_format
    queue_family_supports_presentation: b32 = false
    vk.GetPhysicalDeviceSurfaceSupportKHR(swapchain.device.device, swapchain.graphics_queue.family_index, rend.surface, &queue_family_supports_presentation)

    choose_usage_flags :: proc(device: ^Vk_Graphics_Device, surface: vk.SurfaceKHR, format: vk.Format) -> vk.ImageUsageFlags {
        usage_flags: vk.ImageUsageFlags = { .COLOR_ATTACHMENT, .TRANSFER_DST, .TRANSFER_SRC }
        is_storage_supported := device.surface_caps.supportedUsageFlags & { .STORAGE } != {}
        props: vk.FormatProperties
        vk.GetPhysicalDeviceFormatProperties(device.device, format, &props)
        is_tiling_optimal_supported := props.optimalTilingFeatures & { .STORAGE_IMAGE } != {}
        if is_storage_supported && is_tiling_optimal_supported {
            usage_flags += { .STORAGE }
        }
        return usage_flags
    }

    choose_swap_present_mode :: proc(modes: [dynamic]vk.PresentModeKHR) -> vk.PresentModeKHR {
        for mode in modes {
            if mode == .MAILBOX {
                return .MAILBOX
            }
        }
        return .FIFO
    }

    choose_swap_image_count :: proc(caps: vk.SurfaceCapabilitiesKHR) -> u32 {
        desired: u32 = caps.minImageCount + 1
        exceeded := caps.maxImageCount > 0 && desired > caps.maxImageCount
        return exceeded ? caps.maxImageCount : desired
    }

    usage_flags := choose_usage_flags(swapchain.device, rend.surface, surface_format.format)
    is_composite_alpha_opaque_supported := swapchain.device.surface_caps.supportedCompositeAlpha & { .OPAQUE } != {}

    info := vk.SwapchainCreateInfoKHR {
        sType = .SWAPCHAIN_CREATE_INFO_KHR,
        surface = rend.surface,
        minImageCount = choose_swap_image_count(swapchain.device.surface_caps),
        imageFormat = surface_format.format,
        imageColorSpace = surface_format.colorSpace,
        imageExtent = swapchain.extent,
        imageArrayLayers = 1,
        imageUsage = usage_flags,
        imageSharingMode = .EXCLUSIVE,
        queueFamilyIndexCount = 1,
        pQueueFamilyIndices = &swapchain.graphics_queue.family_index,
        preTransform = swapchain.device.surface_caps.currentTransform,
        compositeAlpha = is_composite_alpha_opaque_supported ? { .OPAQUE } : { .INHERIT },
        presentMode = choose_swap_present_mode(swapchain.device.present_modes),
        clipped = true,
    }
    vk.CreateSwapchainKHR(rend.device, &info, nil, &swapchain.swapchain)

    num_images: u32
    vk.GetSwapchainImagesKHR(rend.device, swapchain.swapchain, &num_images, nil)
    if num_images > 16 {
        num_images = 16
    }
    resize(&swapchain.images, num_images)
    vk.GetSwapchainImagesKHR(rend.device, swapchain.swapchain, &num_images, raw_data(swapchain.images))

    for i in 0..<num_images {
        swapchain.acquire_semaphores[i] = vk_create_semaphore(rend.device)

        image := Vk_Image {
            image = swapchain.images[i],
            usage_flags = usage_flags,
            extent = { width = swapchain.extent.width, height = swapchain.extent.height, depth = 1 },
            type = .D2,
            image_format = surface_format.format,
            is_swapchain_image = true,
            is_owning_vk_image = false,
            is_depth_format = vk_is_depth_format(surface_format.format),
            is_stencil_format = vk_is_stencil_format(surface_format.format),
            samples = { ._1 },
            num_layers = 1,
            num_levels = 1,
        }

        image.image_view = vk_image_create_image_view(
            &image,
            rend.device,
            .D2,
            surface_format.format,
            { .COLOR },
            0,
            vk.REMAINING_MIP_LEVELS,
            0,
            1,
            {},
            nil
        )

        swapchain.swapchain_textures[i] = vk_pool_create(&rend.texture_pool, image)
    }

    // Set timeline
    swapchain.timeline_semaphore = vk_create_timeline_semaphore(rend.device, u64(len(swapchain.images) - 1))

    rend.swapchain = swapchain
}

vk_swapchain_present :: proc(swapchain: ^Vk_Swapchain, wait_semaphore: ^vk.Semaphore) {
    info := vk.PresentInfoKHR {
        sType = .PRESENT_INFO_KHR,
        waitSemaphoreCount = 1,
        pWaitSemaphores = wait_semaphore,
        swapchainCount = 1,
        pSwapchains = &swapchain.swapchain,
        pImageIndices = &swapchain.current_image_index,
    }
    r := vk.QueuePresentKHR(swapchain.graphics_queue.queue, &info)
    fmt.println(r)

    swapchain.current_frame_index += 1
}

vk_swapchain_get_current_texture :: proc(swapchain: ^Vk_Swapchain) -> Vk_Texture {
    info := vk.SemaphoreWaitInfo {
        sType = .SEMAPHORE_WAIT_INFO,
        semaphoreCount = 1,
        pSemaphores = &swapchain.timeline_semaphore,
        pValues = &swapchain.wait_values[swapchain.current_image_index]
    }

    vk.WaitSemaphores(swapchain.renderer.device, &info, 0)

    acquire_semaphore := swapchain.acquire_semaphores[swapchain.current_image_index]
    r := vk.AcquireNextImageKHR(swapchain.renderer.device, swapchain.swapchain, max(u64), acquire_semaphore, 0, &swapchain.current_image_index)
    if r != .SUCCESS && r != .SUBOPTIMAL_KHR && r != .ERROR_OUT_OF_DATE_KHR {
        fmt.println(r)
        panic("Failed to get swapchain image!")
    }

    swapchain.renderer.wait_semaphore.semaphore = acquire_semaphore

    // Return the actual texture
    if cast(int)swapchain.current_image_index < len(swapchain.images) {
        return swapchain.swapchain_textures[swapchain.current_image_index]
    }

    return {}
}