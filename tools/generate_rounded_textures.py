#!/usr/bin/env python3
"""Writes the rounded-rectangle textures in Media/ used for Lineup's cards and badges.

    python3 tools/generate_rounded_textures.py

All are white (tinted in game with SetVertexColor) and drawn as slices, so the corners keep
their size however big the card is (see ns.CreateRoundedTexture in Core.lua):
  RoundedFill.tga    a filled rounded rectangle
  RoundedBorder.tga  just its outline
  PillFill.tga       a pill (round ends, 14 high) for badges, stretched sideways (see ns.CreateBadge)
  PillBorder.tga     just its outline
"""
import math
import struct
from pathlib import Path

SIZE = 32
RADIUS = 8
BORDER = 1.5
SAMPLES = 4  # per axis, for smooth edges
PILL_WIDTH, PILL_HEIGHT = 28, 14
MEDIA = Path(__file__).resolve().parent.parent / "Media"


def distance_outside(x, y, width, height, radius):
    """Signed distance from the rounded rectangle's edge (negative inside)."""
    cx = min(max(x, radius), width - radius)
    cy = min(max(y, radius), height - radius)
    return math.hypot(x - cx, y - cy) - radius


def coverage(px, py, inside, width, height, radius):
    hits = 0
    for sx in range(SAMPLES):
        for sy in range(SAMPLES):
            x = px + (sx + 0.5) / SAMPLES
            y = py + (sy + 0.5) / SAMPLES
            hits += inside(distance_outside(x, y, width, height, radius))
    return hits / (SAMPLES * SAMPLES)


def write_tga(path, inside, width=SIZE, height=SIZE, radius=RADIUS):
    # Uncompressed 32-bit TGA, rows from the top (descriptor: 8 alpha bits, top-left origin).
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    pixels = bytearray()
    for py in range(height):
        for px in range(width):
            alpha = round(255 * coverage(px, py, inside, width, height, radius))
            pixels += bytes((255, 255, 255, alpha))  # BGRA
    path.write_bytes(header + bytes(pixels))
    print(f"Wrote {path.relative_to(MEDIA.parent)}")


write_tga(MEDIA / "RoundedFill.tga", lambda d: d <= 0)
write_tga(MEDIA / "RoundedBorder.tga", lambda d: -BORDER <= d <= 0)
# Pills: as high as two radii, so the ends are half circles.
write_tga(MEDIA / "PillFill.tga", lambda d: d <= 0, PILL_WIDTH, PILL_HEIGHT, PILL_HEIGHT / 2)
write_tga(MEDIA / "PillBorder.tga", lambda d: -BORDER <= d <= 0, PILL_WIDTH, PILL_HEIGHT, PILL_HEIGHT / 2)
