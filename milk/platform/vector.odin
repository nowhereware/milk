package milk_platform

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
	position: Point_3D,
	uv: Vector2,
	normal: Vector3,
}