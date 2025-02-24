package milk

import pt "platform"

import "core:math/linalg/glsl"

Vector2 :: pt.Vector2
Vector3 :: pt.Vector3
Vector4 :: pt.Vector4

DVector2 :: pt.DVector2
DVector3 :: pt.DVector3
DVector4 :: pt.DVector4

IVector2 :: pt.IVector2
IVector3 :: pt.IVector3
IVector4 :: pt.IVector4

UVector2 :: pt.UVector2
UVector3 :: pt.UVector3
UVector4 :: pt.UVector4

Point_2D :: pt.Point_2D
Point_3D :: pt.Point_3D

Mat4 :: pt.Mat4

IDENTITY_MATRIX :: matrix[4, 4]f64 {
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
}

Vertex :: pt.Vertex

Transform_2D :: struct {
    position: Point_2D,
    rotation: f64,
    scale: Vector2,
}

Transform_3D :: struct {
    mat: Mat4,
}

transform_3d_new :: proc() -> (out: Transform_3D) {
    out.mat = 1
    return
}

transform_3d_from_xyz :: proc(position: Point_3D) -> (out: Transform_3D) {
    out.mat = glsl.mat4Translate(position)

    out.mat[1][1] *= -1

    return
}

transform_3d_rotate_degrees :: proc(trans: ^Transform_3D, angle: f32, axis: Vector3) {
    trans.mat *= glsl.mat4Rotate(axis, glsl.radians(angle))
}

transform_get_scale :: proc {
    transform_3d_get_scale,
}

transform_3d_get_scale :: proc(trans: Transform_3D) -> Vector4 {
    return { trans.mat[0, 0], trans.mat[1, 1], trans.mat[2, 2], trans.mat[3, 3] }
}

transform_get_position :: proc {
    transform_3d_get_position,
}

transform_3d_get_position :: proc(trans: Transform_3D) -> Vector4 {
    return trans.mat[3].xyzw
}

transform_translate :: proc {
    transform_2d_translate,
    transform_3d_translate,
}

transform_2d_translate :: proc(trans: ^Transform_2D, vector: Vector2) {
    trans.position += vector
}

transform_3d_translate :: proc(trans: ^Transform_3D, vector: Vector3) {
    trans.mat[3].xyz += vector
}