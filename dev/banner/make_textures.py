#!/usr/bin/env python3
"""Cut the banner's textures out of the game's own art.

The 3DS wants power-of-two textures, and pycgfx hard-clamps anything over 256px
per axis with a non-aspect-preserving resize, so every sheet here is authored at
its final POT size and never resized downstream. Budget matters: the whole CGFX
must stay under 512 KB and these are stored RGBA8888, so 256x256 costs 256 KB.
Art is scaled with NEAREST because all of it is pixel art.
"""
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(__file__).resolve().parent / "textures"
OUT.mkdir(exist_ok=True)

# The logo: 336x216 into the top 256x165 of a 256x256 sheet. The mesh UVs crop
# to that region, so the unused bottom third costs memory but no pixels on screen.
logo = Image.open(ROOT / "resources/textures/1x/balatro.png").convert("RGBA")
LOGO_W, LOGO_H = 256, round(256 * logo.height / logo.width)  # 256x165
sheet = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
sheet.paste(logo.resize((LOGO_W, LOGO_H), Image.NEAREST), (0, 0))

# Hard alpha. The banner draws this with an alpha test rather than blending, and
# the logo carries a soft white glow stored as pure white RGB at partial alpha —
# under a test, every glow texel that clears the threshold snaps to solid white
# and speckles the edges. Keeping only fully opaque texels drops the glow
# cleanly; every partial-alpha texel in this sheet is glow, never art, so
# nothing else is lost. It also makes what renders here identical to what the
# console draws, whatever cutoff the runtime picks.
sheet.putalpha(sheet.getchannel("A").point(lambda a: 255 if a == 255 else 0))
sheet.save(OUT / "logo.png")

# Cards: 72x95 art centred in a 128x128 sheet at 96x128, i.e. 1.33x/1.35x — near
# enough to uniform that the aspect error is under a pixel at banner scale.
CARD_W, CARD_H = 96, 128


def card(src: Image.Image, name: str) -> None:
    sheet = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    sheet.paste(src.resize((CARD_W, CARD_H), Image.NEAREST), ((128 - CARD_W) // 2, 0))
    sheet.save(OUT / name)


card(Image.open(ROOT / "resources/textures/1x/title_ace.png").convert("RGBA"), "ace.png")

# Red Deck's card back is cell 0 of the `centers` atlas (deck_catalog.lua:4-9,
# game.lua:15110 — 72x95 cells, 10 columns).
centers = Image.open(ROOT / "resources/textures/1x/Enhancers.png").convert("RGBA")
card(centers.crop((0, 0, 72, 95)), "deck_back.png")

# Flat backdrop so the banner reads as the game's menu rather than floating on
# whatever Home Menu theme the user has. Colour sampled from the logo's plate.
Image.new("RGBA", (8, 8), (37, 44, 47, 255)).save(OUT / "backdrop.png")

for p in sorted(OUT.glob("*.png")):
    print(f"{p.name}: {Image.open(p).size}")
