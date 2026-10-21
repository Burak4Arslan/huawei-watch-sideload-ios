#!/usr/bin/env python3
"""Generates the images for Flappy (no PIL needed): bird frames, score digits, app icons.

    python3 watch-apps/flappy/tools/make_sprites.py

The bird is drawn from shapes (ellipses + circles), 4x supersampled for smooth edges.
"""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
MAIN = os.path.join(HERE, "..", "entry", "src", "main")
IMAGES = os.path.join(MAIN, "js", "default", "common", "images")
MEDIA = os.path.join(MAIN, "resources", "base", "media")

OUTLINE = (58, 40, 14)
BODY = (247, 210, 58)
BELLY = (251, 232, 150)
WING = (255, 247, 205)
WHITE = (255, 255, 255)
PUPIL = (20, 20, 20)
BEAK = (240, 104, 42)
SKY = (78, 192, 202)


def write_png(path, width, height, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * width * 4:(y + 1) * width * 4]) for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def ellipse(cx, cy, rx, ry):
    return lambda x, y: ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1


def grow(cx, cy, rx, ry, by):
    return ellipse(cx, cy, rx + by, ry + by)


def bird_layers(wing_y):
    """The bird's layers (bottom to top) in 56x42 coordinates (image 60x46, 2 px margin). Each shape: dark outline first, then fill."""
    shapes = [
        ((24, 22, 20, 16), BODY),
        ((27, 29, 13, 7), BELLY),
        ((45, 25, 9, 4.8), BEAK),
        ((44, 29.5, 7, 3.2), BEAK),
        ((34, 13, 7.5, 7.5), WHITE),
        ((13, wing_y, 10.5, 6.5), WING),
    ]
    layers = []
    for (cx, cy, rx, ry), color in shapes:
        layers.append((grow(cx, cy, rx, ry, 2.2), OUTLINE))
        layers.append((ellipse(cx, cy, rx, ry), color))
    layers.append((ellipse(36.5, 13.5, 3.2, 3.6), PUPIL))
    return layers


def render(width, height, layers, scale=1.0, offset=(0, 0), background=None, ss=4):
    """Supersamples the layers into RGBA pixels. scale/offset move the shape coordinates."""
    pixels = bytearray(width * height * 4)
    for py in range(height):
        for px in range(width):
            r = g = b = a = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    x = (px + (sx + 0.5) / ss - offset[0]) / scale
                    y = (py + (sy + 0.5) / ss - offset[1]) / scale
                    color = None
                    for inside, fill in layers:
                        if inside(x, y):
                            color = fill
                    if color is None and background is not None:
                        inside_bg, fill_bg = background
                        if inside_bg(px + (sx + 0.5) / ss, py + (sy + 0.5) / ss):
                            color = fill_bg
                    if color is not None:
                        r += color[0]
                        g += color[1]
                        b += color[2]
                        a += 1
            i = (py * width + px) * 4
            if a:
                pixels[i:i + 4] = bytes((int(r / a), int(g / a), int(b / a), int(255 * a / (ss * ss))))
    return pixels


# 3x5 pixel digits, scaled up like a bold game font
DIGITS = {
    "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"],
    "2": ["111", "001", "111", "100", "111"],
    "3": ["111", "001", "111", "001", "111"],
    "4": ["101", "101", "111", "001", "001"],
    "5": ["111", "100", "111", "001", "111"],
    "6": ["111", "100", "111", "101", "111"],
    "7": ["111", "001", "001", "001", "001"],
    "8": ["111", "101", "111", "101", "111"],
    "9": ["111", "101", "111", "001", "111"],
}
CELL = 9
EDGE = 3
DIGIT_W = 3 * CELL + 2 * EDGE   # 33
DIGIT_H = 5 * CELL + 2 * EDGE   # 51


def digit_png(rows):
    pixels = bytearray(DIGIT_W * DIGIT_H * 4)

    def on(cx, cy):
        return 0 <= cy < 5 and 0 <= cx < 3 and rows[cy][cx] == "1"

    for py in range(DIGIT_H):
        for px in range(DIGIT_W):
            x, y = px - EDGE, py - EDGE
            cx, cy = (x // CELL if x >= 0 else -1), (y // CELL if y >= 0 else -1)
            color = None
            if x >= 0 and y >= 0 and on(cx, cy):
                color = WHITE
            else:
                for dy in (-EDGE, 0, EDGE):
                    for dx in (-EDGE, 0, EDGE):
                        nx, ny = x + dx, y + dy
                        if nx >= 0 and ny >= 0 and on(nx // CELL, ny // CELL):
                            color = OUTLINE
            if color:
                i = (py * DIGIT_W + px) * 4
                pixels[i:i + 4] = bytes(color + (255,))
    return pixels


def main():
    for index, wing_y in enumerate((16, 22, 27)):
        write_png(os.path.join(IMAGES, "bird%d.png" % index), 60, 46, render(60, 46, bird_layers(wing_y), offset=(2, 2)))
    for name, rows in DIGITS.items():
        write_png(os.path.join(IMAGES, "n%s.png" % name), DIGIT_W, DIGIT_H, digit_png(rows))
    # Icons: the bird in a sky-colored circle (the watch shows icons round)
    for name, size in (("icon.png", 114), ("icon_small.png", 41)):
        scale = size * 0.62 / 56
        offset = ((size - 56 * scale) / 2, (size - 42 * scale) / 2)
        disc = (ellipse(size / 2, size / 2, size / 2, size / 2), SKY)
        write_png(os.path.join(MEDIA, name), size, size,
                  render(size, size, bird_layers(22), scale, offset, background=disc))
    print("ok:", IMAGES, MEDIA)


if __name__ == "__main__":
    main()
