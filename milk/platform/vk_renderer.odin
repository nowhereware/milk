package milk_platform

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import SDL "vendor:sdl3"
import vk "vendor:vulkan"
import "../../lib/vma"
import "../../lib/vkb"

Vk_Renderer :: struct {
    instance: ^vkb.Instance,
    surface: vk.SurfaceKHR,
    device: ^vkb.Device,
    graphics_device: ^Vk_Graphics_Device,
    selected_device: ^vkb.Physical_Device,
    device_extensions: [dynamic]cstring,
    features: Vk_Features,
    graphics_queue: Vk_Queue,
    compute_queue: Vk_Queue,
    swapchain: Vk_Swapchain,
    color_space: Vk_Color_Space,
    frame_count: u64,
    extent: vk.Extent2D,
    signal_semaphore: vk.SemaphoreSubmitInfo,
    last_submit_handle: Vk_Submit_Handle,
    last_submit_semaphore: vk.SemaphoreSubmitInfo,
    wait_semaphore: vk.SemaphoreSubmitInfo,
    framebuffer: Framebuffer,
    render_pass: Render_Pass,
    viewport: Vk_Viewport,
    scissor_rect: Vk_Scissor_Rect,
    depth_state: Vk_Depth_State,
    render_info: vk.RenderingInfo,
    // The command pool of the main thread, used for gfx begin.
    main_thread_pool: ^Command_Pool_Internal,
    texture_pool: Vk_Pool(Vk_Image),

    clear_color: Color,
}

// Required procedures

vk_renderer_new :: proc(window: ^SDL.Window, conf: ^Renderer_Config) -> (Renderer_Internal, [dynamic]Graphics_Device_Internal) {
    out: Vk_Renderer

    w, h: i32 = 0, 0
    SDL.GetWindowSize(window, &w, &h)
    out.frame_count = 3 // Currently triple-buffered

    // Create pools
    out.texture_pool = vk_pool_new(Vk_Image)

    // Create Instance
    inst_builder := vkb.init_instance_builder()
    vkb.instance_set_app_name(&inst_builder, strings.clone_from_cstring(conf.app_name))
    vkb.instance_set_app_version(&inst_builder, vk.MAKE_VERSION(conf.app_version.x, conf.app_version.y, conf.app_version.y))
    vkb.instance_set_engine_name(&inst_builder, "Milk Engine")
    vkb.instance_set_engine_version(&inst_builder, vk.MAKE_VERSION(0, 1, 0))
    vkb.instance_require_api_version(&inst_builder, vk.MAKE_VERSION(1, 3, 0))
    vkb.instance_use_default_debug_messenger(&inst_builder)

    inst_ok: bool
    out.instance, inst_ok = vkb.build_instance(&inst_builder)

    // Create Surface
    SDL.Vulkan_CreateSurface(window, out.instance.ptr, nil, &out.surface)

    // Create Device

    // Required features
    features_13 := vk.PhysicalDeviceVulkan13Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        dynamicRendering = true,
        synchronization2 = true,
    }

    features_12 := vk.PhysicalDeviceVulkan12Features {
        sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        bufferDeviceAddress = true,
        descriptorIndexing = true,
    }

    // Select a suitable device
    device_selector, sel_ok := vkb.init_physical_device_selector(out.instance)
    vkb.selector_set_required_features_13(&device_selector, features_13)
    vkb.selector_set_required_features_12(&device_selector, features_12)
    vkb.selector_set_minimum_version(&device_selector, vk.MAKE_VERSION(1, 3, 0))
    vkb.selector_set_surface(&device_selector, out.surface)
    vkb.selector_prefer_gpu_device_type(&device_selector, .Discrete)

    device_list, device_list_ok := vkb.enumerate_physical_devices(out.instance.ptr)
    graphics_devices := vk_convert_devices(&out, device_list)

    selected_physical_device, selected_ok := vkb.select_physical_device(&device_selector)
    out.selected_device = selected_physical_device
    device_builder, device_builder_ok := vkb.init_device_builder(selected_physical_device)

    // Build the device
    device_ok: bool
    out.device, device_ok = vkb.build_device(&device_builder)

    for &dev in graphics_devices {
        dev := &dev.(Vk_Graphics_Device)

        if dev.name == selected_physical_device.name {
            out.graphics_device = dev
        }
    }

    out.color_space = .SRGB_NONLINEAR
    vk_create_swapchain(&out, u32(w), u32(h))

    return out, graphics_devices
}

