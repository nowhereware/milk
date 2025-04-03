package milk_platform

import odin_queue "core:container/queue"
import "core:fmt"
import "core:mem"
import "core:strings"
import vk "vendor:vulkan"
import SDL "vendor:sdl3"
import "../../lib/vma"
import "../../lib/vkb"

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
    swapchain: ^vkb.Swapchain,
    renderer: ^Vk_Renderer,
    graphics_queue: ^Vk_Queue,
    extent: vk.Extent2D,
    image_format: vk.SurfaceFormatKHR,
    images: [dynamic]vk.Image,
    image_views: [dynamic]vk.ImageView,
    wait_values: [MAX_SWAPCHAIN_IMAGES]u64,
    current_frame_index: u64,
    current_image_index: u32,
    timeline_semaphore: vk.Semaphore,
    acquire_semaphores: [MAX_SWAPCHAIN_IMAGES]vk.Semaphore,
    swapchain_textures: [MAX_SWAPCHAIN_IMAGES]Vk_Texture,
}

vk_create_swapchain :: proc(rend: ^Vk_Renderer, width, height: u32) {
    swapchain_builder, builder_ok := vkb.init_swapchain_builder_handles(rend.selected_device, rend.device, rend.surface)

    out: Vk_Swapchain
    out.image_format.format = .B8G8R8A8_UNORM
    out.image_format.colorSpace = .SRGB_NONLINEAR

    vkb.swapchain_builder_set_desired_format(&swapchain_builder, out.image_format)
    vkb.swapchain_builder_set_present_mode(&swapchain_builder, .MAILBOX)
    vkb.swapchain_builder_set_desired_extent(&swapchain_builder, width, height)
    vkb.swapchain_builder_add_image_usage_flags(&swapchain_builder, { .TRANSFER_DST })
    vkb.swapchain_builder_set_desired_min_image_count(&swapchain_builder, rend.graphics_device.surface_caps.minImageCount + 1)
    vkb.swapchain_builder_set_composite_alpha_flags(&swapchain_builder, rend.graphics_device.surface_caps.supportedCompositeAlpha)

    swapchain_ok: bool
    out.swapchain, swapchain_ok = vkb.build_swapchain(&swapchain_builder)

    append_elems(&out.images, ..vkb.swapchain_get_images(out.swapchain))
    append_elems(&out.image_views, ..vkb.swapchain_get_image_views(out.swapchain))

    // Set timeline
    out.timeline_semaphore = vk_create_timeline_semaphore(rend.device.ptr, u64(len(out.images) - 1))

    rend.swapchain = out
}

vk_swapchain_present :: proc(swapchain: ^Vk_Swapchain, wait_semaphore: ^vk.Semaphore) {
    info := vk.PresentInfoKHR {
        sType = .PRESENT_INFO_KHR,
        waitSemaphoreCount = 1,
        pWaitSemaphores = wait_semaphore,
        swapchainCount = 1,
        pSwapchains = &swapchain.swapchain.ptr,
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

    vk.WaitSemaphores(swapchain.renderer.device.ptr, &info, 0)

    acquire_semaphore := swapchain.acquire_semaphores[swapchain.current_image_index]
    r := vk.AcquireNextImageKHR(swapchain.renderer.device.ptr, swapchain.swapchain.ptr, max(u64), acquire_semaphore, 0, &swapchain.current_image_index)
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