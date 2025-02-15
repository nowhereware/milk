package milk_gfx_platform

import "core:fmt"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"
import "shared:vma"

vkcheck :: proc(result: vk.Result, message: string = "", loc := #caller_location) {
    if result != .SUCCESS {
        fmt.println(loc, result)
        if message != "" {
            fmt.println(message)
        }
    }
}

vulkan_check_phys_device_ext_support :: proc(gpu: Vulkan_Graphics_Device, device_extensions: [dynamic]cstring) -> bool {
    // Iterate through extensions and match to GPU
    outer: for ext in device_extensions {
        if vulkan_extension_is_available(ext, gpu.extension_properties) {
            continue outer
        }
        // We've iterated through all of the supported extensions, and none of them match the desired extension.
        free_all(context.temp_allocator)
        return false
    }
    // We've iterated through all of the extensions without returning false, so we must be done
    free_all(context.temp_allocator)
    return true
}

vulkan_choose_surface_format :: proc(formats: []vk.SurfaceFormat2KHR) -> (result: vk.SurfaceFormat2KHR) {
    // If Vulkan returned an unknown format, force what we want
    if len(formats) == 1 && formats[0].surfaceFormat.format == .UNDEFINED {
        result.sType = .SURFACE_FORMAT_2_KHR
        result.surfaceFormat = {
            format = .B8G8R8A8_UNORM, colorSpace = .SRGB_NONLINEAR
        }
        return
    }

    // Favor 32-bit RGBA and SRGB Nonlinear colorspace
    preferred_formats := [?]vk.SurfaceFormat2KHR {
        {
            sType = .SURFACE_FORMAT_2_KHR,
            surfaceFormat = {
                format = .B8G8R8A8_UNORM,
                colorSpace = .SRGB_NONLINEAR,
            }
        },
        {
            sType = .SURFACE_FORMAT_2_KHR,
            surfaceFormat = {
                format = .R8G8B8A8_UNORM,
                colorSpace = .SRGB_NONLINEAR,
            }
        }
    }

    for preferred in preferred_formats {
        for format in formats {
            if format.surfaceFormat.format == preferred.surfaceFormat.format && format.surfaceFormat.colorSpace == preferred.surfaceFormat.colorSpace {
                return format
            }
        }
    }

    return formats[0]
}

vulkan_choose_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
    DESIRED_MODE :: vk.PresentModeKHR.MAILBOX

    // Favor mailbox
    for i := 0; i < len(modes); i += 1 {
        if modes[i] == DESIRED_MODE {
            return DESIRED_MODE
        }
    }

    // Couldn't find mailbox, use FIFO
    return .FIFO
}

vulkan_choose_surface_extent :: proc(size: [2]u32, caps: ^vk.SurfaceCapabilitiesKHR) -> (extent: vk.Extent2D) {
    // Extent is typically size of window we created surface from, if it isn't we substitute the window size
    if caps.currentExtent.width == max(u32) {
        extent.width = size.x
        extent.height = size.y
    } else {
        extent = caps.currentExtent
    }

    return
}

