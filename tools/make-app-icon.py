#!/usr/bin/env python3
"""Creates the two icons a watch app needs: icon.png (114x114) and icon_small.png (41x41).

    tools/make-app-icon.py watch-apps/my-app            (green)
    tools/make-app-icon.py watch-apps/my-app 2A6FDB     (any hex color)

The watch installer requires BOTH in the icon folder; without icon_small the install fails with "103".
To use your own icon, put files with the same names in resources/base/media/
(sips -z 41 41 icon.png --out icon_small.png). No PIL needed: a colored disc with a white ring, 4x supersampled.
"""
import os
import struct
import sys
import zlib


def png(path, size, color):
    r, g, b = color
    rows = []
    samples = 4
    for py in range(size):
        row = bytearray([0])
        for px in range(size):
            fill = ring = 0
            for sy in range(samples):
                for sx in range(samples):
                    x = (px + (sx + 0.5) / samples) / size - 0.5
                    y = (py + (sy + 0.5) / samples) / size - 0.5
                    d = (x * x + y * y) ** 0.5
                    if d <= 0.48:
                        fill += 1
                        if 0.30 <= d <= 0.38:
                            ring += 1
            total = samples * samples
            alpha = round(255 * fill / total)
            white = ring / max(fill, 1)
            row += bytes((round(r + (255 - r) * white), round(g + (255 - g) * white), round(b + (255 - b) * white), alpha))
        rows.append(bytes(row))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    media = os.path.join(sys.argv[1], "entry/src/main/resources/base/media")
    color = sys.argv[2] if len(sys.argv) > 2 else "33CC66"
    rgb = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))
    os.makedirs(media, exist_ok=True)
    png(os.path.join(media, "icon.png"), 114, rgb)
    png(os.path.join(media, "icon_small.png"), 41, rgb)
    print("icons:", media)
    return 0


if __name__ == "__main__":
    sys.exit(main())