vk_renderer_begin :: proc(rend: ^Renderer_Internal) {
    rend := &rend.(Vk_Renderer)

    // Acquire a command buffer
    buffer := vk_command_pool_acquire(rend.main_thread_pool).(^Vk_Command_Buffer)

    render_pass := render_pass_new({ { load_op = .Clear, clear_color = rend.clear_color } })
    framebuffer := framebuffer_new({ { texture = vk_swapchain_get_current_texture(&rend.swapchain) } })

    num_fb_color_attachments := len(framebuffer.color)
    num_pass_color_attachments := len(render_pass.color)

    assert(num_fb_color_attachments == num_pass_color_attachments)

    rend.framebuffer = framebuffer

    for i in 0..<num_fb_color_attachments {
        if framebuffer.color[i].texture != nil {
            image := vk_pool_get(&rend.texture_pool, framebuffer.color[i].texture.(Vk_Texture))
            vk_image_transition_to_color_attachment(buffer, &image)
        }

        if framebuffer.color[i].resolve_texture != nil {
            image := vk_pool_get(&rend.texture_pool, framebuffer.color[i].resolve_texture.(Vk_Texture))
            vk_image_transition_to_color_attachment(buffer, &image)
        }
    }

    depth_texture := framebuffer.depth_stencil.texture

    if depth_texture != nil {
        depth_img := vk_pool_get(&rend.texture_pool, depth_texture.(Vk_Texture))
        assert(depth_img.image_format != .UNDEFINED)
        flags := vk_image_get_aspect_flags(&depth_img)

        vk_image_transition_layout(
            &depth_img, 
            buffer,
            .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            { .LATE_FRAGMENT_TESTS, .EARLY_FRAGMENT_TESTS },
            { .TOP_OF_PIPE, .EARLY_FRAGMENT_TESTS },
            vk.ImageSubresourceRange{ flags, 0, vk.REMAINING_MIP_LEVELS, 0, vk.REMAINING_ARRAY_LAYERS }
        )
    }

    samples := vk.SampleCountFlags { ._1 }
    mip_level: u8 = 0
    fb_width: u32 = 0
    fb_height: u32 = 0

    color_attachments: [MAX_COLOR_ATTACHMENTS]vk.RenderingAttachmentInfo

    for i in 0..<num_fb_color_attachments {
        attachment := framebuffer.color[i]
        assert(attachment.texture != nil)

        color_texture := vk_pool_get(&rend.texture_pool, attachment.texture.(Vk_Texture))
        desc_color := render_pass.color[i]
        if mip_level != 0 && desc_color.level != 0 {
            assert(mip_level == desc_color.level)
        }
        dim := color_texture.extent
        if fb_width != 0 {
            assert(dim.width == fb_width)
        }
        if fb_height != 0 {
            assert(dim.height == fb_height)
        }

        mip_level = desc_color.level
        fb_width = dim.width
        fb_height = dim.height
        samples = color_texture.samples
        color_attachments[i] = vk.RenderingAttachmentInfo {
            sType = .RENDERING_ATTACHMENT_INFO,
            pNext = nil,
            imageView = vk_image_get_or_create_framebuffer_view(&color_texture, rend, desc_color.level, desc_color.layer),
            imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
            resolveMode = card(samples) > 1 ? { .AVERAGE } : { },
            resolveImageView = 0,
            resolveImageLayout = .UNDEFINED,
            loadOp = vk_load_op_convert(desc_color.load_op),
            storeOp = vk_store_op_convert(desc_color.store_op)
        }
        color_attachments[i].clearValue.color.float32 = color_as_percent(desc_color.clear_color)

        // Handle MSAA
        if desc_color.store_op == .MSAA_Resolve {
            color_resolve_texture := vk_pool_get_ptr(&rend.texture_pool, attachment.resolve_texture.(Vk_Texture))
            color_attachments[i].resolveImageView = vk_image_get_or_create_framebuffer_view(color_resolve_texture, rend, desc_color.level, desc_color.layer)
            color_attachments[i].resolveImageLayout = .COLOR_ATTACHMENT_OPTIMAL
        }
    }

    depth_attachment: vk.RenderingAttachmentInfo

    if framebuffer.depth_stencil.texture != nil {
        depth_texture := vk_pool_get_ptr(&rend.texture_pool, framebuffer.depth_stencil.texture.(Vk_Texture))
        desc_depth := render_pass.depth
        assert(desc_depth.level == mip_level)

        depth_attachment = vk.RenderingAttachmentInfo {
            sType = .RENDERING_ATTACHMENT_INFO,
            pNext = nil,
            imageView = vk_image_get_or_create_framebuffer_view(depth_texture, rend, desc_depth.level, desc_depth.layer),
            imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            resolveMode = {},
            resolveImageView = 0,
            resolveImageLayout = .UNDEFINED,
            loadOp = vk_load_op_convert(desc_depth.load_op),
            storeOp = vk_store_op_convert(desc_depth.store_op),
            clearValue = { depthStencil = { depth = desc_depth.clear_depth, stencil = desc_depth.clear_stencil }}
        }

        if desc_depth.store_op == .MSAA_Resolve {
            assert(depth_texture.samples == samples)
            attachment := framebuffer.depth_stencil
            assert(attachment.resolve_texture != nil)
            depth_resolve_texture := vk_pool_get_ptr(&rend.texture_pool, attachment.resolve_texture.(Vk_Texture))
            depth_attachment.resolveImageView = vk_image_get_or_create_framebuffer_view(depth_resolve_texture, rend, desc_depth.level, desc_depth.layer)
            depth_attachment.resolveImageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
            depth_attachment.resolveMode = { .AVERAGE }
        }
        dim := depth_texture.extent
        if fb_width != 0 {
            assert(dim.width == fb_width)
        }
        if fb_height != 0 {
            assert(dim.height == fb_height)
        }
        mip_level = desc_depth.level
        fb_width = dim.width
        fb_height = dim.height
    }

    width := max(fb_width >> mip_level, 1)
    height := max(fb_height >> mip_level, 1)
    viewport := Vk_Viewport {
        position = { 0, 0 },
        size = { f32(width), f32(height) },
        depth = { 0, 1 }
    }
    scissor_rect := Vk_Scissor_Rect {
        position = { 0, 0 },
        size = { width, height }
    }

    stencil_attachment := depth_attachment
    is_stencil_format := render_pass.stencil.load_op != .Invalid

    rend.render_info = vk.RenderingInfo {
        sType = .RENDERING_INFO,
        pNext = nil,
        flags = {},
        renderArea = {
            vk.Offset2D { i32(scissor_rect.position.x ), i32(scissor_rect.position.y) },
            vk.Extent2D { scissor_rect.size.x, scissor_rect.size.y }
        },
        layerCount = 1,
        viewMask = 0,
        colorAttachmentCount = cast(u32)num_fb_color_attachments,
        pColorAttachments = raw_data(color_attachments[:]),
        pDepthAttachment = depth_texture != nil ? &depth_attachment : nil,
        pStencilAttachment = is_stencil_format ? &stencil_attachment : nil,
    }
}

