#!/usr/bin/env python3
"""Draws tools/trace_surround.gd's CSV as a top-down PNG. Standard library only.

Black: the player. One colour per soldier; the attacker's trail is drawn heavier.
The last position of each is a large square. Grid lines every two metres.

    python3 tools/plot_trace.py trace.csv trace.png
"""
import csv
import struct
import sys
import zlib

SIZE = 600
COLOURS = [(220, 50, 50), (40, 120, 220), (40, 170, 80), (200, 140, 20)]


def main(src, dst):
    rows = [list(map(float, r)) for r in csv.reader(open(src))]
    xs, zs = [], []
    for r in rows:
        xs += [r[1]] + r[3::3]
        zs += [r[2]] + r[4::3]
    minx, maxx, minz, maxz = min(xs) - 2, max(xs) + 2, min(zs) - 2, max(zs) + 2
    span = max(maxx - minx, maxz - minz)
    img = [[(250, 250, 250)] * SIZE for _ in range(SIZE)]

    def at(x, z):
        return int((x - minx) / span * (SIZE - 1)), int((z - minz) / span * (SIZE - 1))

    def dot(x, z, colour, radius):
        cx, cy = at(x, z)
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if 0 <= cx + dx < SIZE and 0 <= cy + dy < SIZE:
                    img[cy + dy][cx + dx] = colour

    for gx in range(int(minx), int(maxx) + 1, 2):
        x, _ = at(gx, minz)
        for y in range(SIZE):
            img[y][x] = (225, 225, 225)
    for gz in range(int(minz), int(maxz) + 1, 2):
        _, y = at(minx, gz)
        for x in range(SIZE):
            img[y][x] = (225, 225, 225)

    for k, r in enumerate(rows):
        last = k == len(rows) - 1
        dot(r[1], r[2], (0, 0, 0), 3 if last else 1)
        for i in range((len(r) - 3) // 3):
            x, z, slot = r[3 + i * 3], r[4 + i * 3], r[5 + i * 3]
            dot(x, z, COLOURS[i % len(COLOURS)], 4 if last else (2 if slot else 1))

    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in img)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    with open(dst, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))

    final = rows[-1]
    for i in range((len(final) - 3) // 3):
        x, z, slot = final[3 + i * 3], final[4 + i * 3], final[5 + i * 3]
        d = ((x - final[1]) ** 2 + (z - final[2]) ** 2) ** 0.5
        print(f"soldier {i}: {'attacking' if slot else 'waiting  '} {d:5.2f} m from the player at ({x:.1f}, {z:.1f})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
