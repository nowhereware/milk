package milk

import pt "platform"

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import SDL "vendor:sdl3"
import vk "vendor:vulkan"
import "shared:vma"

Renderer_Vulkan :: struct {
    instance: vk.Instance,
    surface: vk.SurfaceKHR,
    device: vk.Device,
    physical_device: vk.PhysicalDevice,
    graphics_devices: [dynamic]pt.Vulkan_Graphics_Device,
    graphics_device: ^pt.Vulkan_Graphics_Device,
    validation_layers: [dynamic]cstring,
    device_extensions: [dynamic]cstring,
    graphics_queue: pt.Vulkan_Queue_Info,
    present_queue: pt.Vulkan_Queue_Info,
    frame_count: int,
    swapchain: pt.Vulkan_SwapChain,
    extent: vk.Extent2D,
    allocator: pt.Vulkan_Resource_Allocator,
    sampler_pool: pt.Vulkan_Sampler_Pool,
    transient_command_pool: vk.CommandPool,
    timeline_semaphore: vk.Semaphore,
    frame_data: [dynamic]pt.Vulkan_Frame_Data,
    g_buffer: pt.Vulkan_G_Buffer,
    descriptor_pool: vk.DescriptorPool,
    max_textures: u32,

    viewport: Viewport,
    clear_color: vk.ClearColorValue
}

// Required procedures

renderer_vulkan_new :: proc(window: ^SDL.Window, conf: ^Context_Config, viewport: Viewport) -> Renderer_Internal {
    out: Renderer_Vulkan

    w, h: i32 = 0, 0
    SDL.GetWindowSize(window, &w, &h)
    out.viewport.size = { cast(u32)w, cast(u32)h }
    out.frame_count = 3 // Currently just double-buffered

    app_info := vk.ApplicationInfo {
        sType = .APPLICATION_INFO,
        pApplicationName = conf.title,
        applicationVersion = vk.MAKE_VERSION(conf.version.x, conf.version.y, conf.version.z),
        pEngineName = "Milk Engine",
        engineVersion = vk.MAKE_VERSION(0, 1, 0),
        apiVersion = vk.MAKE_VERSION(1, 4, 0),
        pNext = nil,
    }

    out.validation_layers, out.instance = pt.vulkan_create_instance(&app_info, window)
    pt.vulkan_create_surface(out.instance, &out.surface, window)
    out.graphics_devices = pt.vulkan_enumerate_physical_devices(out.instance, out.surface)
    out.device_extensions, out.graphics_queue, out.present_queue, out.physical_device, out.graphics_device = pt.vulkan_select_physical_device(out.graphics_devices, out.surface)
    out.device = pt.vulkan_create_logical_device_and_queues(
        out.device_extensions,
        &out.graphics_queue,
        &out.present_queue,
        out.validation_layers,
        out.physical_device, 
        out.instance
    )
    allocator_info := vma.AllocatorCreateInfo {
        physicalDevice = out.physical_device,
        device = out.device,
        instance = out.instance,
        vulkanApiVersion = vk.MAKE_VERSION(1, 4, 0),
    }
    out.allocator = pt.vulkan_resource_allocator_new(allocator_info)
    out.sampler_pool = pt.vulkan_sampler_pool_new(out.device)
    out.transient_command_pool = pt.vulkan_create_transient_command_pool(&out.graphics_queue, out.device)
    out.swapchain = pt.vulkan_swapchain_create(out.graphics_device, out.device, &out.graphics_queue, &out.present_queue, out.transient_command_pool, out.surface)
    out.extent = pt.vulkan_swapchain_init_resources(&out.swapchain)
    out.timeline_semaphore = pt.vulkan_create_frame_submission(out.swapchain.max_frames_in_flight, out.device, &out.frame_data)
    out.max_textures, out.descriptor_pool = pt.vulkan_create_descriptor_pool(out.device, out.graphics_device)

    // Sampler for displaying G Buffer
    info := vk.SamplerCreateInfo {
        sType = .SAMPLER_CREATE_INFO,
        magFilter = .LINEAR,
        minFilter = .LINEAR,
    }
    linear_sampler := pt.vulkan_acquire_sampler(&out.sampler_pool, &info)

    // Create G Buffer
    {
        cmd := pt.vulkan_begin_single_time_commands(out.device, out.transient_command_pool)

        color_formats := make([dynamic]vk.Format)
        append(&color_formats, vk.Format.R8G8B8A8_UNORM)

        depth_format := pt.vulkan_find_depth_format(out.physical_device)
        g_buffer_init := pt.Vulkan_G_Buffer_Info {
            device = out.device,
            alloc = &out.allocator,
            size = out.extent,
            color_formats = color_formats,
            depth_format = depth_format,
            linear_sampler = linear_sampler,
            sample_count = { ._1 },
        }
        out.g_buffer = pt.vulkan_g_buffer_new(g_buffer_init, cmd)

        pt.vulkan_end_single_time_commands(&cmd, out.device, out.transient_command_pool, out.graphics_queue.queue)
    }
    fmt.println(out.g_buffer)

    return out
}

