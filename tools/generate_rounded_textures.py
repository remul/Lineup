#!/usr/bin/env python3
"""Writes the rounded-rectangle textures in Media/ used for Lineup's cards.

    python3 tools/generate_rounded_textures.py

Both are white (tinted in game with SetVertexColor) and drawn as nine-slices, so the corners keep
their size however big the card is (see ns.CreateRoundedTexture in Core.lua):
  RoundedFill.tga    a filled rounded rectangle
  RoundedBorder.tga  just its outline
"""
import math
import struct
from pathlib import Path

SIZE = 32
RADIUS = 8
BORDER = 1.5
SAMPLES = 4  # per axis, for smooth edges
MEDIA = Path(__file__).resolve().parent.parent / "Media"


def distance_outside(x, y):
    """Signed distance from the rounded rectangle's edge (negative inside)."""
    cx = min(max(x, RADIUS), SIZE - RADIUS)
    cy = min(max(y, RADIUS), SIZE - RADIUS)
    return math.hypot(x - cx, y - cy) - RADIUS


def coverage(px, py, inside):
    hits = 0
    for sx in range(SAMPLES):
        for sy in range(SAMPLES):
            x = px + (sx + 0.5) / SAMPLES
            y = py + (sy + 0.5) / SAMPLES
            hits += inside(distance_outside(x, y))
    return hits / (SAMPLES * SAMPLES)


def write_tga(path, inside):
    # Uncompressed 32-bit TGA, rows from the top (descriptor: 8 alpha bits, top-left origin).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    pixels = bytearray()
    for py in range(SIZE):
        for px in range(SIZE):
            alpha = round(255 * coverage(px, py, inside))
            pixels += bytes((255, 255, 255, alpha))  # BGRA
    path.write_bytes(header + bytes(pixels))
    print(f"Wrote {path.relative_to(MEDIA.parent)}")


write_tga(MEDIA / "RoundedFill.tga", lambda d: d <= 0)
write_tga(MEDIA / "RoundedBorder.tga", lambda d: -BORDER <= d <= 0)
