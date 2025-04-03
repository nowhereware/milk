package milk_platform

import "core:fmt"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"
import "../../lib/vma"

vkcheck :: proc(result: vk.Result, message: string = "", loc := #caller_location) {
    if result != .SUCCESS {
        fmt.println(loc, result)
        if message != "" {
            fmt.println(message)
        }
    }
}

vk_find_queue_family_index :: proc(device: vk.PhysicalDevice, flags: vk.QueueFlags) -> int {
    queue_family_count: u32 = 0
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, nil)
    props := make([dynamic]vk.QueueFamilyProperties, queue_family_count)
    vk.GetPhysicalDeviceQueueFamilyProperties(device, &queue_family_count, raw_data(props))

    find_dedicated_index :: proc(props: [dynamic]vk.QueueFamilyProperties, require: vk.QueueFlags, avoid: vk.QueueFlags) -> int {
        for i in 0..<len(props) {
            is_suitable := (require & props[i].queueFlags == require)
            is_dedicated := (avoid & props[i].queueFlags == {})

            if props[i].queueCount != 0 && is_suitable && is_dedicated {
                delete(props)
                return i
            }
        }

        delete(props)
        
        return -1
    }

    if .COMPUTE in flags {
        q := find_dedicated_index(props, flags, { .GRAPHICS })
        if q != -1 {
            return q
        }
    }

    if .TRANSFER in flags {
        q := find_dedicated_index(props, flags, { .GRAPHICS })
        if q != -1 {
            return q
        }
    }

    return find_dedicated_index(props, flags, {})
}

vk_query_surface_capabilities :: proc(rend: ^Vk_Renderer, device: ^Vk_Graphics_Device) {
    depth_formats := [?]vk.Format {
        .D32_SFLOAT_S8_UINT,
        .D24_UNORM_S8_UINT,
        .D16_UNORM_S8_UINT,
        .D32_SFLOAT,
        .D16_UNORM,
    }

    for format in depth_formats {
        format_props: vk.FormatProperties
        vk.GetPhysicalDeviceFormatProperties(device.device, format, &format_props)
        if format_props.optimalTilingFeatures != {} {
            append(&device.depth_formats, format)
        }
    }
    if rend.surface == 0 {
        return
    }
    vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device.device, rend.surface, &device.surface_caps)
    format_count: u32
    vk.GetPhysicalDeviceSurfaceFormatsKHR(device.device, rend.surface, &format_count, nil)
    if format_count != 0 {
        resize(&device.surface_formats, format_count)
        vk.GetPhysicalDeviceSurfaceFormatsKHR(device.device, rend.surface, &format_count, raw_data(device.surface_formats))
    }

    present_mode_count: u32
    vk.GetPhysicalDeviceSurfacePresentModesKHR(device.device, rend.surface, &present_mode_count, nil)
    if present_mode_count != 0 {
        resize(&device.present_modes, present_mode_count)
        vk.GetPhysicalDeviceSurfacePresentModesKHR(device.device, rend.surface, &present_mode_count, raw_data(device.present_modes))
    }
}

