#!/usr/bin/env python3
"""Pixel sprites for Dino (no PIL needed). Every image is generated in a day and a night (-n) version.

    python3 watch-apps/dino/tools/make_sprites.py
"""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
MAIN = os.path.join(HERE, "..", "entry", "src", "main")
IMAGES = os.path.join(MAIN, "js", "default", "common", "images")
MEDIA = os.path.join(MAIN, "resources", "base", "media")

DAY_INK = (83, 83, 83)
NIGHT_INK = (200, 200, 200)
DAY_CLOUD = (208, 208, 208)
NIGHT_CLOUD = (95, 99, 104)
MOON = (232, 234, 237)
DAY_BG = (247, 247, 247)

HEAD = [
    "...........#######..",
    "..........##.#######",
    "..........##########",
    "..........##########",
    "..........######....",
    "..........########..",
]
DEAD_HEAD = [
    "...........#######..",
    "..........##.#.#####",
    "..........###.######",
    "..........##.#.#####",
    "..........######....",
    "..........########..",
]
BODY = [
    "#........######.....",
    "#.......#######.....",
    "##.....#########....",
    "###...###########...",
    "####.##########.#...",
    "##############......",
    ".#############......",
    "..###########.......",
    "...#########........",
    "....#######.........",
]
LEGS_STAND = [
    ".....###.###........",
    ".....##...##........",
    ".....#.....#........",
    ".....##....##.......",
]
LEGS_RUN1 = [
    ".....###.###........",
    ".....##...####......",
    ".....#..............",
    ".....##.............",
]
LEGS_RUN2 = [
    ".....###.###........",
    "...####...##........",
    "..........#.........",
    "..........##........",
]
CACTUS_SMALL = [
    "...###...",
    "...###...",
    "...###..#",
    "#..###..#",
    "#..###.##",
    "##.###.##",
    "##.###.##",
    "##.######",
    "##.#####.",
    "######...",
    ".#####...",
] + ["...###..."] * 6
CACTUS_LARGE = [
    ".....###.....",
    "....#####....",
    "....#####....",
    "....#####..#.",
    ".#..#####.###",
    "###.#####.###",
    "###.#####.###",
    "###.#####.###",
    "###.#########",
    "###.########.",
    "#########....",
    ".########....",
] + ["....#####...."] * 8
BIRD_UP = [
    ".......#..............",
    ".......##.............",
    ".......###............",
    ".......####...........",
    "...##..#####..........",
    "..#.#..######.........",
    ".#####.#######........",
    "################......",
    "....##############....",
    ".....#############....",
    "......##########......",
    "",
    "",
    "",
]
BIRD_DOWN = [
    "",
    "",
    "",
    "",
    "...##.................",
    "..#.#.................",
    ".#####................",
    "################......",
    "....##############....",
    ".....#############....",
    "......#######.........",
    ".......#####..........",
    ".......###............",
    ".......#..............",
]
CLOUD = [
    ".........#####.........",
    ".......##.....##.......",
    "....###.........#......",
    "..##.............##....",
    ".#.................###.",
    "#.....................#",
    "#######################",
]
MOON_GRID = [
    "..###...",
    "...###..",
    "....###.",
    "....###.",
    ".....###",
    ".....###",
    ".....###",
    ".....###",
    ".....###",
    ".....###",
    "....###.",
    "....###.",
    "...###..",
    "..###...",
]


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


def normalize(grid):
    width = max(len(row) for row in grid)
    return [row.ljust(width, ".") for row in grid]


def side_by_side(*grids, gap=1):
    grids = [normalize(g) for g in grids]
    height = max(len(g) for g in grids)
    grids = [["." * len(g[0])] * (height - len(g)) + g for g in grids]   # aligned to the bottom
    return ["".join(g[y] + ("." * gap if i < len(grids) - 1 else "") for i, g in enumerate(grids))
            for y in range(height)]


