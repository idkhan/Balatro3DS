#!/usr/bin/env python3
"""Bake a language's font sheets for the 3DS.

A CJK font cannot ship whole: `mkbcfnt` rasterises every glyph in a face, a full CJK face holds
tens of thousands, and the result is hundreds of megabytes (or a crash). The game only ever draws
the characters its strings contain -- under a thousand for the Chinese translation -- so this
cuts the font down to exactly those, then bakes one `.bcfnt` per cell height, the same way
`dev/build.sh` bakes the per-size m6x11plus sheets. `fonts.lua` (LANGUAGE_FACES) loads them.

    python3 dev/bake_cjk_font.py --font resources/fonts/GoNotoCJKCore.ttf \\
        --strings locales/zh_CN.lua locales/content/zh_CN \\
        --heights 13 18 22 27 33 --out "build/fonts/zh_CN_h%d.bcfnt" --cache dev/.cache/assets

Characters come from every given string file (and every `.lua` under a given directory), plus
printable ASCII, which the translations mix in for numbers and symbols. `mkbcfnt` takes a point
size, not a cell height, and the two do not map one to one, so each height is searched for.
Results are cached by the font, the character set and the height, so an unchanged language costs
nothing on the next build.

Needs fontTools (`python3 -m pip install fonttools`) and devkitPro's mkbcfnt.
"""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
from bcfnt import normalize_metrics


def collect_characters(paths):
    chars = set(chr(c) for c in range(0x20, 0x7F))
    files = []
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                files += [os.path.join(root, n) for n in sorted(names) if n.endswith(".lua")]
        else:
            files.append(path)
    for path in files:
        with open(path, encoding="utf-8") as fp:
            chars.update(fp.read())
    return sorted(c for c in chars if c.isprintable() and c not in "\r\n\t")


def subset_font(font_path, chars, out_path):
    from fontTools import subset

    options = subset.Options()
    options.hinting = True   # retain the prepared face's pixel-grid metrics
    options.layout_features = []      # mkbcfnt draws glyphs one at a time; no shaping
    options.notdef_outline = True
    options.name_IDs = ["*"]
    # mkbcfnt sizes every cell from the font's bounding box; a cut-down font still carrying the
    # full font's box gets cells twice as wide as any glyph it kept.
    options.recalc_bounds = True
    font = subset.load_font(font_path, options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=[ord(c) for c in chars])
    subsetter.subset(font)
    subset.save_font(font, out_path, options)


def cell_height(bcfnt_path):
    """TGLP block: cellWidth, then cellHeight, 8 bytes past the block magic (as build.sh reads it)."""
    with open(bcfnt_path, "rb") as fp:
        data = fp.read()
    index = data.find(b"TGLP")
    return data[index + 9] if index >= 0 else -1


def bake_height(mkbcfnt, ttf, target, out_path):
    """Find the point size whose sheet has exactly `target` px cells. Returns the cell height
    actually produced (the closest at or below target when no point size hits it exactly)."""
    best = None
    with tempfile.TemporaryDirectory() as tmp:
        trial = os.path.join(tmp, "trial.bcfnt")
        # Cell height grows with point size and lands near 1.5x it for these faces; walk the
        # plausible range rather than trusting the ratio.
        for quarter in range(4 * max(4, target // 3), 4 * (target + 2)):
            size = quarter / 4
            subprocess.run([mkbcfnt, ttf, "-s", str(size), "-o", trial], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            h = cell_height(trial)
            if h == target:
                shutil.copyfile(trial, out_path)
                return h
            if h < target and (best is None or h > best[0]):
                best = (h, size)
                shutil.copyfile(trial, out_path + ".best")
            if h > target:
                break
    if best is None:
        raise SystemExit(f"bake_cjk_font: no point size gives a cell of {target}px or less")
    os.replace(out_path + ".best", out_path)
    return best[0]


def bake_height_exact(mkbcfnt, ttf, target, out_path):
    produced = bake_height(mkbcfnt, ttf, target, out_path)
    if produced != target:
        raise SystemExit(f"bake_cjk_font: expected {target}px cells, got {produced}px; refusing a mismatched native sheet")
    if os.path.exists(out_path + ".best"):
        os.remove(out_path + ".best")
    normalize_metrics(out_path)
    return produced


def main(argv):
    parser = argparse.ArgumentParser(description="Bake a language's font sheets for the 3DS.")
    parser.add_argument("--font", required=True, help="source .ttf/.otf")
    parser.add_argument("--strings", nargs="+", required=True, help="string files or directories")
    parser.add_argument("--heights", nargs="+", type=int, required=True, help="cell heights to bake")
    parser.add_argument("--out", required=True, help="output path with %%d for the cell height")
    parser.add_argument("--cache", help="directory to cache baked sheets in")
    parser.add_argument("--mkbcfnt", default=shutil.which("mkbcfnt") or "mkbcfnt")
    args = parser.parse_args(argv[1:])

    chars = collect_characters(args.strings)
    with open(args.font, "rb") as fp:
        font_hash = hashlib.sha1(fp.read()).hexdigest()
    key = hashlib.sha1(("hinted-finf-v1:" + font_hash + "".join(chars)).encode("utf-8")).hexdigest()[:16]

    with tempfile.TemporaryDirectory() as tmp:
        subset_path = None
        for target in args.heights:
            out = args.out % target
            os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
            cached = args.cache and os.path.join(args.cache, f"cjk_{key}_h{target}.bcfnt")
            if cached and os.path.exists(cached):
                shutil.copyfile(cached, out)
                continue
            if subset_path is None:
                subset_path = os.path.join(tmp, "subset.ttf")
                subset_font(args.font, chars, subset_path)
            produced = bake_height_exact(args.mkbcfnt, subset_path, target, out)
            if produced != target:
                print(f"bake_cjk_font: warning: {target}px cell not reachable; baked {produced}px",
                      file=sys.stderr)
            if cached:
                os.makedirs(args.cache, exist_ok=True)
                shutil.copyfile(out, cached)
        print(f"baked {len(args.heights)} sheets, {len(chars)} characters, from {os.path.basename(args.font)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
