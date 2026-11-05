#!/usr/bin/env python3
"""Bake the 12 px controller-button pip sheet the game draws 1:1.

The source strip (`dev/source_art/gamepad_ui_3ds_opt_1x.png`, twenty 32x34 cells) is the
reference game's button art: a 2-3 px dark ring, a highlight and a shadow rim, and a letter
drawn with 3 px strokes. Every prompt in the port draws a pip 11-14 px tall, which is 0.375 of
the source. No filter survives that:

- Nearest (the old runtime scale) keeps three source pixels in eight. B reads as D, L as a dash.
- Lanczos keeps every stroke as a 1.1 px smear: blurry letters and no ring.

So the six pips the game can show (A, B, X, Y, L, R; see InputBindings.REBINDABLE_BUTTONS) are
drawn here by hand at 12 px, one pixel per stroke, in the source's own colours. The other cells
keep their slots so the sheet's indices match the reference game; they are never drawn, and are
left as a nearest downscale.

Run from the repo root:  python3 dev/bake_button_pips.py
"""
from pathlib import Path

from PIL import Image

SRC = Path("dev/source_art/gamepad_ui_3ds_opt_1x.png")
OUT = Path("resources/textures/gamepad_ui_3ds_12px.png")
SRC_W, SRC_H, CELLS = 32, 34, 20
# 32x34 at 12 px wide keeps the source's aspect: 12.75, rounded up so nothing is cropped.
CELL_W, CELL_H = 12, 13

# O ring, H highlight rim, F fill, S shadow rim, W letter, . clear. One row per pixel row.
FACE = [
    "....OOOO....",
    "..OOHHHHOO..",
    ".OHHFFFFHHO.",
    ".OHFFFFFFHO.",
    "OHFFFFFFFFHO",
    "OHFFFFFFFFHO",
    "OSFFFFFFFFSO",
    "OSFFFFFFFFSO",
    ".OSFFFFFFSO.",
    ".OSSFFFFSSO.",
    "..OOSSSSOO..",
    "....OOOO....",
    "............",
]
SHOULDER_L = [
    "............",
    "............",
    "OOOOOOOOOO..",
    "OHHHHHHHHHO.",
    "OHFFFFFFFFHO",
    "OFFFFFFFFFFO",
    "OFFFFFFFFFFO",
    "OFFFFFFFFFFO",
    "OSFFFFFFFFSO",
    "OSSSSSSSSSSO",
    "OOOOOOOOOOOO",
    "............",
    "............",
]
SHOULDER_R = [row[::-1] for row in SHOULDER_L]

# Letters, 5 rows tall, placed with their top-left at (x, y) on the body.
GLYPHS = {
    "A": [".##.", "#..#", "####", "#..#", "#..#"],
    "B": ["###.", "#..#", "###.", "#..#", "###."],
    "X": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
    "Y": ["#...#", ".#.#.", "..#..", "..#..", "..#.."],
    "L": ["#..", "#..", "#..", "#..", "###"],
    "R": ["###.", "#..#", "###.", "#.#.", "#..#"],
}
# Cell index (InputBindings.BUTTON_SPRITE_INDICES) -> body, letter, letter top-left.
# X and Y are 5 wide on a 12 px face, so they sit half a pixel left of centre.
HAND_DRAWN = {
    0: (FACE, "A", 4, 3),
    1: (FACE, "B", 4, 3),
    2: (FACE, "X", 3, 3),
    3: (FACE, "Y", 3, 3),
    4: (SHOULDER_L, "L", 4, 4),
    5: (SHOULDER_R, "R", 4, 4),
}


def luminance(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def source_palette(cell):
    """The cell's ring, shadow, fill and highlight, darkest first, and its letter colour."""
    colours = {p for p in cell.getdata() if p[3] >= 128}
    letter = max(colours, key=luminance)
    body = sorted(colours - {letter}, key=luminance)
    if len(body) != 4:
        raise SystemExit(f"expected 4 body colours plus a letter, got {len(body)}: {body}")
    ring, shadow, fill, highlight = body
    return {"O": ring, "S": shadow, "F": fill, "H": highlight, "W": letter}


def hand_drawn(cell, body, glyph, gx, gy):
    palette = source_palette(cell)
    out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    px = out.load()
    for y, row in enumerate(body):
        for x, key in enumerate(row):
            if key != ".":
                px[x, y] = palette[key]
    for y, row in enumerate(GLYPHS[glyph]):
        for x, key in enumerate(row):
            if key == "#":
                if body[gy + y][gx + x] in ".O":
                    raise SystemExit(f"{glyph} leaves its body at ({gx + x}, {gy + y})")
                px[gx + x, gy + y] = palette["W"]
    return out


def main():
    for body in (FACE, SHOULDER_L, SHOULDER_R):
        if len(body) != CELL_H or any(len(row) != CELL_W for row in body):
            raise SystemExit("every body template must be CELL_W x CELL_H")
    src = Image.open(SRC).convert("RGBA")
    if src.size != (SRC_W * CELLS, SRC_H):
        raise SystemExit(f"{SRC}: expected {SRC_W * CELLS}x{SRC_H}, got {src.size}")
    out = Image.new("RGBA", (CELL_W * CELLS, CELL_H), (0, 0, 0, 0))
    for i in range(CELLS):
        cell = src.crop((i * SRC_W, 0, (i + 1) * SRC_W, SRC_H))
        if i in HAND_DRAWN:
            out.paste(hand_drawn(cell, *HAND_DRAWN[i]), (i * CELL_W, 0))
        else:
            out.paste(cell.resize((CELL_W, CELL_H), Image.NEAREST), (i * CELL_W, 0))
    out.save(OUT, optimize=True)
    print(f"{OUT}: {out.size[0]}x{out.size[1]}, {CELLS} cells of {CELL_W}x{CELL_H}")


if __name__ == "__main__":
    main()
