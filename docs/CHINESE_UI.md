# Simplified Chinese UI and font updates

The Chinese catalog names were compared with `localization/zh_CN.lua` in a locally installed Steam copy of Balatro. This revision corrects 93 names from the 2.0.3 translation; all 327 audited names match that reference. The game archive and original localization files are not included in this contribution.

Descriptions retain stable card IDs and existing structured color segments. Corrections include free edition tags, Double Tag's exclusion, Ancient Joker's changing suit, and Ectoplasm's cumulative hand-size penalty.

## Fonts

`resources/fonts/zh_CN.ttf` is a renamed subset of the Noto Sans SC Bold font already in this repository. `dev/build_zh_font.py` collects the Chinese strings plus printable ASCII, normalizes line metrics and tall outline outliers, and regenerates the subset. The source copyright and SIL Open Font License are in `resources/fonts/OFL-zh_CN.txt`.

The native build uses five exact cell heights: 13, 17, 21, 27 and 33 px. `dev/build.sh` generates the corresponding BCFNT sheets; compiled sheets are not checked into this PR. Preserved hinting, quarter-point baking and normalized FINF metrics keep the runtime's requested size consistent with the baked cells. Equal-size roles share a font object.

Regenerate the desktop subset after changing Chinese strings:

```sh
python3 dev/build_zh_font.py
```

This needs `fonttools`; native sheet generation additionally needs `mkbcfnt` through the normal build workflow. The current subset covers 967 characters.

## Layout and input

The patch fits HUD counters on one line, gives Boss descriptions separate space from the target, measures wrapped blind text, keeps CJK punctuation with its neighbours, and preserves discovery notifications in the original upper-screen popup. It also fits menu labels and improves deck-footer placement.

Blind buttons display the current confirm/cancel bindings. Shop exit displays the cancel binding and a hold hint, works from shop focus, and remains protected while dragging or sweep-selecting. The existing upstream check that a hold must begin in the shop is preserved, so skipping a booster cannot also leave the shop.

## Notifications and rewards

The earlier revision moved discovery notifications to a footer to avoid covering the upper-screen score, chips and multiplier. In response to review, the original popup position, dimensions, border, shadow and slide animation have been restored. Chinese text still uses this contribution's font and translations. The popup keeps the original Chinese layout dimensions independently of the normalized font metrics.

Reward previews and blind commitment now share the existing stake, challenge and Boss payout rules. Reward symbols use one `$` per dollar, without an extra currency prefix; zero blind reward displays `$0`. Their previous font size and normal fit-to-width behavior are retained.

## Validation

Run the normal headless suite with `./tests/run.sh`. New cases cover Chinese font sharing, remapped prompts, single-line HUD readouts, punctuation, shop exit gestures, original notification geometry and accurate reward previews. The latest clean-source run passed 1080 cases, skipped 2 cases that require a patched LovePotion checkout, and had no failures.

To compare names and placeholders against your own installed game:

```sh
python3 dev/audit_zh_translation.py --official-game /path/to/Balatro.exe
```

The audit requires `lupa` and reads the game's localization locally. It reports differences and returns nonzero for missing keys, name mismatches, or placeholder mismatches. Its default output is `dev/.cache/zh-audit/`.

Desktop dual-screen checks covered 84 blind-selection layouts, all 28 Boss HUDs, and eight scenes. Native sheet maps, baselines and locale coverage were also checked. **The earlier maintenance build was tested on a Japanese-region New Nintendo 3DS running Luma3DS 13.4. The latest notification-restoration and reward-preview changes have not yet been tested on hardware. Other models and region variants remain untested.** This does not establish exhaustive coverage of font clarity, memory use, layouts or gameplay; desktop previews do not extend the hardware coverage.