renderer_vulkan_begin :: proc(rend: ^Renderer_Internal, window: ^SDL.Window) {
    rend := &rend.(Renderer_Vulkan)

    /*
    vkcheck(vk.WaitForFences(rend.device, 1, &rend.command_buffer_fences[rend.image_index], true, max(u64)), "Failed to wait for fences!")
    vkcheck(vk.ResetFences(rend.device, 1, &rend.command_buffer_fences[rend.image_index]), "Failed to reset fences!")
    */

    color_attachment := vk.RenderingAttachmentInfo {
        sType = .RENDERING_ATTACHMENT_INFO,
        //imageView = rend.swapchain.next_images[rend.swapchain.current_frame].view,
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        loadOp = .CLEAR,
        storeOp = .STORE,
        clearValue = vk.ClearValue { color = rend.clear_color },
    }

    depth_attachment := vk.RenderingAttachmentInfo {
        sType = .RENDERING_ATTACHMENT_INFO,
        imageView = rend.g_buffer.depth_view,
        imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
        loadOp = .CLEAR,
        storeOp = .DONT_CARE,
        clearValue = { depthStencil = { depth = 1000, stencil = 0 } }
    }

    render_info := vk.RenderingInfo {
        sType = .RENDERING_INFO,
        renderArea = {
            offset = {0, 0},
            extent = rend.extent
        },
        layerCount = 1,
        colorAttachmentCount = 1,
        pColorAttachments = &color_attachment,
        pDepthAttachment = &depth_attachment,
    }
}

renderer_vulkan_bind_graphics_pipeline :: proc(rend: ^Renderer_Internal, pipeline: ^Pipeline_Internal) {
    
}

renderer_vulkan_end :: proc(rend: ^Renderer_Internal, window: ^SDL.Window) {
    rend := &rend.(Renderer_Vulkan)
}

renderer_vulkan_quit :: proc(rend: ^Renderer_Internal) {
    rend := &rend.(Renderer_Vulkan)

    vk.DeviceWaitIdle(rend.device)

    //vma.DestroyImage(rend.allocator, rend.depth_image.image, rend.depth_image.allocation)

    fmt.println("Yah?")
    pt.vulkan_g_buffer_destroy(&rend.g_buffer)
    fmt.println("Ohkey")
    pt.vulkan_swapchain_destroy(&rend.swapchain)

    vk.DestroySemaphore(rend.device, rend.timeline_semaphore, nil)
    vk.DestroyCommandPool(rend.device, rend.transient_command_pool, nil)

    for frame in rend.frame_data {
        for _, &val in frame.command_pool {
            vk.DestroyCommandPool(rend.device, val, nil)
        }
    }

    pt.vulkan_sampler_pool_destroy(&rend.sampler_pool)
    pt.vulkan_resource_allocator_destroy(&rend.allocator)

    vk.DestroyDevice(rend.device, nil)
    delete(rend.validation_layers)
    delete(rend.device_extensions)

    for &device in rend.graphics_devices {
        pt.vulkan_graphics_device_destroy(&device)
    }

    delete(rend.graphics_devices)
    vk.DestroySurfaceKHR(rend.instance, rend.surface, nil)
    vk.DestroyInstance(rend.instance, nil)

    delete(rend.frame_data)
}

renderer_vulkan_set_clear_color :: proc(rend: ^Renderer_Internal, color: Color) {
    rend := &rend.(Renderer_Vulkan)
    rend.viewport.clear_color = color
}

// TODO: Impl this, using rend.viewport as the size
renderer_vulkan_set_framebuffer_resized :: proc(rend: ^Renderer_Internal, size: UVector2) {
    rend := &rend.(Renderer_Vulkan)

    rend.swapchain.need_rebuild = true
}

@(private="file")
vkcheck :: proc(result: vk.Result, message: string = "", loc := #caller_location) {
    if result != .SUCCESS {
        fmt.println(result)
        panic(message, loc)
    }
}

vulkan_thread_command_pool :: proc(rend: ^Renderer_Vulkan) -> vk.CommandPool {
    if os.current_thread_id() not_in rend.frame_data[rend.swapchain.current_frame].command_pool {
        pool_info := vk.CommandPoolCreateInfo {
            sType = .COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = rend.swapchain.present_queue.family_index,
        }

        pool: vk.CommandPool
        vk.CreateCommandPool(rend.device, &pool_info, nil, &pool)
        rend.frame_data[rend.swapchain.current_frame].command_pool[os.current_thread_id()] = pool
    }

    return rend.frame_data[rend.swapchain.current_frame].command_pool[os.current_thread_id()]
}

vulkan_thread_command_buffer :: proc(rend: ^Renderer_Vulkan) -> vk.CommandBuffer {
    if os.current_thread_id() not_in rend.frame_data[rend.swapchain.current_frame].command_pool {
        vulkan_thread_command_pool(rend)
    }

    if os.current_thread_id() not_in rend.frame_data[rend.swapchain.current_frame].command_buffer {
        buffer_info := vk.CommandBufferAllocateInfo {
            sType = .COMMAND_BUFFER_ALLOCATE_INFO,
            commandPool = rend.frame_data[rend.swapchain.current_frame].command_pool[os.current_thread_id()],
            level = .PRIMARY,
            commandBufferCount = 1,
        }
        buffer: vk.CommandBuffer
        vkcheck(vk.AllocateCommandBuffers(rend.device, &buffer_info, &buffer))
        rend.frame_data[rend.swapchain.current_frame].command_buffer[os.current_thread_id()] = buffer
    }

    return rend.frame_data[rend.swapchain.current_frame].command_buffer[os.current_thread_id()]
}