package milk_platform

import odin_queue "core:container/queue"
import "core:fmt"
import vk "vendor:vulkan"

Vk_Command_Buffer :: struct {
    rend: ^Vk_Renderer,
    buffer: vk.CommandBuffer,
    buffer_allocated: vk.CommandBuffer,
    handle: Vk_Submit_Handle,
    fence: vk.Fence,
    semaphore: vk.Semaphore,
    is_encoding: bool,
    framebuffer: Framebuffer,
}

MAX_COMMAND_BUFFERS :: 64

Vk_Command_Pool :: struct {
    rend: ^Vk_Renderer,
    device: vk.Device,
    queue: vk.Queue,
    command_pool: vk.CommandPool,
    queue_family_index: u32,
    debug_name: Maybe(string),
    buffers: [MAX_COMMAND_BUFFERS]Vk_Command_Buffer,
    last_submit_semaphore: vk.SemaphoreSubmitInfo,
    wait_semaphore: vk.SemaphoreSubmitInfo,
    signal_semaphore: vk.SemaphoreSubmitInfo,
    available_buffer_queue: odin_queue.Queue(int),
    submit_counter: u32,
    last_submit_handle: Vk_Submit_Handle,
    next_submit_handle: Vk_Submit_Handle,
}

Vk_Submit_Handle :: struct {
    buffer_index: u32,
    submit_id: u32,
}

vk_command_pool_new :: proc(rend: ^Renderer_Internal) -> Command_Pool_Internal {
    rend := &rend.(Vk_Renderer)
    out: Vk_Command_Pool

    out.rend = rend
    out.device = rend.device
    out.queue_family_index = rend.graphics_queue.family_index

    out.last_submit_semaphore = {
        sType = .SEMAPHORE_SUBMIT_INFO,
        stageMask = { .ALL_COMMANDS }
    }
    out.wait_semaphore = {
        sType = .SEMAPHORE_SUBMIT_INFO,
        stageMask = { .ALL_COMMANDS }
    }
    out.signal_semaphore = {
        sType = .SEMAPHORE_SUBMIT_INFO,
        stageMask = { .ALL_COMMANDS }
    }
    odin_queue.init(&out.available_buffer_queue, MAX_COMMAND_BUFFERS)
    out.queue = rend.graphics_queue.queue

    info := vk.CommandPoolCreateInfo {
        sType = .COMMAND_POOL_CREATE_INFO,
        flags = { .RESET_COMMAND_BUFFER, .TRANSIENT },
        queueFamilyIndex = out.queue_family_index,
    }
    vk.CreateCommandPool(rend.device, &info, nil, &out.command_pool)

    alloc_info := vk.CommandBufferAllocateInfo {
        sType = .COMMAND_BUFFER_ALLOCATE_INFO,
        commandPool = out.command_pool,
        level = .PRIMARY,
        commandBufferCount = 1,
    }

    for i in 0..<MAX_COMMAND_BUFFERS {
        wrapper := &out.buffers[i]
        wrapper.semaphore = vk_create_semaphore(rend.device)
        wrapper.fence = vk_create_fence(rend.device)
        vk.AllocateCommandBuffers(rend.device, &alloc_info, &wrapper.buffer_allocated)
        wrapper.handle.buffer_index = cast(u32)i
        odin_queue.push(&out.available_buffer_queue, i)
        wrapper.rend = out.rend
    }

    return out
}

vk_command_pool_acquire :: proc(commands: ^Command_Pool_Internal) -> Command_Buffer_Internal {
    commands := &commands.(Vk_Command_Pool)

    for odin_queue.len(commands.available_buffer_queue) == 0 {
        fmt.println("Waiting for command buffers...")
        vk_command_pool_purge(commands)
    }

    index := odin_queue.pop_back(&commands.available_buffer_queue)
    current := &commands.buffers[index]

    current.handle.submit_id = cast(u32)index

    current.buffer = current.buffer_allocated
    current.is_encoding = true
    info := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = { .ONE_TIME_SUBMIT }
    }
    vkcheck(vk.BeginCommandBuffer(current.buffer, &info))

    commands.next_submit_handle = current.handle

    return current
}

vk_command_pool_destroy :: proc(commands: ^Command_Pool_Internal) {
    commands := &commands.(Vk_Command_Pool)

    vk_command_pool_wait_all(commands)
    for buf in commands.buffers {
        vk.DestroyFence(commands.device, buf.fence, nil)
        vk.DestroySemaphore(commands.device, buf.semaphore, nil)
    }

    vk.DestroyCommandPool(commands.device, commands.command_pool, nil)
}

vk_command_buffer_end :: proc(buffer: Command_Buffer_Internal) {
    buffer := buffer.(^Vk_Command_Buffer)

    vk.EndCommandBuffer(buffer.buffer)
}

vk_command_buffer_begin_draw :: proc(
    rend: ^Renderer_Internal,
    buffer: Command_Buffer_Internal,
) {
    rend := &rend.(Vk_Renderer)
    buffer := buffer.(^Vk_Command_Buffer)

    vk_command_buffer_bind_viewport(buffer, &rend.viewport)
    vk_command_buffer_bind_scissor_rect(buffer, &rend.scissor_rect)
    vk_command_buffer_bind_depth_state(buffer)

    vk.CmdSetDepthCompareOp(buffer.buffer, .ALWAYS)
    vk.CmdSetDepthBiasEnable(buffer.buffer, false)

    vk.CmdBeginRendering(buffer.buffer, &rend.render_info)
}

