package milk_gfx_3d_platform

import "core:fmt"

import "../../../milk"
import pt "../../../milk/platform"

import gl "vendor:OpenGL"

Gl_Mesh :: struct {
    vertex_count: ^i32,
    vertex_buffer: ^u32,
    index_count: ^i32,
    index_buffer: ^u32,
    uniform_buffer: ^u32,
    vao: ^u32,
}

gl_mesh_new :: proc(cmd: pt.Command_Buffer_Internal, vertices: []milk.Vertex, indices: []u32) -> Mesh_Internal {
    cmd := cmd.(^pt.Gl_Command_Buffer)
    out: Gl_Mesh

    Submit_Data :: struct {
        cmd: ^pt.Gl_Command_Buffer,
        vertices: [dynamic]milk.Vertex,
        indices: [dynamic]u32,
        vertex_count: ^i32,
        vertex_buffer: ^u32,
        index_count: ^i32,
        index_buffer: ^u32,
        uniform_buffer: ^u32,
        vao: ^u32,
    }

    out.vertex_count = new(i32)
    out.vertex_buffer = new(u32)
    out.index_count = new(i32)
    out.index_buffer = new(u32)
    out.uniform_buffer = new(u32)
    out.vao = new(u32)

    vs := make([dynamic]milk.Vertex)

    for vert in vertices {
        append(&vs, vert)
    }

    is := make([dynamic]u32)

    for index in indices {
        append(&is, index)
    }

    new_data := Submit_Data {
        cmd = cmd,
        vertices = vs,
        indices = is,
        vertex_count = out.vertex_count,
        vertex_buffer = out.vertex_buffer,
        index_count = out.index_count,
        index_buffer = out.index_buffer,
        uniform_buffer = out.uniform_buffer,
        vao = out.vao,
    }

    command :: proc(data: rawptr) {
        d := cast(^Submit_Data)data

        fmt.println("NEW MESH")

        // Create VAO
        gl.GenVertexArrays(1, d.vao)
    
        // Create vertex buffer
        gl.GenBuffers(1, d.vertex_buffer)

        // Create index buffer
        gl.GenBuffers(1, d.index_buffer)

        gl.BindVertexArray(d.vao^)

        temp_vertices := make([dynamic]f32)

        for vert in d.vertices {
            append_elems(&temp_vertices, vert.position.x, vert.position.y, vert.position.z)
        }

        fmt.println(temp_vertices)

        gl.BindBuffer(gl.ARRAY_BUFFER, d.vertex_buffer^)
        gl.BufferData(gl.ARRAY_BUFFER, len(temp_vertices) * size_of(f32), raw_data(temp_vertices), gl.STATIC_DRAW)
        d.vertex_count^ = cast(i32)len(temp_vertices)

        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, d.index_buffer^)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(d.indices) * size_of(u32), raw_data(d.indices[:]), gl.STATIC_DRAW)
        d.index_count^ = cast(i32)len(d.indices)

        gl.VertexAttribPointer(0, 3, gl.FLOAT, false, 3 * size_of(f32), 0)
        gl.EnableVertexAttribArray(0)

        delete(temp_vertices)
        delete(d.vertices)
        delete(d.indices)
        free(data)
    }

    append(&cmd.commands, pt.Gl_Command { new_clone(new_data), command })

    return out
}

gl_mesh_bind_buffers :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal, pos: ^milk.Transform_3D, cam_pos: ^milk.Transform_3D, cam: ^milk.Camera_3D) {
    cmd := cmd.(^pt.Gl_Command_Buffer)
    mesh := &mesh.(Gl_Mesh)

    Submit_Data :: struct {
        vertex_buffer: ^u32,
        index_buffer: ^u32,
        uniform_buffer: ^u32,
        vao: ^u32,
        pos: ^milk.Transform_3D,
        cam_pos: ^milk.Transform_3D,
        cam: ^milk.Camera_3D,
    }

    submit := Submit_Data {
        vertex_buffer = mesh.vertex_buffer,
        index_buffer = mesh.index_buffer,
        uniform_buffer = mesh.uniform_buffer,
        vao = mesh.vao,
        pos = pos,
        cam_pos = cam_pos,
        cam = cam,
    }

    command :: proc(data: rawptr) {
        d := cast(^Submit_Data)data

        /*
        ubo := pt.Uniform_Buffer_Object {
            model = d.pos.mat,
            view = d.cam_pos.mat,
            proj = d.cam.projection
        }
        */
    
        //gl.NamedBufferSubData(d.uniform_buffer^, 0, size_of(pt.Uniform_Buffer_Object), &ubo)

        gl.BindVertexArray(d.vao^)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, d.index_buffer^)
    
        //gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, d.index_buffer^)

        free(data)
    }

    append(&cmd.commands, pt.Gl_Command { new_clone(submit), command })
}

gl_mesh_draw :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal) {
    cmd := cmd.(^pt.Gl_Command_Buffer)
    mesh := &mesh.(Gl_Mesh)

    Submit_Data :: struct {
        index_count: ^i32,
    }

    submit_data := Submit_Data {
        index_count = mesh.index_count,
    }

    command :: proc(data: rawptr) {
        d := cast(^Submit_Data)data
        
        gl.DrawElements(gl.TRIANGLES, d.index_count^, gl.UNSIGNED_INT, nil)

        free(data)
    }

    append(&cmd.commands, pt.Gl_Command { new_clone(submit_data), command })
}

gl_mesh_destroy :: proc(cmd: pt.Command_Buffer_Internal, mesh: ^Mesh_Internal) {
    cmd := cmd.(^pt.Gl_Command_Buffer)
    mesh := &mesh.(Gl_Mesh)

    free(mesh.vertex_count)
    free(mesh.index_count)
    
    gl.DeleteBuffers(1, mesh.vertex_buffer)
    gl.DeleteBuffers(1, mesh.index_buffer)
    gl.DeleteBuffers(1, mesh.uniform_buffer)
    gl.DeleteVertexArrays(1, mesh.vao)

    free(mesh.vertex_buffer)
    free(mesh.index_buffer)
    free(mesh.uniform_buffer)
    free(mesh.vao)
}