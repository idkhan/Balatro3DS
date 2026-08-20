#!/usr/bin/env python3
"""Bake the foil and holo edition pattern sheets.

The reference game draws editions with fragment shaders. The PICA200 has no
programmable fragment stage, so `fx.lua` re-expresses them as a textured mesh with
Gouraud vertex colours plus one additive pass. Vertex colours can carry a card-wide
colour ramp but nothing spatial: foil's concentric rings and holo's triangular lattice
need per-pixel detail, and the only way to get per-pixel detail without a shader is to
ship it as a texture.

So this bakes the *structure* — the pattern's intensity, in the alpha channel, white in
RGB — and leaves the *colour* to the vertex field at runtime. That keeps the draw-call
count identical to the flat version; only the sampled texture changes.

Two things are baked in per pattern because they cannot be recovered at runtime:

  * The card silhouette. There is no stencil on ctr and only one texture unit is bound
    per draw, so an additive overlay cannot be masked against a second texture. The mask
    is therefore taken from the real art's alpha, once per card size — playing cards are
    72x95 cells of `Enhancers.png`, Joker sprites are 70x94 standalone PNGs, and their
    silhouettes are not the same shape, so each gets its own bake.

  * Foil's animation phases. `card.lua:4349` drives the reference's ring phase from card
    rotation, juice and tilt plus a very slow clock, so the phase is an input, not a
    frame counter; the baked phases are indexed by it at runtime. Six of them, in three
    columns, because that is what keeps the sheet inside a 256x512 t3x — four columns
    would pad to 512x512 and double the cost for two more phases.

Run from the repo root:  python3 dev/bake_edition_patterns.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_io import read_rgba, write_rgba  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(REPO, "resources", "textures", "1x")
OUT = os.path.join(TEX, "editions")

FOIL_PHASES = 6
FOIL_COLS = 3

TWO_PI = math.pi * 2


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else (hi if x > hi else x)


# --- masks ---------------------------------------------------------------------------
# (name, source png, cell rect, cell size). The rect is declared, never derived from the
# image's dimensions -- see CLAUDE.md on why dividing by getDimensions is a trap here.
MASKS = [
    ("card", "Enhancers.png", (0, 0), (72, 95)),
    ("joker", os.path.join("Jokers", "Jokers1_1.png"), (0, 0), (70, 94)),
]


def load_mask(source, origin, size):
    """Alpha channel of one card-shaped cell, as a list of floats."""
    w, _h, rgba = read_rgba(os.path.join(TEX, source))
    ox, oy = origin
    cw, ch = size
    return [rgba[((oy + y) * w + (ox + x)) * 4 + 3] / 255.0 for y in range(ch) for x in range(cw)]


# --- patterns ------------------------------------------------------------------------
def foil_rings(u, v, aspect, phase):
    """`foil.fs:109-116`: concentric rings modulated by a second, faster ring set, plus a
    rotating angular sweep.

    Three constants are retuned so the phase loops seamlessly over [0, 2pi): the inner
    ring frequency 3.121 -> 3.0, and the sweep's rotater rates 0.1221/0.3512 -> 1/2. The
    reference never loops (its phase is an ever-growing sum), but a baked sheet has to,
    and at 240p the retune is not visible.
    """
    ax = (u - 0.5) * aspect
    ay = v - 0.5
    length = math.hypot(ax, ay)

    fac = clamp(
        2 * math.sin(90 * length + phase * 2 + 3 * (1 + 0.8 * math.cos(113.1121 * length - phase * 3)))
        - 1
        - max(5 - 90 * length, 0)
    )

    rx, ry = math.cos(phase), math.sin(phase * 2)
    denom = math.hypot(rx, ry) * (length or 1e-6)
    angle = (rx * ax + ry * ay) / denom
    fac2 = clamp(
        5 * math.cos(math.cos(phase) + angle * math.pi * (2.2 + 0.9 * math.sin(phase)))
        - 4
        - max(2 - 20 * length, 0)
    )

    return clamp((max(fac, fac2) + 2.2 * (fac + fac2)) * 0.30)


def holo_lattice(u, v, _aspect, _phase):
    """`holo.fs:120`: one vertical grid and two diagonals, which read as a triangular
    prism lattice. Static -- the reference animates holo's hue, not its lattice."""
    g = 0.79
    a = max(0.0, 7 * abs(math.cos(u * g * 20)) - 6)
    b = max(0.0, 7 * math.cos(v * g * 45 + u * g * 20) - 6)
    c = max(0.0, 7 * math.cos(v * g * 45 - u * g * 20) - 6)
    return clamp(max(a, b, c))


def render_cell(fn, mask, size, phase):
    """One cell: white, alpha = pattern intensity clipped to the card silhouette."""
    cw, ch = size
    aspect = cw / float(ch)
    cell = bytearray(cw * ch * 4)
    for y in range(ch):
        v = (y + 0.5) / ch
        for x in range(cw):
            u = (x + 0.5) / cw
            a = fn(u, v, aspect, phase) * mask[y * cw + x]
            k = (y * cw + x) * 4
            cell[k] = cell[k + 1] = cell[k + 2] = 255
            cell[k + 3] = int(round(clamp(a) * 255))
    return cell


def blit(dst, dst_w, cell, size, at):
    cw, ch = size
    ax, ay = at
    for y in range(ch):
        src = y * cw * 4
        dst_off = ((ay + y) * dst_w + ax) * 4
        dst[dst_off : dst_off + cw * 4] = cell[src : src + cw * 4]


def bake(name, fn, phases, cols):
    """Lay every silhouette's phase grid into one sheet and report the geometry, which
    the Lua side declares rather than derives."""
    blocks = []
    y_cursor = 0
    width = 0
    for mask_name, source, origin, size in MASKS:
        cw, ch = size
        rows = (phases + cols - 1) // cols
        width = max(width, min(phases, cols) * cw)
        blocks.append((mask_name, source, origin, size, y_cursor, rows))
        y_cursor += rows * ch
    height = y_cursor

    sheet = bytearray(width * height * 4)
    geometry = []
    for mask_name, source, origin, size, y0, rows in blocks:
        cw, ch = size
        mask = load_mask(source, origin, size)
        for i in range(phases):
            phase = (i / float(phases)) * TWO_PI
            cell = render_cell(fn, mask, size, phase)
            blit(sheet, width, cell, size, ((i % cols) * cw, y0 + (i // cols) * ch))
        geometry.append((mask_name, cw, ch, 0, y0, cols))

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".png")
    write_rgba(path, width, height, sheet)

    print("%s: %dx%d, %d phases" % (os.path.relpath(path, REPO), width, height, phases))
    for mask_name, cw, ch, x0, y0, c in geometry:
        print("    %-6s cell %dx%d at (%d,%d), %d per row" % (mask_name, cw, ch, x0, y0, c))
    return width, height


def next_pow2(n):
    p = 8
    while p < n:
        p *= 2
    return p


def main():
    total = 0
    for name, fn, phases, cols in (
        ("foil", foil_rings, FOIL_PHASES, FOIL_COLS),
        ("holo", holo_lattice, 1, 1),
    ):
        w, h = bake(name, fn, phases, cols)
        pw, ph = next_pow2(w), next_pow2(h)
        cost = pw * ph * 4
        total += cost
        print("    t3x pads to %dx%d = %d KB RGBA8 in the linear heap" % (pw, ph, cost // 1024))
    print("total %d KB, lazy-loaded" % (total // 1024))


if __name__ == "__main__":
    main()
