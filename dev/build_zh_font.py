"""Subset the repository's Noto font to the Chinese strings used by this build."""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
ROOT=Path(__file__).resolve().parents[1]
text=''.join(p.read_text(encoding='utf-8-sig') for p in [ROOT/'locales/zh_CN.lua',*ROOT.joinpath('locales/content/zh_CN').glob('*.lua')])
chars=set(text)|set(chr(i) for i in range(32,127))
font=TTFont(ROOT/'resources/fonts/NotoSansSC-Bold.ttf')
missing=chars-set(map(chr,font.getBestCmap()))-{'\t','\r','\n'}
# Non-display characters in comments need not be added, but report them.
options=subset.Options(); options.name_IDs=['*']; options.name_legacy=True; options.name_languages=['*']
# 3DS uses one fixed-width cell for every glyph. Retaining optional ligatures
# and vertical alternates can triple cell width and waste several MiB.
options.layout_features=[]
options.layout_scripts=[]
s=subset.Subsetter(options=options); s.populate(text=''.join(sorted(chars))); s.subset(font)
if missing:
    raise ValueError('Missing source characters: '+repr(''.join(sorted(missing))))
# Keep unusually tall Latin punctuation/accents inside the Chinese em box.
# Otherwise mkbcfnt sizes every cell for those outliers and shrinks all Hanzi.
glyphs=font.getGlyphSet()
replacements={}
for name in font.getGlyphOrder():
    bounds=BoundsPen(glyphs); glyphs[name].draw(bounds)
    if not bounds.bounds: continue
    _,lo,_,hi=bounds.bounds
    if lo >= -120 and hi <= 880: continue
    scale=min(1,1000/(hi-lo))
    shift=max(-120-lo*scale,min(0,880-hi*scale))
    recording=DecomposingRecordingPen(glyphs); glyphs[name].draw(recording)
    pen=TTGlyphPen(None); recording.replay(TransformPen(pen,(1,0,0,scale,0,shift)))
    replacements[name]=pen.glyph()
for name,glyph in replacements.items(): font['glyf'][name]=glyph
# Noto's generous multilingual line metrics overflow the port's 11/22/33px
# UI grid. CJK outlines fit the standard 880/-120 em box without scaling.
units=font['head'].unitsPerEm
font['hhea'].ascent=round(units*0.88); font['hhea'].descent=-round(units*0.12); font['hhea'].lineGap=0
font['OS/2'].sTypoAscender=font['hhea'].ascent; font['OS/2'].sTypoDescender=font['hhea'].descent; font['OS/2'].sTypoLineGap=0
font['OS/2'].usWinAscent=font['hhea'].ascent; font['OS/2'].usWinDescent=-font['hhea'].descent
for rec in font['name'].names:
    if rec.nameID in (1,3,4,6,16):
        rec.string=('Balatro3DS-SC' if rec.nameID==6 else 'Balatro3DS SC').encode(rec.getEncoding())
font.recalcTimestamp=False
font.save(ROOT/'resources/fonts/zh_CN.ttf')
print('Font subset:',len(font.getBestCmap()),'characters;', (ROOT/'resources/fonts/zh_CN.ttf').stat().st_size,'bytes; source-only missing:',repr(''.join(sorted(missing))))