vk_command_buffer_end_draw :: proc(buffer: Command_Buffer_Internal) {
    buffer := buffer.(^Vk_Command_Buffer)
    vk.CmdEndRendering(buffer.buffer)
}

vk_command_buffer_bind_viewport :: proc(buffer: ^Vk_Command_Buffer, viewport: ^Vk_Viewport) {
    vp := vk.Viewport {
        x = viewport.position.x,
        y = viewport.position.y,
        width = viewport.size.x,
        height = viewport.size.y,
        minDepth = viewport.depth.x,
        maxDepth = viewport.depth.y,
    }
    vk.CmdSetViewport(buffer.buffer, 0, 1, &vp)
}

vk_command_buffer_bind_scissor_rect :: proc(buffer: ^Vk_Command_Buffer, rect: ^Vk_Scissor_Rect) {
    scissor := vk.Rect2D {
        offset = {
            x = i32(rect.position.x), y = i32(rect.position.y),
        },
        extent = {
            width = rect.size.x, height = rect.size.y
        }
    }
    vk.CmdSetScissor(buffer.buffer, 0, 1, &scissor)
}

vk_command_buffer_bind_depth_state :: proc(buffer: ^Vk_Command_Buffer, state: Vk_Depth_State = { .Always_Pass, false }) {
    op := vk_compare_op_convert(state.compare_op)
    vk.CmdSetDepthWriteEnable(buffer.buffer, cast(b32)state.is_depth_write_enabled)
    vk.CmdSetDepthTestEnable(buffer.buffer, cast(b32)(op != .ALWAYS || state.is_depth_write_enabled))

    vk.CmdSetDepthCompareOp(buffer.buffer, op)
}



// Internal procedures



vk_command_pool_purge :: proc(commands: ^Vk_Command_Pool) {
    enumerate_buffers :: proc(arr: []Vk_Command_Buffer) -> u32 {
        count: u32
        for buf in arr {
            if buf.buffer != nil {
                count += 1
            }
        }
        return count
    }
    num_buffers := enumerate_buffers(commands.buffers[:])

    for i in 0..<num_buffers {
        buf := commands.buffers[(i + commands.last_submit_handle.buffer_index + 1) % num_buffers]

        if buf.buffer == nil || buf.is_encoding {
            continue
        }

        result := vk.WaitForFences(commands.device, 1, &buf.fence, true, 0)

        if result == .SUCCESS {
            vkcheck(vk.ResetCommandBuffer(buf.buffer, {}))
            vkcheck(vk.ResetFences(commands.device, 1, &buf.fence))
            buf.buffer = nil
            odin_queue.push(&commands.available_buffer_queue, cast(int)i)
        } else {
            if result != .TIMEOUT {
                vkcheck(result)
            }
        }
    }
}

vk_command_pool_wait_all :: proc(commands: ^Vk_Command_Pool) {
    fences: [MAX_COMMAND_BUFFERS]vk.Fence

    num_fences: u32 = 0

    for buf in commands.buffers {
        if buf.buffer != nil && !buf.is_encoding {
            fences[num_fences] = buf.fence
            num_fences += 1
        }
    }

    if num_fences != 0 {
        vkcheck(vk.WaitForFences(commands.device, num_fences, raw_data(fences[:]), true, max(u64)))
    }

    vk_command_pool_purge(commands)
}

vk_command_pool_is_ready :: proc(commands: ^Vk_Command_Pool, handle: Vk_Submit_Handle) -> bool {
    if vk_submit_handle_is_empty(handle) {
        return true
    }

    buf := &commands.buffers[handle.buffer_index]
    if buf.buffer == nil {
        return true
    }

    if buf.handle.submit_id != handle.submit_id {
        return true
    }

    return vk.WaitForFences(commands.device, 1, &buf.fence, true, 0) == .SUCCESS
}

vk_command_pool_wait :: proc(commands: ^Vk_Command_Pool, handle: Vk_Submit_Handle) {
    if vk_submit_handle_is_empty(handle) {
        vk.DeviceWaitIdle(commands.device)
        return
    }

    if vk_command_pool_is_ready(commands, handle) {
        return
    }

    if !commands.buffers[handle.buffer_index].is_encoding {
        return
    }

    vkcheck(vk.WaitForFences(commands.device, 1, &commands.buffers[handle.buffer_index].fence, true, max(u64)))
    vk_command_pool_purge(commands)
}

vk_command_buffer_transition_to_shader_readonly :: proc(buffer: ^Vk_Command_Buffer, texture: Vk_Texture) {
    img := vk_pool_get(&buffer.rend.texture_pool, texture)

    if img.samples == { ._1 } {
        flags := vk_image_get_aspect_flags(&img)
        src_stage: vk.PipelineStageFlags = {}
        if vk_image_is_sampled(img) {
            src_stage += vk_is_depth_or_stencil_format(img.image_format) ? { .LATE_FRAGMENT_TESTS } : { .COLOR_ATTACHMENT_OUTPUT }
        }
        if vk_image_is_storage(img) {
            src_stage += { .COMPUTE_SHADER }
        }

        vk_image_transition_layout(
            &img,
            buffer,
            vk_image_is_sampled(img) ? .SHADER_READ_ONLY_OPTIMAL : .GENERAL,
            src_stage,
            { .FRAGMENT_SHADER, .COMPUTE_SHADER },
            vk.ImageSubresourceRange {
                aspectMask = flags,
                baseMipLevel = 0,
                levelCount = vk.REMAINING_MIP_LEVELS,
                baseArrayLayer = 0,
                layerCount = vk.REMAINING_ARRAY_LAYERS,
            }
        )
    }
}