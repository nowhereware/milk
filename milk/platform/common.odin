package milk_platform

MAX_COLOR_ATTACHMENTS :: 8

Load_Op :: enum {
    Invalid,
    Dont_Care,
    Load,
    Clear,
    None,
}

Store_Op :: enum {
    Dont_Care,
    Store,
    MSAA_Resolve,
    None,
}

Render_Attachment :: struct {
    load_op: Load_Op,
    store_op: Store_Op,
    layer: u8,
    level: u8,
    clear_color: Color,
    clear_depth: f32,
    clear_stencil: u32,
}

Render_Pass :: struct {
    color: [dynamic]Render_Attachment,
    depth: Render_Attachment,
    stencil: Render_Attachment,
}

render_pass_new :: proc(color_attaches: []Render_Attachment) -> (out: Render_Pass) {
    out.color = make([dynamic]Render_Attachment, 0, MAX_COLOR_ATTACHMENTS)
    append_elems(&out.color, ..color_attaches)

    return
}

Frame_Attachment :: struct {
    texture: Texture_Internal,
    resolve_texture: Texture_Internal,
}

Framebuffer :: struct {
    color: [dynamic]Frame_Attachment,
    depth_stencil: Frame_Attachment,
}

framebuffer_new :: proc(color_attaches: []Frame_Attachment) -> (out: Framebuffer) {
    out.color = make([dynamic]Frame_Attachment, 0, MAX_COLOR_ATTACHMENTS)
    append_elems(&out.color, ..color_attaches)

    return
}