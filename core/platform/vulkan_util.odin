package milk_gfx_platform

import "core:fmt"
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
        desired_ext := strings.clone_from_cstring(ext, context.temp_allocator)
        for &supported_ext in gpu.extension_properties {
            gpu_ext := strings.clone_from_bytes(supported_ext.extensionName[:], context.temp_allocator)
            if strings.contains(gpu_ext, desired_ext) {
                // Matches! Continue to the next extension
                continue outer
            }
        }
        // We've iterated through all of the supported extensions, and none of them match the desired extension.
        free_all(context.temp_allocator)
        return false
    }
    // We've iterated through all of the extensions without returning false, so we must be done

    free_all(context.temp_allocator)
    return true
}

vulkan_choose_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> (result: vk.SurfaceFormatKHR) {
    // If Vulkan returned an unknown format, force what we want
    if len(formats) == 1 && formats[0].format == .UNDEFINED {
        result.format = .B8G8R8A8_UNORM
        result.colorSpace = .SRGB_NONLINEAR
        return
    }

    // Favor 32-bit RGBA and SRGB Nonlinear colorspace
    for format in formats {
        if format.format == .B8G8R8A8_UNORM && format.colorSpace == .SRGB_NONLINEAR {
            return format
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

vulkan_create_sampler :: proc(device: vk.Device, type: Vulkan_Image_Type, filter: Vulkan_Filter_Type, repeat: Vulkan_Repeat_Type) -> (out: vk.Sampler) {
    sampler_create_info := vk.SamplerCreateInfo {
        sType = .SAMPLER_CREATE_INFO,
        maxAnisotropy = 1.0,
        anisotropyEnable = false,
        compareEnable = (type == .Depth),
        compareOp = (type == .Depth) ? .LESS_OR_EQUAL : .NEVER,
    }

    switch filter {
        case .Linear: {
            sampler_create_info.minFilter = .LINEAR
            sampler_create_info.magFilter = .LINEAR
            sampler_create_info.mipmapMode = .LINEAR
        }
        case .Nearest: {
            sampler_create_info.minFilter = .NEAREST
            sampler_create_info.magFilter = .NEAREST
            sampler_create_info.mipmapMode = .NEAREST
        }
    }

    switch repeat {
        case .Repeat: {
            sampler_create_info.addressModeU = .REPEAT
            sampler_create_info.addressModeV = .REPEAT
            sampler_create_info.addressModeW = .REPEAT
        }
        case .Clamp_To_Edge: {
            sampler_create_info.addressModeU = .CLAMP_TO_EDGE
            sampler_create_info.addressModeV = .CLAMP_TO_EDGE
            sampler_create_info.addressModeW = .CLAMP_TO_EDGE
        }
        case .Clamp_To_Border_Clear: {
            sampler_create_info.borderColor = .FLOAT_TRANSPARENT_BLACK
            sampler_create_info.addressModeU = .CLAMP_TO_BORDER
            sampler_create_info.addressModeV = .CLAMP_TO_BORDER
            sampler_create_info.addressModeW = .CLAMP_TO_BORDER
        }
        case .Clamp_To_Border_Black: {
            sampler_create_info.borderColor = .FLOAT_OPAQUE_BLACK
            sampler_create_info.addressModeU = .CLAMP_TO_BORDER
            sampler_create_info.addressModeV = .CLAMP_TO_BORDER
            sampler_create_info.addressModeW = .CLAMP_TO_BORDER
        }
    }

    vkcheck(vk.CreateSampler(device, &sampler_create_info, nil, &out))

    return
}

vulkan_alloc_image :: proc(device: vk.Device, allocator: vma.Allocator, image: ^Vulkan_Image, loc := #caller_location) {
    image.sampler = vulkan_create_sampler(device, image.type, image.filter, image.repeat)

    usage_flags := vk.ImageUsageFlags { .SAMPLED }
    if image.type == .Depth {
        usage_flags += { .DEPTH_STENCIL_ATTACHMENT }
    } else {
        usage_flags += { .TRANSFER_DST }
    }

    image_create_info := vk.ImageCreateInfo {
        sType = .IMAGE_CREATE_INFO,
        flags = {},
        imageType = .D2,
        format = image.format,
        extent = { width = image.extent.width, height = image.extent.height, depth = 1 },
        mipLevels = image.levels,
        arrayLayers = 1,
        samples = {._1},
        tiling = .OPTIMAL,
        usage = usage_flags,
        initialLayout = .UNDEFINED,
        sharingMode = .EXCLUSIVE,
    }

    alloc_info := vma.AllocationCreateInfo {
        usage = .GPU_ONLY
    }
    vkcheck(vma.CreateImage(allocator, &image_create_info, &alloc_info, &image.image, &image.allocation, nil), "Failed to create image", loc)

    view_create_info := vk.ImageViewCreateInfo {
        sType = .IMAGE_VIEW_CREATE_INFO,
        image = image.image,
        viewType = .D2,
        format = image.format,
        // components
        subresourceRange = {
            aspectMask = (image.type == .Depth) ? { .DEPTH, .STENCIL} : { .COLOR },
            levelCount = image.levels,
            layerCount = 1,
            baseMipLevel = 0,
        }
    }

    vkcheck(vk.CreateImageView(device, &view_create_info, nil, &image.view), "Failed to create depth image view!", loc)
}

vulkan_subimage_upload :: proc(image: ^Vulkan_Image, mip_level, x, y, z, width, height: uint, pic: rawptr, pixel_pitch: int) {
    assert(cast(u32)mip_level < image.levels)

    size := width * height * 8 / 8
}