def grid_png(path, grid, scale, color):
    grid = normalize(grid)
    width, height = len(grid[0]) * scale, len(grid) * scale
    pixels = bytearray(width * height * 4)
    for y in range(height):
        for x in range(width):
            if grid[y // scale][x // scale] == "#":
                i = (y * width + x) * 4
                pixels[i:i + 4] = bytes(color + (255,))
    write_png(path, width, height, pixels)
    return width, height


def icon_png(path, size, grid, color, background):
    """Pixel dinosaur inside a circle; the circle edge is 4x supersampled, the pixel art stays sharp."""
    grid = normalize(grid)
    gw, gh = len(grid[0]), len(grid)
    scale = size * 0.6 / max(gw, gh)
    ox, oy = (size - gw * scale) / 2, (size - gh * scale) / 2
    ss = 4
    pixels = bytearray(size * size * 4)
    for py in range(size):
        for px in range(size):
            r = g = b = a = 0
            for sy in range(ss):
                for sx in range(ss):
                    x, y = px + (sx + 0.5) / ss, py + (sy + 0.5) / ss
                    if (x - size / 2) ** 2 + (y - size / 2) ** 2 > (size / 2) ** 2:
                        continue
                    cx, cy = int((x - ox) // scale), int((y - oy) // scale)
                    fill = color if 0 <= cx < gw and 0 <= cy < gh and grid[cy][cx] == "#" else background
                    r, g, b, a = r + fill[0], g + fill[1], b + fill[2], a + 1
            if a:
                i = (py * size + px) * 4
                pixels[i:i + 4] = bytes((r // a, g // a, b // a, 255 * a // (ss * ss)))
    write_png(path, size, size, pixels)


def ground_grid():
    """566 px wide ground strip; the pattern repeats every 100 px, so scrolling never shows a seam."""
    width, rows = 566, 12
    grid = [["."] * width for _ in range(rows)]
    for x in range(width):
        grid[0][x] = grid[1][x] = "#"
    marks = [(4, 8, 5), (21, 23, 9), (37, 43, 4), (55, 56, 7), (68, 71, 10), (83, 88, 6), (95, 96, 9)]
    for start in range(0, width, 100):
        for x0, x1, row in marks:
            for x in range(start + x0, min(width, start + x1 + 1)):
                grid[row][x] = "#"
    return ["".join(row) for row in grid]


def main():
    sprites = {
        "dino-stand": (HEAD + BODY + LEGS_STAND, 3),
        "dino-run1": (HEAD + BODY + LEGS_RUN1, 3),
        "dino-run2": (HEAD + BODY + LEGS_RUN2, 3),
        "dino-dead": (DEAD_HEAD + BODY + LEGS_STAND, 3),
        "cactus-s1": (CACTUS_SMALL, 3),
        "cactus-s2": (side_by_side(CACTUS_SMALL, CACTUS_SMALL), 3),
        "cactus-s3": (side_by_side(CACTUS_SMALL, CACTUS_SMALL, CACTUS_SMALL), 3),
        "cactus-l1": (CACTUS_LARGE, 3),
        "cactus-l2": (side_by_side(CACTUS_LARGE, CACTUS_LARGE), 3),
        "bird-1": (BIRD_UP, 2),
        "bird-2": (BIRD_DOWN, 2),
        "ground": (ground_grid(), 1),
    }
    for name, (grid, scale) in sprites.items():
        size = grid_png(os.path.join(IMAGES, name + ".png"), grid, scale, DAY_INK)
        grid_png(os.path.join(IMAGES, name + "-n.png"), grid, scale, NIGHT_INK)
        print(name, size)
    print("cloud", grid_png(os.path.join(IMAGES, "cloud.png"), CLOUD, 2, DAY_CLOUD))
    grid_png(os.path.join(IMAGES, "cloud-n.png"), CLOUD, 2, NIGHT_CLOUD)
    print("moon", grid_png(os.path.join(IMAGES, "moon.png"), MOON_GRID, 3, MOON))
    for name, size in (("icon.png", 114), ("icon_small.png", 41)):
        icon_png(os.path.join(MEDIA, name), size, HEAD + BODY + LEGS_STAND, DAY_INK, DAY_BG)


if __name__ == "__main__":
    main()