vk_choose_swap_surface_format :: proc(formats: [dynamic]vk.SurfaceFormatKHR, color_space: Vk_Color_Space) -> vk.SurfaceFormatKHR {
    is_native_swapchain_bgr :: proc(formats: [dynamic]vk.SurfaceFormatKHR) -> bool {
        for fmt in formats {
            if fmt.format == .R8G8B8A8_UNORM || fmt.format == .R8G8B8A8_SRGB || fmt.format == .A2R10G10B10_UNORM_PACK32 {
                return false
            }
            if fmt.format == .B8G8R8A8_UNORM || fmt.format == .B8G8R8A8_SRGB || fmt.format == .A2B10G10R10_UNORM_PACK32 {
                return true
            }
        }
        return false
    }

    color_space_to_surface_format :: proc(color_space: Vk_Color_Space, is_bgr: bool) -> vk.SurfaceFormatKHR {
        switch color_space {
            case .SRGB_LINEAR: {
                return vk.SurfaceFormatKHR {
                    is_bgr ? .B8G8R8A8_UNORM : .R8G8B8A8_UNORM, .BT709_LINEAR_EXT
                }
            }
            case .SRGB_NONLINEAR: {
                fallthrough
            }
            case: {
                return vk.SurfaceFormatKHR {
                    is_bgr ? .B8G8R8A8_SRGB : .R8G8B8A8_SRGB, .SRGB_NONLINEAR
                }
            }
        }
    }

    preferred := color_space_to_surface_format(color_space, is_native_swapchain_bgr(formats))

    for fmt in formats {
        if fmt.format == preferred.format && fmt.colorSpace == preferred.colorSpace {
            return fmt
        }
    }

    for fmt in formats {
        if fmt.format == preferred.format {
            return fmt
        }
    }
    
    return formats[0]
}

vk_submit_handle :: proc(handle: u64) -> Vk_Submit_Handle {
    return {
        buffer_index = u32(handle & 0xffffffff),
        submit_id = u32(handle >> 32)
    }
}

vk_submit_handle_is_empty :: proc(handle: Vk_Submit_Handle) -> bool {
    return handle.submit_id == 0
}

vk_get_handle :: proc(handle: ^Vk_Submit_Handle) -> u64 {
    return u64(handle.submit_id) << 32 + cast(u64)handle.buffer_index
}

vk_create_semaphore :: proc(device: vk.Device) -> (out: vk.Semaphore) {
    info := vk.SemaphoreCreateInfo {
        sType = .SEMAPHORE_CREATE_INFO,
        flags = {},
    }
    vk.CreateSemaphore(device, &info, nil, &out)
    return
}

vk_create_timeline_semaphore :: proc(device: vk.Device, count: u64) -> vk.Semaphore {
    type_create_info := vk.SemaphoreTypeCreateInfo {
        sType = .SEMAPHORE_TYPE_CREATE_INFO,
        semaphoreType = .TIMELINE,
        initialValue = count,
    }
    info := vk.SemaphoreCreateInfo {
        sType = .SEMAPHORE_CREATE_INFO,
        pNext = &type_create_info,
        flags = {}
    }
    out: vk.Semaphore
    vk.CreateSemaphore(device, &info, nil, &out)
    return out
}

vk_create_fence :: proc(device: vk.Device) -> (out: vk.Fence) {
    info := vk.FenceCreateInfo {
        sType = .FENCE_CREATE_INFO,
        flags = {}
    }
    vk.CreateFence(device, &info, nil, &out)
    return
}

vk_get_available_device_extensions :: proc(physical_device: vk.PhysicalDevice) -> (exts: [dynamic]vk.ExtensionProperties) {
    count: u32
    vkcheck(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &count, nil))
    exts = make([dynamic]vk.ExtensionProperties, count)
    vkcheck(vk.EnumerateDeviceExtensionProperties(physical_device, nil, &count, raw_data(exts)))
    return
}

vk_get_available_instance_extensions :: proc() -> (exts: [dynamic]vk.ExtensionProperties) {
    count: u32
    vkcheck(vk.EnumerateInstanceExtensionProperties(nil, &count, nil))
    exts = make([dynamic]vk.ExtensionProperties, count)
    vkcheck(vk.EnumerateInstanceExtensionProperties(nil, &count, raw_data(exts)))
    return
}

vk_extension_is_available :: proc(name: cstring, extensions: [dynamic]vk.ExtensionProperties) -> bool {
    for &ext in extensions {
        name_str := strings.clone_from_cstring(name, context.temp_allocator)
        ext_name_str := strings.clone_from_bytes(ext.extensionName[:], context.temp_allocator)
        if strings.contains(ext_name_str, name_str) {
            return true
        }
    }

    return false
}

