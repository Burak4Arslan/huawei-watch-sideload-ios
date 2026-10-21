#!/usr/bin/env python3
"""Generated files for Snake: game.hml (a pool of 40 segments) and the icons.

    python3 watch-apps/snake/tools/make_assets.py

Each segment of the snake is its own square; every step only moves the tail square to the front.
"""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
MAIN = os.path.join(HERE, "..", "entry", "src", "main")
POOL = 40
BG = (199, 240, 216)
INK = (67, 82, 61)


def write_png(path, width, height, pixels):
    raw = b"".join(b"\x00" + bytes(pixels[y * width * 4:(y + 1) * width * 4]) for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def icon(path, size):
    """A curled pixel snake and food in a Nokia green circle."""
    snake = [(1, 4), (2, 4), (3, 4), (4, 4), (4, 3), (4, 2), (5, 2), (6, 2), (7, 2), (7, 3), (7, 4), (7, 5), (7, 6)]
    food = (3, 7)
    cell = size / 9.0
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
                    c, rr = int(x // cell), int(y // cell)
                    inner = (x % cell) > cell * 0.08 and (y % cell) > cell * 0.08
                    fill = INK if inner and ((c, rr) in snake or (c, rr) == food) else BG
                    r, g, b, a = r + fill[0], g + fill[1], b + fill[2], a + 1
            if a:
                i = (py * size + px) * 4
                pixels[i:i + 4] = bytes((r // a, g // a, b // a, 255 * a // (ss * ss)))
    write_png(path, size, size, pixels)


def page():
    segments = "\n".join(
        '    <div class="seg" style="left: {{s%dx}}; top: {{s%dy}};"></div>' % (i, i) for i in range(POOL))
    return """<stack class="screen">
    <div class="food" style="left: {{foodX}}; top: {{foodY}};"></div>
%s
    <div class="eye" style="left: {{eyeX}}; top: {{eyeY}};"></div>

    <text class="score">{{scoreText}}</text>

    <text class="title" show="{{state == 'ready'}}">Snake</text>
    <text class="hint" show="{{state == 'ready'}}">Tap to start</text>
    <text class="hint2" show="{{state == 'ready'}}">Turns toward your tap</text>

    <div class="panel" show="{{state == 'over'}}">
        <text class="panel-title">Game over</text>
        <text class="panel-line">{{resultText}}</text>
        <text class="panel-line">{{bestText}}</text>
    </div>
    <text class="hint" show="{{state == 'over'}}">Tap to play again</text>

    <div class="touch" ontouchstart="press" onclick="tap"></div>
</stack>
""" % segments


def main():
    with open(os.path.join(MAIN, "js", "default", "pages", "game", "game.hml"), "w") as f:
        f.write(page())
    media = os.path.join(MAIN, "resources", "base", "media")
    icon(os.path.join(media, "icon.png"), 114)
    icon(os.path.join(media, "icon_small.png"), 41)
    print("ok")


if __name__ == "__main__":
    main()
