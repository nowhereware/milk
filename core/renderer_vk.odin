package milk_core

import pt "platform"

import "base:runtime"
import "core:fmt"
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
    graphics_family: int,
    present_family: int,
    validation_layers: [dynamic]cstring,
    device_extensions: [dynamic]cstring,
    graphics_queue: vk.Queue,
    present_queue: vk.Queue,
    frame_data: [dynamic]pt.Vulkan_Frame_Data,
    swapchain: vk.SwapchainKHR,
    swapchain_format: vk.Format,
    present_mode: vk.PresentModeKHR,
    swapchain_extent: vk.Extent2D,
    image_index: int,
    swapchain_images: [dynamic]pt.Vulkan_Image,
    depth_image: pt.Vulkan_Image,
    frame_count: int,

    // VMA
    vk_functions: vma.VulkanFunctions,
    allocator: vma.Allocator,

    viewport: Viewport,
    clear_color: vk.ClearColorValue
}

// Required procedures

renderer_vulkan_new :: proc(window: ^SDL.Window, conf: ^Context_Config, viewport: Viewport) -> Renderer_Internal {
    out: Renderer_Vulkan

    w, h: i32 = 0, 0
    SDL.GetWindowSize(window, &w, &h)
    out.viewport.size = { cast(u32)w, cast(u32)h }
    out.frame_count = 2 // Currently just double-buffered

    app_info := vk.ApplicationInfo {
        sType = .APPLICATION_INFO,
        pApplicationName = conf.title,
        applicationVersion = vk.MAKE_VERSION(conf.version.x, conf.version.y, conf.version.z),
        pEngineName = "Milk Engine",
        engineVersion = vk.MAKE_VERSION(0, 1, 0),
        apiVersion = vk.MAKE_VERSION(1, 4, 0),
        pNext = nil,
    }
    
    out.frame_data = make([dynamic]pt.Vulkan_Frame_Data, pt.FRAME_COUNT)

    out.validation_layers, out.instance = pt.vulkan_create_instance(&app_info, window)
    pt.vulkan_create_surface(out.instance, &out.surface, window)
    out.graphics_devices = pt.vulkan_enumerate_physical_devices(out.instance, out.surface)
    out.device_extensions, out.graphics_family, out.present_family, out.physical_device, out.graphics_device = pt.vulkan_select_physical_device(out.graphics_devices, out.surface)
    out.device, out.graphics_queue, out.present_queue, out.vk_functions, out.allocator = pt.vulkan_create_logical_device_and_queues(
        out.device_extensions, 
        out.graphics_family, 
        out.present_family, 
        out.validation_layers, 
        out.physical_device, 
        out.instance
    )
    pt.vulkan_create_semaphores(out.device, out.frame_data)
    pt.vulkan_create_command_pool(out.graphics_family, out.device, out.frame_data)
    pt.vulkan_create_command_buffer(out.device, out.frame_data)
    fmt.println(out.frame_data)
    out.swapchain, out.swapchain_format, out.present_mode, out.swapchain_extent, out.swapchain_images = pt.vulkan_create_swapchain(
        out.graphics_device, 
        out.device, 
        out.viewport.size, 
        out.surface, 
        out.graphics_family, 
        out.present_family, 
        pt.FRAME_COUNT,
    )
    out.depth_image = pt.vulkan_create_render_targets(out.physical_device, out.device, out.swapchain_extent, out.allocator)

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
        imageView = rend.swapchain_images[rend.image_index].view,
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        loadOp = .CLEAR,
        storeOp = .STORE,
        clearValue = vk.ClearValue { color = rend.clear_color },
    }

    depth_attachment := vk.RenderingAttachmentInfo {
        sType = .RENDERING_ATTACHMENT_INFO,
        imageView = rend.depth_image.view,
        imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
        loadOp = .CLEAR,
        storeOp = .DONT_CARE,
        clearValue = { depthStencil = { depth = 1000, stencil = 0 } }
    }

    render_info := vk.RenderingInfo {
        sType = .RENDERING_INFO,
        renderArea = {
            offset = {0, 0},
            extent = rend.swapchain_extent
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

    for &image in rend.swapchain_images {
        vk.DestroyImageView(rend.device, image.view, nil)
        vk.DestroySampler(rend.device, image.sampler, nil)
    }

    vk.DestroyImageView(rend.device, rend.depth_image.view, nil)
    vk.DestroySampler(rend.device, rend.depth_image.sampler, nil)
    vma.DestroyImage(rend.allocator, rend.depth_image.image, rend.depth_image.allocation)

    delete(rend.swapchain_images)

    vk.DestroySwapchainKHR(rend.device, rend.swapchain, nil)

    for i in 0..<pt.FRAME_COUNT {
        vk.FreeCommandBuffers(rend.device, rend.frame_data[i].command_pool, 1, &rend.frame_data[i].command_buffer)
        vk.DestroyFence(rend.device, rend.frame_data[i].render_fence, nil)
        vk.DestroyCommandPool(rend.device, rend.frame_data[i].command_pool, nil)
        vk.DestroySemaphore(rend.device, rend.frame_data[i].acquire_semaphore, nil)
        vk.DestroySemaphore(rend.device, rend.frame_data[i].render_complete_semaphore, nil)
    }

    vma.DestroyAllocator(rend.allocator)

    vk.DestroyDevice(rend.device, nil)
    delete(rend.validation_layers)
    delete(rend.device_extensions)

    for &device in rend.graphics_devices {
        pt.graphics_device_destroy(&device)
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
}

@(private="file")
vkcheck :: proc(result: vk.Result, message: string = "", loc := #caller_location) {
    if result != .SUCCESS {
        fmt.println(result)
        panic(message, loc)
    }
}