vk_request_extension :: proc(list: ^[dynamic]cstring, name: cstring, exts: [dynamic]vk.ExtensionProperties, panic_on_fail := false) {
    if vk_extension_is_available(name, exts) {
        append(list, name)
    } else {
        if panic_on_fail {
            panic(fmt.aprint("Failed to find extension:", name))
        } else {
            fmt.println("Failed to find extension:", name)
        }
    }
}

vk_get_available_layers :: proc() -> (layers: [dynamic]vk.LayerProperties) {
    count: u32
    vkcheck(vk.EnumerateInstanceLayerProperties(&count, nil))
    layers = make([dynamic]vk.LayerProperties, count)
    vkcheck(vk.EnumerateInstanceLayerProperties(&count, raw_data(layers)))
    return
}

vk_layer_is_available :: proc(name: cstring, layers: [dynamic]vk.LayerProperties) -> bool {
    for &layer in layers {
        name_str := strings.clone_from_cstring(name, context.temp_allocator)
        layer_str := strings.clone_from_bytes(layer.layerName[:], context.temp_allocator)
        if strings.contains(layer_str, name_str) {
            return true
        }
    }

    return false
}

vk_request_layer :: proc(list: ^[dynamic]cstring, name: cstring, layers: [dynamic]vk.LayerProperties, panic_on_fail := false) {
    if vk_layer_is_available(name, layers) {
        append(list, name)
    } else {
        if panic_on_fail {
            panic(fmt.aprint("Failed to find layer:", name))
        } else {
            fmt.println("Failed to find layer:", name)
        }
    }
}

vk_is_depth_format :: proc(format: vk.Format) -> bool {
    return format == .D16_UNORM || format == .X8_D24_UNORM_PACK32 || format == .D32_SFLOAT || format == .D16_UNORM_S8_UINT ||
        format == .D24_UNORM_S8_UINT || format == .D32_SFLOAT_S8_UINT
}

vk_is_stencil_format :: proc(format: vk.Format) -> bool {
    return format == .S8_UINT || format == .D16_UNORM_S8_UINT || format == .D24_UNORM_S8_UINT || format == .D32_SFLOAT_S8_UINT
}

vk_is_depth_or_stencil_format :: proc(format: vk.Format) -> bool {
    #partial switch format {
        case .D16_UNORM: fallthrough
        case .X8_D24_UNORM_PACK32: fallthrough
        case .D32_SFLOAT: fallthrough
        case .S8_UINT: fallthrough
        case .D16_UNORM_S8_UINT: fallthrough
        case .D24_UNORM_S8_UINT: fallthrough
        case .D32_SFLOAT_S8_UINT: {
            return true
        }
        case: {
            return false
        }
    }

    return false
}

vk_image_get_aspect_flags :: proc(image: ^Vk_Image) -> vk.ImageAspectFlags {
    flags := vk.ImageAspectFlags {}

    flags += image.is_depth_format ? { .DEPTH } : {}
    flags += image.is_stencil_format ? { .STENCIL } : {}
    flags += !(image.is_depth_format || image.is_depth_format) ? { .COLOR } : {}

    return flags
}

vk_image_is_sampled :: proc(image: Vk_Image) -> bool {
    return .SAMPLED in image.usage_flags
}

vk_image_is_storage :: proc(image: Vk_Image) -> bool {
    return .STORAGE in image.usage_flags
}

vk_image_is_color_attachment :: proc(image: Vk_Image) -> bool {
    return .COLOR_ATTACHMENT in image.usage_flags
}

vk_image_is_depth_attachment :: proc(image: Vk_Image) -> bool {
    return .DEPTH_STENCIL_ATTACHMENT in image.usage_flags
}

vk_image_is_attachment :: proc(image: Vk_Image) -> bool {
    return vk_image_is_color_attachment(image) && vk_image_is_depth_attachment(image)
}