vk_renderer_end :: proc(rend: ^Renderer_Internal, window: ^SDL.Window) {
    rend := &rend.(Vk_Renderer)

    num_fb_color_attachments := len(rend.framebuffer.color)

    for i in 0..<num_fb_color_attachments {
        attachment := rend.framebuffer.color[i]
        tex := vk_pool_get_ptr(&rend.texture_pool, attachment.texture.(Vk_Texture))

        tex.image_layout = .COLOR_ATTACHMENT_OPTIMAL
    }

    if rend.framebuffer.depth_stencil.texture != nil {
        tex := vk_pool_get_ptr(&rend.texture_pool, rend.framebuffer.depth_stencil.texture.(Vk_Texture))
        tex.image_layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
    }

    signal_value := rend.swapchain.current_frame_index + cast(u64)len(rend.swapchain.images)
    rend.swapchain.wait_values[rend.swapchain.current_image_index] = signal_value

    rend.signal_semaphore.semaphore = rend.swapchain.timeline_semaphore
    rend.signal_semaphore.value = signal_value

    vk_swapchain_present(&rend.swapchain, &rend.last_submit_semaphore.semaphore)
}

vk_renderer_quit :: proc(rend: ^Renderer_Internal) {
    rend := &rend.(Vk_Renderer)

    vk.DeviceWaitIdle(rend.device.ptr)

    vk_pool_destroy(&rend.texture_pool)

    vk.DestroySemaphore(rend.device.ptr, rend.swapchain.timeline_semaphore, nil)

    vkb.destroy_swapchain(rend.swapchain.swapchain)

    for view in rend.swapchain.image_views {
        vk.DestroyImageView(rend.device.ptr, view, nil)
    }

    vk.DestroyDevice(rend.device.ptr, nil)

    vk.DestroySurfaceKHR(rend.instance.ptr, rend.surface, nil)
    vk.DestroyInstance(rend.instance.ptr, nil)

    delete(rend.device_extensions)
    delete(rend.swapchain.images)
}

