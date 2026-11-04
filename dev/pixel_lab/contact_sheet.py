"""Tile Pixel Lab captures into one labelled sheet, nearest-neighbour scaled.

    python dev/pixel_lab/contact_sheet.py <capture_dir> <out.png> [--scale 2] [--cols 4] [names...]

With no names, every still (captures without an `_fNN` burst suffix) is used.
"""
import argparse
import re
from pathlib import Path

from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("out")
    ap.add_argument("names", nargs="*")
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--cols", type=int, default=4)
    a = ap.parse_args()
    d = Path(a.dir)
    names = a.names or [n for n in (d / "captures.txt").read_text().split() if not re.search(r"_f\d+$", n)]
    tiles = [(n, Image.open(d / f"{n}.png").convert("RGB")) for n in names]
    w, h = tiles[0][1].size
    w, h = w * a.scale, h * a.scale
    label = 18
    cols = min(a.cols, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (w + 8) + 8, rows * (h + label + 8) + 8), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(tiles):
        x = 8 + (i % cols) * (w + 8)
        y = 8 + (i // cols) * (h + label + 8)
        draw.text((x, y + 2), n, fill=(230, 230, 230))
        sheet.paste(im.resize((w, h), Image.NEAREST), (x, y + label))
    sheet.save(a.out)


if __name__ == "__main__":
    main()