vulkan_choose_supported_format :: proc(physical_device: vk.PhysicalDevice, formats: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format {
    for format in formats {
        props: vk.FormatProperties
        vk.GetPhysicalDeviceFormatProperties(physical_device, format, &props)

        if tiling == .LINEAR && props.linearTilingFeatures >= features {
            return format
        } else if tiling == .OPTIMAL && props.optimalTilingFeatures >= features {
            return format
        }
    }

    return .UNDEFINED
}

vulkan_get_pipeline_stage_access :: proc(state: vk.ImageLayout) -> (vk.PipelineStageFlags2, vk.AccessFlags2) {
    #partial switch state {
        case .UNDEFINED: {
            return { .TOP_OF_PIPE }, { }
        }
        case .COLOR_ATTACHMENT_OPTIMAL: {
            return { .COLOR_ATTACHMENT_OUTPUT }, { .COLOR_ATTACHMENT_READ, .COLOR_ATTACHMENT_WRITE }
        }
        case .SHADER_READ_ONLY_OPTIMAL: {
            return { .FRAGMENT_SHADER, .COMPUTE_SHADER, .PRE_RASTERIZATION_SHADERS }, { .SHADER_READ }
        }
        case .TRANSFER_DST_OPTIMAL: {
            return { .TRANSFER }, { .TRANSFER_WRITE }
        }
        case .GENERAL: {
            return { .COMPUTE_SHADER, .TRANSFER }, { .MEMORY_READ, .MEMORY_WRITE, .TRANSFER_WRITE }
        }
        case .PRESENT_SRC_KHR: {
            return { .COLOR_ATTACHMENT_OUTPUT }, { }
        }
        case: {
            panic("Unsupported layout transition!")
        }
    }
}

vulkan_create_image_memory_barrier :: proc(
    image: vk.Image, 
    old_layout: vk.ImageLayout, 
    new_layout: vk.ImageLayout, 
    subresource_range: vk.ImageSubresourceRange = { { .COLOR }, 0, 1, 0, 1 }
) -> (barrier: vk.ImageMemoryBarrier2) {
    src_stage, src_access := vulkan_get_pipeline_stage_access(old_layout)
    dst_stage, dst_access := vulkan_get_pipeline_stage_access(new_layout)

    barrier = vk.ImageMemoryBarrier2 {
        sType = .IMAGE_MEMORY_BARRIER_2,
        srcStageMask = src_stage,
        srcAccessMask = src_access,
        dstStageMask = dst_stage,
        dstAccessMask = dst_access,
        oldLayout = old_layout,
        newLayout = new_layout,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = image,
        subresourceRange = subresource_range
    }

    return
}

vulkan_transition_image_layout :: proc(
    cmd: vk.CommandBuffer,
    image: vk.Image,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    aspect_mask: vk.ImageAspectFlags = { .COLOR }
) {
    barrier := vulkan_create_image_memory_barrier(image, old_layout, new_layout, { aspect_mask, 0, 1, 0, 1 })
    dep_info := vk.DependencyInfo {
        sType = .DEPENDENCY_INFO,
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = &barrier
    }

    vk.CmdPipelineBarrier2(cmd, &dep_info)
}

vulkan_infer_access_mask_from_stage :: proc(stage: vk.PipelineStageFlags2, src: bool) -> (access: vk.AccessFlags2) {
    if .COMPUTE_SHADER in stage {
        access += src ? { .SHADER_READ } : { .SHADER_WRITE }
    }
    if .FRAGMENT_SHADER in stage {
        access += src ? { .SHADER_READ } : { .SHADER_WRITE }
    }
    if .VERTEX_ATTRIBUTE_INPUT in stage {
        access += { .VERTEX_ATTRIBUTE_READ }
    }
    if .TRANSFER in stage {
        access += src ? { .TRANSFER_READ } : { .TRANSFER_WRITE }
    }

    if access == {} {
        panic("Missing stage implementation!")
    }
    return
}

