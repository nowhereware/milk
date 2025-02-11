package milk_core

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

COLOR_BLACK :: Color {
    value = { 0, 0, 0, 255 },
    format = .RGBA
}

COLOR_CORNFLOWER_BLUE :: Color {
    value = { 100, 149, 237, 255 },
    format = .RGBA
}

COLOR_GRAY_10 :: Color {
    value = { 0.1, 0.1, 0.1, 1.0 },
    format = .Percent
}

COLOR_GRAY_20 :: Color {
    value = { 0.2, 0.2, 0.2, 1.0 },
    format = .Percent
}

COLOR_GRAY_30 :: Color {
    value = { 0.3, 0.3, 0.3, 1.0 },
    format = .Percent
}

COLOR_GRAY_40 :: Color {
    value = { 0.4, 0.4, 0.4, 1.0 },
    format = .Percent
}

COLOR_GRAY_50 :: Color {
    value = { 0.5, 0.5, 0.5, 1.0 },
    format = .Percent
}

COLOR_GRAY_60 :: Color {
    value = { 0.6, 0.6, 0.6, 1.0 },
    format = .Percent
}

COLOR_GRAY_70 :: Color {
    value = { 0.7, 0.7, 0.7, 1.0 },
    format = .Percent
}

COLOR_GRAY_80 :: Color {
    value = { 0.8, 0.8, 0.8, 1.0 },
    format = .Percent
}

COLOR_GRAY_90 :: Color {
    value = { 0.9, 0.9, 0.9, 1.0 },
    format = .Percent
}