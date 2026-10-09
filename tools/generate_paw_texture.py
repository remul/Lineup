#!/usr/bin/env python3
"""Writes Media/Paw.tga, the paw from Lineup's emblem (Media/Emblem.svg) on its own.

    python3 tools/generate_paw_texture.py

White on transparent, so it can be tinted in game, e.g. in the button text's colour.
"""
import struct
from pathlib import Path

SIZE = 64
SAMPLES = 4  # per axis, for smooth edges
MEDIA = Path(__file__).resolve().parent.parent / "Media"

# The emblem's paw, in its 512 x 512 coordinates: three toes and the pad (cubic Béziers).
TOES = [(186, 196, 34), (256, 172, 38), (326, 196, 34)]
PAD_START = (256, 236)
PAD_CURVES = [
    ((318, 236), (352, 282), (352, 320)),
    ((352, 356), (326, 370), (296, 362)),
    ((282, 358), (270, 354), (256, 354)),
    ((242, 354), (230, 358), (216, 362)),
    ((186, 370), (160, 356), (160, 320)),
    ((160, 282), (194, 236), (256, 236)),
]
# The square of the emblem drawn into the texture: the paw's bounds plus a little room.
LEFT, TOP, SIDE = 130, 124, 252


def flatten_pad():
    points, start = [], PAD_START
    for c1, c2, end in PAD_CURVES:
        for step in range(1, 33):
            t = step / 32
            u = 1 - t
            points.append(tuple(
                u * u * u * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t * p3
                for p0, p1, p2, p3 in zip(start, c1, c2, end)
            ))
        start = end
    return points


PAD = flatten_pad()


def in_pad(x, y):
    inside = False
    for (x1, y1), (x2, y2) in zip(PAD, PAD[1:] + PAD[:1]):
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
            inside = not inside
    return inside


def in_paw(x, y):
    return in_pad(x, y) or any((x - cx) ** 2 + (y - cy) ** 2 <= r * r for cx, cy, r in TOES)


def coverage(px, py):
    hits = 0
    for sx in range(SAMPLES):
        for sy in range(SAMPLES):
            x = LEFT + (px + (sx + 0.5) / SAMPLES) * SIDE / SIZE
            y = TOP + (py + (sy + 0.5) / SAMPLES) * SIDE / SIZE
            hits += in_paw(x, y)
    return hits / (SAMPLES * SAMPLES)


def write_tga(path):
    # Uncompressed 32-bit TGA, rows from the top (descriptor: 8 alpha bits, top-left origin).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    pixels = bytearray()
    for py in range(SIZE):
        for px in range(SIZE):
            pixels += bytes((255, 255, 255, round(255 * coverage(px, py))))  # BGRA
    path.write_bytes(header + bytes(pixels))
    print(f"Wrote {path.relative_to(MEDIA.parent)}")


write_tga(MEDIA / "Paw.tga")