// TODO: Impl this, using rend.viewport as the size
vk_renderer_set_framebuffer_resized :: proc(rend: ^Renderer_Internal, size: UVector2) {
    rend := &rend.(Vk_Renderer)
}

vk_renderer_submit_pool :: proc(rend: ^Renderer_Internal, pool: ^Command_Pool_Internal) {
    rend := &rend.(Vk_Renderer)
    buffer := &pool.(Vk_Command_Pool)

    // TODO: Rewrite, using secondary command buffers.
    /*
    wait_semaphores := make([dynamic]vk.SemaphoreSubmitInfo)
    if rend.wait_semaphore.semaphore != 0 {
        append(&wait_semaphores, rend.wait_semaphore)
    }
    if rend.last_submit_semaphore.semaphore != 0 {
        append(&wait_semaphores, rend.last_submit_semaphore)
    }

    signal_semaphores := make([dynamic]vk.SemaphoreSubmitInfo)
    append(&signal_semaphores, vk.SemaphoreSubmitInfo {
        sType = .SEMAPHORE_CREATE_INFO,
        semaphore = buffer.semaphore,
        stageMask = { .ALL_COMMANDS }
    })

    if rend.signal_semaphore.semaphore != 0 {
        append(&signal_semaphores, rend.signal_semaphore)
    }

    info := vk.CommandBufferSubmitInfo {
        sType = .COMMAND_BUFFER_SUBMIT_INFO,
        commandBuffer = buffer.buffer
    }
    submit_info := vk.SubmitInfo2 {
        sType = .SUBMIT_INFO_2,
        waitSemaphoreInfoCount = cast(u32)len(wait_semaphores),
        pWaitSemaphoreInfos = raw_data(wait_semaphores),
        commandBufferInfoCount = 1,
        pCommandBufferInfos = &info,
        signalSemaphoreInfoCount = cast(u32)len(signal_semaphores),
        pSignalSemaphoreInfos = raw_data(signal_semaphores)
    }
    vk.QueueSubmit2(rend.graphics_queue.queue, 1, &submit_info, buffer.fence)
    rend.last_submit_semaphore.semaphore = buffer.semaphore
    rend.last_submit_handle = buffer.handle

    rend.wait_semaphore.semaphore = 0
    rend.signal_semaphore.semaphore = 0
    buffer.is_encoding = false
    */
}

vk_renderer_register_main_pool :: proc(rend: ^Renderer_Internal, pool: ^Command_Pool_Internal) {
    rend := &rend.(Vk_Renderer)

    rend.main_thread_pool = pool
}

vk_renderer_get_swapchain_texture :: proc(rend: ^Renderer_Internal) -> Texture_Internal {
    rend := &rend.(Vk_Renderer)

    return vk_swapchain_get_current_texture(&rend.swapchain)
}