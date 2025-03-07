package milk

import "core:math/linalg/glsl"

Viewport :: struct {
    // The current entity with Camera components that is bound to the Viewport.
    current: Maybe(Entity),
    // The resolution in pixels of the Viewport.
    resolution: Vector2,
}

viewport_set_camera :: proc(viewport: ^Viewport, ent: Entity) {
    viewport.current = ent
}

Camera_3D :: struct {
    fov: f32,
    aspect: f32,
    near: f32,
    far: f32,
    projection: Mat4,
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

camera_3d_look_at :: proc(cam: ^Camera_3D, trans: ^Transform_3D, center: Vector3) {
    trans.mat = glsl.mat4LookAt(trans.mat[3].xyz, center, {0, 0, 1})
}