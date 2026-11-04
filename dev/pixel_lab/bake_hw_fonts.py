"""Bake BMFont copies of the glyph sheets `mkbcfnt` produces for the 3DS build.

Pixel Lab draws text from these instead of letting desktop LÖVE rasterise the .ttf, because
the two disagree exactly where it matters: mkbcfnt asks FreeType for `-s <pt>` at 96 dpi
(`tex3ds/source/freetype.cpp`, FT_Set_Char_Size(pt * 64, 0, 96, 0)), renders with
FT_LOAD_RENDER (hinted, 8-bit coverage), and stores the coverage as 4-bit alpha
(`bcfnt.cpp`, A4 sheets). Desktop LÖVE asks for a whole pixel em. Reproducing the FreeType
call reproduces the sheet's pixels.

Metrics follow `bcfnt.cpp` too. The BMFont lineHeight is the cell height, because that is what
the CTR rasterizer reports as the font's height and advances lines by. Further: left = horiBearingX >> 6, advance = horiAdvance >> 6, the cell
baseline is the tallest bitmap_top, and the cell height is that minus the deepest descent.

    python dev/pixel_lab/bake_hw_fonts.py <font.ttf> <out_dir> <cell:pt> [<cell:pt> ...]

Writes `<out_dir>/hw_h<cell>.fnt` + `.png` per sheet, and `hw_fonts.txt` listing them.
"""
import sys
from pathlib import Path

import freetype
from PIL import Image


def bake(ttf, pt, out_png, out_fnt, page_name):
    face = freetype.Face(str(ttf))
    face.select_charmap(freetype.FT_ENCODING_UNICODE)
    face.set_char_size(int(pt * 64), 0, 96, 0)
    line_feed = face.size.height >> 6

    glyphs = []
    code, index = face.get_first_char()
    while index:
        if code < 0xFFFF:
            face.load_glyph(index, freetype.FT_LOAD_RENDER)
            g = face.glyph
            bm = g.bitmap
            w, h = bm.width, bm.rows
            buf = bytes(bm.buffer)
            pitch = bm.pitch
            # A4 storage: keep the top four bits of coverage, expanded back to 8.
            alpha = bytearray(w * h)
            for y in range(h):
                for x in range(w):
                    v = buf[y * pitch + x] >> 4
                    alpha[y * w + x] = v * 17
            glyphs.append(dict(
                code=code, w=w, h=h, alpha=bytes(alpha), top=g.bitmap_top,
                left=g.metrics.horiBearingX >> 6, adv=g.metrics.horiAdvance >> 6,
            ))
        code, index = face.get_next_char(code, index)

    ascent = max([g["top"] for g in glyphs if g["h"]] + [face.size.ascender >> 6])
    descent = min([g["top"] - g["h"] for g in glyphs if g["h"]] + [face.size.descender >> 6])
    cell_h = ascent - descent

    # Shelf-pack into one page with a 1 px gutter (linear sampling must not bleed).
    page_w = 512
    x = y = 1
    row_h = 0
    for g in glyphs:
        if x + g["w"] + 1 > page_w:
            x, y = 1, y + row_h + 1
            row_h = 0
        g["px"], g["py"] = x, y
        x += g["w"] + 1
        row_h = max(row_h, g["h"])
    page_h = 1
    while page_h < y + row_h + 1:
        page_h *= 2

    img = Image.new("RGBA", (page_w, page_h), (255, 255, 255, 0))
    for g in glyphs:
        if g["w"] and g["h"]:
            a = Image.frombytes("L", (g["w"], g["h"]), g["alpha"])
            white = Image.new("RGBA", (g["w"], g["h"]), (255, 255, 255, 255))
            white.putalpha(a)
            img.paste(white, (g["px"], g["py"]))
    img.save(out_png)

    lines = [
        f'info face="m6x11plus_hw" size={cell_h} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1',
        f"common lineHeight={cell_h} base={ascent} scaleW={page_w} scaleH={page_h} pages=1 packed=0",
        f'page id=0 file="{page_name}"',
        f"chars count={len(glyphs)}",
    ]
    for g in glyphs:
        lines.append(
            f'char id={g["code"]} x={g["px"]} y={g["py"]} width={g["w"]} height={g["h"]} '
            f'xoffset={g["left"]} yoffset={ascent - g["top"]} xadvance={g["adv"]} page=0 chnl=15'
        )
    Path(out_fnt).write_text("\n".join(lines) + "\n")
    return cell_h, line_feed, ascent


def main(argv):
    ttf, out_dir, sheets = Path(argv[1]), Path(argv[2]), argv[3:]
    out_dir.mkdir(parents=True, exist_ok=True)
    listing = []
    for spec in sheets:
        cell, pt = spec.split(":")
        name = f"hw_h{cell}"
        produced, line_feed, base = bake(ttf, float(pt), out_dir / f"{name}.png",
                                         out_dir / f"{name}.fnt", f"{name}.png")
        if produced != int(cell):
            print(f"warning: -s {pt} gives a {produced}px cell here, config says {cell}", file=sys.stderr)
        listing.append(f"{cell} {pt} {produced} {line_feed} {base}")
        print(f"h{cell}: pt {pt} em {float(pt) * 96 / 72:.2f}px cell {produced} lineFeed {line_feed} base {base}")
    (out_dir / "hw_fonts.txt").write_text("\n".join(listing) + "\n")


if __name__ == "__main__":
    main(sys.argv)
