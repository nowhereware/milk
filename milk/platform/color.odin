package milk_platform

import "core:math"

@(private="file")
SRGB_FRACTION : f32 : 1.0 / 2.4

Color_Format :: enum {
    RGBA,
    Percent,
    SRGB
}

Color :: struct {
    using value: Vector4,
    format: Color_Format
}

color_from_rgba :: proc(input: Vector4) -> Color {
    out: Color

    out.format = .RGBA
    out.value = input

    return out
}

color_from_percent :: proc(input: Vector4) -> Color {
    out: Color

    out.format = .Percent
    out.value = input

    return out
}

color_from_srgb :: proc(input: Vector4) -> Color {
    out: Color

    out.format = .SRGB
    out.value = input

    return out
}

color_as_rgba :: proc(input: Color) -> Color {
    out := input

    if out.format != .RGBA {
        out.value.r *= 255
        out.value.g *= 255
        out.value.b *= 255
        out.value.a *= 255
        out.format = .RGBA
    }

    return out
}

color_as_percent :: proc(input: Color) -> Color {
    out := input

    switch out.format {
    case .RGBA: {
        out.r /= 255
        out.g /= 255
        out.b /= 255
        out.a /= 255
        out.format = .Percent
    }
    case .SRGB: {
        out.r = math.pow((out.r + 0.055) / 1.055, 2.4)
        out.g = math.pow((out.g + 0.055) / 1.055, 2.4)
        out.b = math.pow((out.b + 0.055) / 1.055, 2.4)
        out.a = math.pow((out.a + 0.055) / 1.055, 2.4)
        out.format = .Percent
    }
    case .Percent: {
        break
    }
    }

    return out
}

color_as_srgb :: proc(input: Color) -> Color {
    out := input

    switch out.format {
    case .Percent: {
        out.r = (math.pow(out.r, SRGB_FRACTION) * 1.055) - 0.055
        out.g = (math.pow(out.g, SRGB_FRACTION) * 1.055) - 0.055
        out.b = (math.pow(out.b, SRGB_FRACTION) * 1.055) - 0.055
        out.a = (math.pow(out.a, SRGB_FRACTION) * 1.055) - 0.055
        out.format = .SRGB
    }
    case .RGBA: {
        out = color_as_percent(out)
        out = color_as_srgb(out)
    }
    case .SRGB: {
        break
    }
    }

    return out
}