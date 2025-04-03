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

        gl.CreateBuffers(1, d.vertex_buffer)
        gl.NamedBufferStorage(d.vertex_buffer^, len(d.vertices) * size_of(milk.Vertex), raw_data(d.vertices), gl.DYNAMIC_STORAGE_BIT)
        d.vertex_count^ = cast(i32)len(d.vertices)

        fmt.println(d.vertices)

        gl.CreateBuffers(1, d.index_buffer)
        gl.NamedBufferStorage(d.index_buffer^, len(d.indices) * size_of(u32), raw_data(d.indices), gl.DYNAMIC_STORAGE_BIT)
        d.index_count^ = cast(i32)len(d.indices)

        gl.CreateVertexArrays(1, d.vao)
    
        gl.VertexArrayVertexBuffer(d.vao^, 0, d.vertex_buffer^, 0, size_of(milk.Vertex))
        gl.VertexArrayElementBuffer(d.vao^, d.index_buffer^)

        gl.EnableVertexArrayAttrib(d.vao^, 0)
        gl.EnableVertexArrayAttrib(d.vao^, 1)
        gl.EnableVertexArrayAttrib(d.vao^, 2)

        gl.VertexArrayAttribFormat(d.vao^, 0, 3, gl.FLOAT, false, cast(u32)offset_of(milk.Vertex, position))
        gl.VertexArrayAttribFormat(d.vao^, 1, 2, gl.FLOAT, false, cast(u32)offset_of(milk.Vertex, uv))
        gl.VertexArrayAttribFormat(d.vao^, 2, 3, gl.FLOAT, false, cast(u32)offset_of(milk.Vertex, normal))

        gl.VertexArrayAttribBinding(d.vao^, 0, 0)
        gl.VertexArrayAttribBinding(d.vao^, 1, 0)
        gl.VertexArrayAttribBinding(d.vao^, 2, 0)

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