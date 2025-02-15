package milk

import "core:math/linalg/glsl"

Vector2 :: glsl.vec2
Vector3 :: glsl.vec3
Vector4 :: glsl.vec4

DVector2 :: glsl.dvec2
DVector3 :: glsl.dvec3
DVector4 :: glsl.dvec4

IVector2 :: glsl.ivec2
IVector3 :: glsl.ivec3
IVector4 :: glsl.ivec4

UVector2 :: glsl.uvec2
UVector3 :: glsl.uvec3
UVector4 :: glsl.uvec4

Point_2D :: Vector2
Point_3D :: Vector3

Mat4 :: glsl.mat4

Vertex :: struct {
	pos: Point_2D,
	color: Vector3
}

Transform_2D :: struct {
    position: Point_2D,
    rotation: f64,
    scale: Vector2,
}

Transform_3D :: struct {
    mat: Mat4,
}

transform_3d_from_xyz :: proc(position: Point_3D) -> (out: Transform_3D) {
    out.mat = glsl.mat4Translate(position)

    out.mat[1][1] *= -1

    return
}

transform_3d_rotate_degrees :: proc(trans: ^Transform_3D, angle: f32, axis: Vector3) {
    trans.mat *= glsl.mat4Rotate(axis, glsl.radians(angle))
}