vulkan_buffer_memory_barrier :: proc(
    cmd: vk.CommandBuffer,
    buffer: vk.Buffer,
    src_stage_mask: vk.PipelineStageFlags2,
    dst_stage_mask: vk.PipelineStageFlags2,
    src_access_mask: vk.AccessFlags2 = {},
    dst_access_mask: vk.AccessFlags2 = {},
    offset: vk.DeviceSize = 0,
    size: vk.DeviceSize = cast(vk.DeviceSize)vk.WHOLE_SIZE,
    src_queue_family_index: u32 = vk.QUEUE_FAMILY_IGNORED,
    dst_queue_family_index: u32 = vk.QUEUE_FAMILY_IGNORED,
) {
    src_access_mask := src_access_mask
    if src_access_mask == {} {
        src_access_mask = vulkan_infer_access_mask_from_stage(src_stage_mask, true)
    }
    dst_access_mask := dst_access_mask
    if dst_access_mask == {} {
        dst_access_mask = vulkan_infer_access_mask_from_stage(dst_stage_mask, true)
    }

    buffer_barrier := make([dynamic]vk.BufferMemoryBarrier2)
    append(&buffer_barrier, vk.BufferMemoryBarrier2 {
        sType = .BUFFER_MEMORY_BARRIER_2,
        srcStageMask = src_stage_mask,
        srcAccessMask = src_access_mask,
        dstStageMask = dst_stage_mask,
        dstAccessMask = dst_access_mask,
        srcQueueFamilyIndex = src_queue_family_index,
        dstQueueFamilyIndex = dst_queue_family_index,
        buffer = buffer,
        offset = offset,
        size = size,
    })

    dep_info := vk.DependencyInfo {
        sType = .DEPENDENCY_INFO,
        bufferMemoryBarrierCount = cast(u32)len(buffer_barrier),
        pBufferMemoryBarriers = raw_data(buffer_barrier)
    }
    vk.CmdPipelineBarrier2(cmd, &dep_info)
}

vulkan_find_supported_format :: proc(
    physical_device: vk.PhysicalDevice,
    candidates: ^[dynamic]vk.Format,
    tiling: vk.ImageTiling,
    features: vk.FormatFeatureFlags,
) -> vk.Format {
    for format in candidates {
        props := vk.FormatProperties2 {
            sType = .FORMAT_PROPERTIES_2
        }
        vk.GetPhysicalDeviceFormatProperties2(physical_device, format, &props)

        if tiling == .LINEAR && features <= props.formatProperties.linearTilingFeatures {
            return format
        } else if tiling == .OPTIMAL && features <= props.formatProperties.optimalTilingFeatures {
            return format
        }
    }

    panic("Failed to find supported format!")
}

vulkan_find_depth_format :: proc(physical_device: vk.PhysicalDevice) -> vk.Format {
    candidates := make([dynamic]vk.Format)
    append_elems(&candidates, 
        vk.Format.D16_UNORM, 
        vk.Format.D32_SFLOAT, 
        vk.Format.D32_SFLOAT_S8_UINT, 
        vk.Format.D24_UNORM_S8_UINT
    )

    return vulkan_find_supported_format(
        physical_device,
        &candidates,
        .OPTIMAL,
        { .DEPTH_STENCIL_ATTACHMENT }
    )
}

vulkan_begin_single_time_commands :: proc(device: vk.Device, pool: vk.CommandPool) -> (cmd: vk.CommandBuffer) {
    alloc_info := vk.CommandBufferAllocateInfo {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = pool,
        level = .PRIMARY,
        commandBufferCount = 1
    }
    vkcheck(vk.AllocateCommandBuffers(device, &alloc_info, &cmd))
    begin_info := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT }
    }
    vkcheck(vk.BeginCommandBuffer(cmd, &begin_info))
    return
}

vulkan_end_single_time_commands :: proc(cmd: ^vk.CommandBuffer, device: vk.Device, cmd_pool: vk.CommandPool, queue: vk.Queue) {
    // Submit and clean up
    vkcheck(vk.EndCommandBuffer(cmd^))

    fmt.println("Ended buffer")

    // Create fence for sync
    fence_info := vk.FenceCreateInfo { sType = .FENCE_CREATE_INFO }
    fence: vk.Fence
    vkcheck(vk.CreateFence(device, &fence_info, nil, &fence))

    fmt.println("Created fence")

    cmd_buffer_info := vk.CommandBufferSubmitInfo { sType = .COMMAND_BUFFER_SUBMIT_INFO, commandBuffer = cmd^ }
    submit_info := vk.SubmitInfo2 {
        sType = .SUBMIT_INFO_2,
        commandBufferInfoCount = 1,
        pCommandBufferInfos = &cmd_buffer_info
    }
    vkcheck(vk.QueueSubmit2(queue, 1, &submit_info, fence))
    fmt.println("Queue submitted.")
    vkcheck(vk.WaitForFences(device, 1, &fence, true, max(u64)))

    fmt.println("Waited.")

    vk.DestroyFence(device, fence, nil)
    vk.FreeCommandBuffers(device, cmd_pool, 1, cmd)
}