vk_image_memory_barrier :: proc(
    buffer: ^Vk_Command_Buffer,
    image: vk.Image,
    src_access_mask: vk.AccessFlags,
    dst_access_mask: vk.AccessFlags,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    src_stage_mask: vk.PipelineStageFlags,
    dst_stage_mask: vk.PipelineStageFlags,
    sub_range: vk.ImageSubresourceRange,
) {
    barrier := vk.ImageMemoryBarrier {
        sType = .IMAGE_MEMORY_BARRIER,
        srcAccessMask = src_access_mask,
        dstAccessMask = dst_access_mask,
        oldLayout = old_layout,
        newLayout = new_layout,
        image = image,
        subresourceRange = sub_range,
    }

    vk.CmdPipelineBarrier(buffer.buffer, src_stage_mask, dst_stage_mask, {}, 0, nil, 0, nil, 1, &barrier)
}

vk_image_transition_layout :: proc(
    image: ^Vk_Image,
    buffer: ^Vk_Command_Buffer,
    new_layout: vk.ImageLayout,
    src_stage_mask: vk.PipelineStageFlags,
    dst_stage_mask: vk.PipelineStageFlags,
    sub_range: vk.ImageSubresourceRange,
) {
    src_access_mask := vk.AccessFlags {}
    dst_access_mask := vk.AccessFlags {}
    src_stage_mask := src_stage_mask

    if image.image_layout == .UNDEFINED {
        src_stage_mask = { .TOP_OF_PIPE }
    }

    do_not_require_access_mask := vk.PipelineStageFlags {
        .TOP_OF_PIPE, .BOTTOM_OF_PIPE, .ALL_GRAPHICS, .ALL_COMMANDS
    }
    src_remaining_mask := src_stage_mask - do_not_require_access_mask
    dst_remaining_mask := dst_stage_mask - do_not_require_access_mask

    if .LATE_FRAGMENT_TESTS in src_stage_mask {
        src_access_mask += { .DEPTH_STENCIL_ATTACHMENT_WRITE }
        src_remaining_mask = src_remaining_mask - { .LATE_FRAGMENT_TESTS }
    }

    if .COLOR_ATTACHMENT_OUTPUT in src_stage_mask {
        src_access_mask += { .COLOR_ATTACHMENT_WRITE }
        src_remaining_mask = src_remaining_mask - { .COLOR_ATTACHMENT_OUTPUT }
    }

    if .TRANSFER in src_stage_mask {
        src_access_mask += { .TRANSFER_WRITE }
        src_remaining_mask = src_remaining_mask - { .TRANSFER }
    }

    if .COMPUTE_SHADER in src_stage_mask {
        src_access_mask += { .SHADER_WRITE }
        src_remaining_mask = src_remaining_mask - { .COMPUTE_SHADER }
    }

    if .EARLY_FRAGMENT_TESTS in src_stage_mask {
        src_access_mask += { .DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE }
        src_remaining_mask = src_remaining_mask - { .EARLY_FRAGMENT_TESTS }
    }

    assert(src_access_mask == {})

    if .COMPUTE_SHADER in dst_stage_mask {
        dst_access_mask += { .SHADER_READ, .SHADER_WRITE }
        dst_remaining_mask = dst_remaining_mask - { .COMPUTE_SHADER }
    }

    if .LATE_FRAGMENT_TESTS in dst_stage_mask {
        dst_access_mask += { .DEPTH_STENCIL_ATTACHMENT_WRITE }
        dst_remaining_mask -= { .LATE_FRAGMENT_TESTS }
    }

    if .EARLY_FRAGMENT_TESTS in dst_stage_mask {
        dst_access_mask += { .DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE }
        dst_remaining_mask -= { .EARLY_FRAGMENT_TESTS }
    }

    if .FRAGMENT_SHADER in dst_stage_mask {
        dst_access_mask += { .SHADER_READ, .INPUT_ATTACHMENT_READ }
        dst_remaining_mask -= { .FRAGMENT_SHADER }
    }

    if .TRANSFER in dst_stage_mask {
        dst_access_mask += { .TRANSFER_READ }
        dst_remaining_mask -= { .TRANSFER }
    }

    if .RAY_TRACING_SHADER_KHR in dst_stage_mask {
        dst_access_mask += { .SHADER_READ, .SHADER_WRITE }
        dst_remaining_mask -= { .RAY_TRACING_SHADER_KHR }
    }

    assert(dst_remaining_mask == {})

    vk_image_memory_barrier(
        buffer, image.image, src_access_mask, dst_access_mask, image.image_layout, new_layout, src_stage_mask, dst_stage_mask, sub_range
    )

    image.image_layout = new_layout
}

