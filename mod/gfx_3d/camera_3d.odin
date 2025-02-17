package milk_gfx_3d

import "../../milk"

import "core:math/linalg/glsl"

Camera_3D :: struct {
    fov: f32,
    aspect: f32,
    near: f32,
    far: f32,
    projection: milk.Mat4,
}

camera_3d_new :: proc(fov, aspect, near, far: f32) -> (out: Camera_3D) {
    out.fov = fov
    out.aspect = aspect
    out.near = near
    out.far = far
    out.projection = glsl.mat4Perspective(glsl.radians(fov), aspect, near, far)

    return
}

camera_3d_update_aspect :: proc(cam: ^Camera_3D, aspect: f32) {
    tan_half_fovy := glsl.tan(0.5 * cam.fov)
	cam.projection[0, 0] = 1 / (cam.aspect * tan_half_fovy)
}

camera_3d_look_at :: proc(cam: ^Camera_3D, trans: ^milk.Transform_3D, center: milk.Vector3) {
    trans.mat = glsl.mat4LookAt(trans.mat[3].xyz, center, {0, 0, 1})
}