vulkan_get_available_device_extensions :: proc(physical_device: vk.PhysicalDevice) -> (exts: [dynamic]vk.ExtensionProperties) {
    count: u32
    vkcheck(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &count, nil))
    exts = make([dynamic]vk.ExtensionProperties, count)
    vkcheck(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &count, raw_data(exts)))
    return
}

vulkan_get_available_instance_extensions :: proc() -> (exts: [dynamic]vk.ExtensionProperties) {
    count: u32
    vkcheck(vk.EnumerateInstanceExtensionProperties(nil, &count, nil))
    exts = make([dynamic]vk.ExtensionProperties, count)
    vkcheck(vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(exts)))
    return
}

vulkan_extension_is_available :: proc(name: cstring, extensions: [dynamic]vk.ExtensionProperties) -> bool {
    for &ext in extensions {
        name_str := strings.clone_from_cstring(name, context.temp_allocator)
        ext_name_str := strings.clone_from_bytes(ext.extensionName[:], context.temp_allocator)
        if strings.contains(ext_name_str, name_str) {
            return true
        }
    }

    return false
}

vulkan_request_extension :: proc(list: ^[dynamic]cstring, name: cstring, exts: [dynamic]vk.ExtensionProperties, panic_on_fail := false) {
    if vulkan_extension_is_available(name, exts) {
        append(list, name)
    } else {
        if panic_on_fail {
            panic(fmt.aprint("Failed to find extension:", name))
        } else {
            fmt.println("Failed to find extension:", name)
        }
    }
}

vulkan_get_available_layers :: proc() -> (layers: [dynamic]vk.LayerProperties) {
    count: u32
    vkcheck(vk.EnumerateInstanceLayerProperties(&count, nil))
    layers = make([dynamic]vk.LayerProperties, count)
    vkcheck(vk.EnumerateInstanceLayerProperties(&count, raw_data(layers)))
    return
}

vulkan_layer_is_available :: proc(name: cstring, layers: [dynamic]vk.LayerProperties) -> bool {
    for &layer in layers {
        name_str := strings.clone_from_cstring(name, context.temp_allocator)
        layer_str := strings.clone_from_bytes(layer.layerName[:], context.temp_allocator)
        if strings.contains(layer_str, name_str) {
            return true
        }
    }

    return false
}

vulkan_request_layer :: proc(list: ^[dynamic]cstring, name: cstring, layers: [dynamic]vk.LayerProperties, panic_on_fail := false) {
    if vulkan_layer_is_available(name, layers) {
        append(list, name)
    } else {
        if panic_on_fail {
            panic(fmt.aprint("Failed to find layer:", name))
        } else {
            fmt.println("Failed to find layer:", name)
        }
    }
}

vulkan_create_sampler_hash :: proc(info: vk.SamplerCreateInfo) -> string {
    return fmt.aprint(
        info.magFilter,
        info.minFilter,
        info.mipmapMode,
        info.addressModeU,
        info.addressModeV,
        info.addressModeW,
        info.mipLodBias,
        info.anisotropyEnable,
        info.maxAnisotropy,
        info.compareEnable,
        info.compareOp,
        info.minLod,
        info.maxLod,
        info.borderColor,
        info.unnormalizedCoordinates,
    )
}

vulkan_create_sampler :: proc(device: vk.Device, info: ^vk.SamplerCreateInfo) -> (out: vk.Sampler) {
    vkcheck(vk.CreateSampler(device, info, nil, &out))
    return out
}