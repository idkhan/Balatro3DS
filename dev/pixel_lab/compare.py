"""Labelled before/after proof sheets from two Pixel Lab capture directories.

    python dev/pixel_lab/compare.py <before_dir> <after_dir> <out.png> --title "..." \
        --shot 05_hand --shot 05_hand:top:250,20,150,70 [--note "..."]

Each --shot is one row: BEFORE | AFTER | CHANGED. A shot is `capture[:screen[:x,y,w,h]]`, where
screen is `top`, `bottom` or `both` (default) and the box is in native screen pixels. A whole
screen is drawn at 2x, a cropped box is zoomed until it is about 360 px wide, always by a whole
factor and nearest-neighbour, so one console pixel is always a clean square on the sheet.

CHANGED is the before image dimmed, with every pixel that differs in the after image painted
magenta, so a reviewer can see at a glance that a fix touched only what it says it touched.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

BG = (24, 24, 24)
FG = (235, 235, 235)
DIM = (150, 150, 150)
GAP = 10
LABEL_H = 16


def load(d, capture, screen):
    suffix = {"both": "", "top": "_top", "bottom": "_bottom"}[screen]
    path = Path(d) / f"{capture}{suffix}.png"
    if not path.exists():
        raise SystemExit(f"missing capture: {path}")
    return Image.open(path).convert("RGB")


def parse_shot(spec):
    parts = spec.split(":")
    capture = parts[0]
    screen = parts[1] if len(parts) > 1 and parts[1] else "both"
    box = None
    if len(parts) > 2:
        x, y, w, h = (int(v) for v in parts[2].split(","))
        box = (x, y, x + w, y + h)
    if screen not in ("both", "top", "bottom"):
        raise SystemExit(f"bad screen in shot {spec!r}")
    return capture, screen, box


def changed(before, after):
    diff = ImageChops.difference(before, after).convert("L").point(lambda v: 255 if v else 0)
    out = Image.blend(before, Image.new("RGB", before.size, (0, 0, 0)), 0.6)
    out.paste((255, 0, 255), mask=diff)
    return out, diff.getbbox() is not None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before")
    ap.add_argument("after")
    ap.add_argument("out")
    ap.add_argument("--title", required=True)
    ap.add_argument("--note", action="append", default=[])
    ap.add_argument("--shot", action="append", required=True)
    a = ap.parse_args()

    rows = []
    for spec in a.shot:
        capture, screen, box = parse_shot(spec)
        b, f = load(a.before, capture, screen), load(a.after, capture, screen)
        if box:
            b, f = b.crop(box), f.crop(box)
            zoom = max(2, min(8, 360 // b.width))
        else:
            zoom = 2
        c, any_change = changed(b, f)
        size = (b.width * zoom, b.height * zoom)
        tiles = [im.resize(size, Image.NEAREST) for im in (b, f, c)]
        where = f"{screen}" + (f" x={box[0]} y={box[1]} {box[2]-box[0]}x{box[3]-box[1]}" if box else "")
        caption = f"{capture}  [{where}]  {zoom}x" + ("" if any_change else "  (no pixel changed)")
        rows.append((caption, tiles))

    width = max(3 * t[0].width + 4 * GAP for _, t in rows)
    header_h = 28 + 16 * len(a.note)
    height = header_h + sum(LABEL_H * 2 + t[0].height + GAP for _, t in rows) + GAP
    sheet = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(sheet)
    d.text((GAP, 8), a.title, fill=FG)
    for i, n in enumerate(a.note):
        d.text((GAP, 26 + 16 * i), n, fill=DIM)
    y = header_h
    for caption, tiles in rows:
        d.text((GAP, y), caption, fill=FG)
        y += LABEL_H
        x = GAP
        for label, t in zip(("BEFORE", "AFTER", "CHANGED (magenta)"), tiles):
            d.text((x, y), label, fill=DIM)
            sheet.paste(t, (x, y + LABEL_H))
            x += t.width + GAP
        y += LABEL_H + tiles[0].height + GAP
    sheet.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
