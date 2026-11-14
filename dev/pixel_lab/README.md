# Pixel Lab

Pixel Lab shows the game as the 3DS screens actually show it. It writes both screens out 1:1 from desktop LÖVE: the top screen at 400×240 and the bottom at 320×240. It also lists every draw call that puts pixels where the console can't draw them cleanly.

It is desktop-only. `dev/` is never staged into a console build, and `main.lua` reaches the lab only when `--pixel-lab` is on the command line.

## Run a scenario

```sh
LOVE=/path/to/lovec dev/pixel_lab/run.sh tour --out dev/pixel_lab/out/mine
```

| Flag | Effect |
| --- | --- |
| `--out <dir>` | Where the captures and the audit go. The default is `dev/pixel_lab/out/<scenario>`. |
| `--n3ds` | Use the New 3DS profile. Without it the run is an Old 3DS, which turns some effects down and falls back to the prebaked menu backdrop. |
| `--desktop-fonts` | Draw text with desktop LÖVE's `.ttf` rendering instead of the hardware glyph sheets. |
| `--no-audit` | Skip the draw-call audit. |

On Windows, use `lovec.exe` (the console build) so output reaches the terminal.

Runs are deterministic: every frame is a fixed 1/60 s step, and the save directory is wiped at start. The same scenario gives the same pixels every time, so any difference between two runs comes from the code.

## What it writes

For each capture, the lab writes three images:

- `<name>.png`: both screens laid out as on the console.
- `<name>_top.png`: the top screen.
- `<name>_bottom.png`: the bottom screen.

Each run also writes the audit:

- `audit.txt`: findings grouped by the line that issued the draw.
- `audit.json`: the same findings, for scripts.

The audit's categories are described at the top of `audit.lua`:

- Text off the pixel grid or scaled. Fonts are sampled linearly on hardware, so this text is blurred.
- Nearest-filtered art at a fractional scale, which gives uneven pixels.
- Rectangles and outlines whose edges fall between pixels.
- Anything rotated.

Some of these are intentional. An animation that eases a scale or a position passes through fractional values on purpose, so read the audit as a list of lines to check, not a list of bugs.

## Compare two runs

```sh
python dev/pixel_lab/compare.py <before_dir> <after_dir> out.png --title "What changed" \
    --note "Why" --shot 05_hand:top --shot 05_hand:top:0,0,64,24
```

Each `--shot capture[:top|bottom|both[:x,y,w,h]]` becomes one row: BEFORE | AFTER | CHANGED. The CHANGED column shows the changed pixels in magenta over a dimmed copy of the before image. Whole screens are drawn at 2×. Crops are drawn at the largest whole zoom that fits, so each screen pixel is a crisp square.

## Write a scenario

A scenario is a file in `scenarios/` that returns a function. The lab runs it as a coroutine, one resume per frame. Inside it, `lab` provides:

| Call | Does |
| --- | --- |
| `lab.wait(seconds)` | Lets the game run. |
| `lab.frames(n)` | Lets the game run for `n` frames. |
| `lab.press(button, hold_s)` | Presses a gamepad button through the real input path. |
| `lab.touch(x, y, hold_s)` | Taps the bottom screen. |
| `lab.capture(name)` | Captures both screens of the next frame. |
| `lab.burst(name, n, every)` | Takes `n` captures, `every` frames apart, for animations. |
| `lab.G` | The live game, for setup that has no input path. |

`scenarios/tour.lua` walks from the main menu through a hand, scoring, the shop, a booster, the pause menu, the deck view and run info.

## Fidelity

The lab is close to the console, but not identical:

- **Text matches.** Text is drawn from glyph sheets rasterised the way `mkbcfnt` rasterises them for the console build (`hw_fonts.lua`, `bake_hw_fonts.py`), and sampled linearly as LövePotion samples them.
- **The GPU differs.** The PICA200 is not desktop OpenGL. Rasterisation rules at exact pixel edges and stereo 3D depth are not reproduced, so a fix proven here still needs one look on hardware or in an emulator.

## Pixel rules the game follows

`pixel_grid.lua` holds the rules that keep drawing on the grid:

- `PixelGrid.snap(v)`: rounds a position to the nearest whole pixel.
- `PixelGrid.art_scale(s)`: rounds a layout scale of 1 or more to a whole number. A downscale needs a sheet baked at that size; `dev/bake_button_pips.py` is the example.
- `PixelGrid.at_rest(scale, extent)`: tells whether a scale is too close to 1 to move any pixel. Such a scale is drawn as 1, so a pop's settling tail is drawn without blurring.
- `PixelGrid.outline(x, y, w, h, radius)`: strokes an outline inside its box at any line width.

The rules for text are in `fonts.lua`. `Fonts.ink` gives where the letters sit inside a font's cell. `Fonts.fit_line` steps down the font ladder until a line fits, instead of scaling the text.
