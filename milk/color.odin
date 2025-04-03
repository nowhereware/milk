package milk

import pt "platform"

Color_Format :: pt.Color_Format

Color :: pt.Color

color_as_percent :: pt.color_as_percent
color_as_rgba :: pt.color_as_rgba
color_as_srgb :: pt.color_as_srgb

color_from_percent :: pt.color_from_percent
color_from_rgba :: pt.color_from_rgba
color_from_srgb :: pt.color_from_srgb

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