vk_image_transition_to_color_attachment :: proc(buffer: ^Vk_Command_Buffer, image: ^Vk_Image) {
    vk_image_transition_layout(
        image, 
        buffer, 
        .COLOR_ATTACHMENT_OPTIMAL,
        { .COLOR_ATTACHMENT_OUTPUT },
        { .FRAGMENT_SHADER, .COMPUTE_SHADER },
        vk.ImageSubresourceRange {
            aspectMask = { .COLOR },
            baseMipLevel = 0,
            levelCount = vk.REMAINING_MIP_LEVELS,
            baseArrayLayer = 0,
            layerCount = vk.REMAINING_ARRAY_LAYERS,
        }
    )
}

vk_image_get_or_create_framebuffer_view :: proc(image: ^Vk_Image, rend: ^Vk_Renderer, level: u8, layer: u8) -> vk.ImageView {
    num_framebuffer_elems :: proc(views: [][MAX_SWAPCHAIN_IMAGES]vk.ImageView) -> u8 {
        count: u8 = 0
        for view_arr in views {
            for view in view_arr {
                if view != 0 {
                    count += 1
                }
            }
        }
        return count
    }

    if level >= MAX_MIP_LEVELS || layer >= num_framebuffer_elems(image.image_view_for_framebuffer[:]) {
        return 0
    }


    if image.image_view_for_framebuffer[level][layer] != 0 {
        return image.image_view_for_framebuffer[level][layer]
    }

    image.image_view_for_framebuffer[level][layer] = vk_image_create_image_view(
        image,
        rend.device.ptr,
        .D2,
        image.image_format,
        vk_image_get_aspect_flags(image),
        cast(u32)level,
        1,
        cast(u32)layer,
        1,
    )

    return image.image_view_for_framebuffer[level][layer]
}

vk_load_op_convert :: proc(load_op: Load_Op) -> vk.AttachmentLoadOp {
    switch load_op {
        case .Invalid: {
            return .DONT_CARE
        }
        case .Dont_Care: {
            return .DONT_CARE
        }
        case .Load: {
            return .LOAD
        }
        case .Clear: {
            return .CLEAR
        }
        case .None: {
            return .NONE
        }
    }
    
    return .DONT_CARE
}

vk_store_op_convert :: proc(store_op: Store_Op) -> vk.AttachmentStoreOp {
    switch store_op {
        case .Dont_Care: {
            return .DONT_CARE
        }
        case .Store: {
            return .STORE
        }
        case .MSAA_Resolve: {
            return .DONT_CARE
        }
        case .None: {
            return .NONE
        }
    }

    return .DONT_CARE
}

vk_compare_op_convert :: proc(op: Vk_Compare_Op) -> vk.CompareOp {
    switch op {
        case .Never: return .NEVER
        case .Less: return .LESS
        case .Equal: return .EQUAL
        case .Less_Equal: return .LESS_OR_EQUAL
        case .Greater: return .GREATER
        case .Not_Equal: return .NOT_EQUAL
        case .Greater_Equal: return .GREATER_OR_EQUAL
        case .Always_Pass: return .ALWAYS
    }

    return .ALWAYS
}