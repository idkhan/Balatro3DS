#!/usr/bin/env python3
"""Bake the 12 px controller-button pip sheet the game draws 1:1.

The source strip (`dev/source_art/gamepad_ui_3ds_opt_1x.png`, twenty 32x34 cells) is the
reference game's button art. Every prompt in the port draws a pip 11-14 px tall, and the game
used to scale the 32 px cells down at draw time. Textures are nearest-filtered, so at 0.375 the
sampler keeps three source pixels in eight and drops the rest: B read as D, L as an underscore.

A runtime linear filter would not rescue it either. Without mipmaps the PICA200 still reads only
the four nearest texels per screen pixel. So the downscale is done here, once, with a proper
filter, and the game draws the result at scale 1. The sheet is also 1/16 of the texture memory.

Run from the repo root:  python3 dev/bake_button_pips.py
"""
from pathlib import Path

from PIL import Image

SRC = Path("dev/source_art/gamepad_ui_3ds_opt_1x.png")
OUT = Path("resources/textures/gamepad_ui_3ds_12px.png")
SRC_W, SRC_H, CELLS = 32, 34, 20
# 32x34 scaled to 12 px wide keeps the source's aspect: 12.75, rounded up so nothing is cropped.
CELL_W, CELL_H = 12, 13


def main():
    src = Image.open(SRC).convert("RGBA")
    if src.size != (SRC_W * CELLS, SRC_H):
        raise SystemExit(f"{SRC}: expected {SRC_W * CELLS}x{SRC_H}, got {src.size}")
    out = Image.new("RGBA", (CELL_W * CELLS, CELL_H), (0, 0, 0, 0))
    for i in range(CELLS):
        cell = src.crop((i * SRC_W, 0, (i + 1) * SRC_W, SRC_H))
        # Pillow premultiplies RGBA for resampling, so transparent pixels do not bleed colour.
        out.paste(cell.resize((CELL_W, CELL_H), Image.LANCZOS), (i * CELL_W, 0))
    out.save(OUT, optimize=True)
    print(f"{OUT}: {out.size[0]}x{out.size[1]}, {CELLS} cells of {CELL_W}x{CELL_H}")


if __name__ == "__main__":
    main()
