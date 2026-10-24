# Balatro for Nintendo 3DS

**English** | [简体中文](README.zh-CN.md)

The poker roguelike. Balatro is a hypnotically satisfying deckbuilder where you play illegal poker hands, discover game-changing jokers, and trigger adrenaline-pumping, outrageous combos, now on the 3DS.

This is a fan-made remake of Balatro. This project is in no way affiliated with LocalThunk, the creator of Balatro. All art and sound effects are originally from the game, only adapted to run on the 3DS hardware. If you want to support the creator or get the full Balatro experience, please buy the game.

It runs on [LövePotion](https://github.com/lovebrew/lovepotion), TurtleP's implementation of the LÖVE API for homebrew consoles.

## Installation

The easiest way to install is using FBI. Open the [releases page](https://github.com/idkhan/Balatro3DS/releases) and scan the QR code using FBI's "Remote Install" feature.

The CIA is unsigned, so installing it needs custom firmware with sigpatches. If you'd rather not install a title, the releases page also carries a `.3dsx`: drop it in the `3ds` folder at the root of your SD card and launch it from the Homebrew Launcher.

## Controls

The bottom screen is the playfield and the only touch surface; the top screen is a readout. You can play entirely with buttons, entirely by touch, or mix the two.

The face buttons follow the layout Balatro ships on the Switch, since the 3DS has the same ABXY arrangement:

- **A** — select. Hold and press the D-pad to reorder.
- **B** — deselect, sell, or (with nothing selected) sort. Hold and press the D-pad to sweep.
- **X** — discard, or reroll in the shop.
- **Y** — play, or buy and use in the shop.
- **L / R** — toggle the jokers and consumables panels.

All six are rebindable from Options, and on a New 3DS you can bind ZL and ZR as well.

## Performance notes

**This port has been tested on both a New 3DS and Old 3DS**

A few things are deliberately turned down or off on an original 3DS, which has a much less powerful CPU. Some particle effects draw on a coarser grid.

## Modding

The game loads mods written in the [Steamodded](https://github.com/Steamodded/smods) style: a folder with a `.json` manifest and a Lua file that calls `SMODS.Joker { ... }` and friends. Mods can add Jokers, Tarots, Planets, Spectrals, Vouchers, Decks, Editions, and sets of face-card art for **Options → Art**.

To install a mod, copy its folder into the `mods` folder the game creates next to its save files on the SD card (`/3ds/save/Balatro3DS/sdmc/mods`), then restart. **Options → Mods** lists what loaded, and why anything didn't.

A saved run remembers which mods it was played with. If those mods change, Continue shows what to install or remove; the run itself is kept.

This isn't Steamodded itself. There's no Lovely, the PC game's internals aren't there, and the 3DS can't run shaders. Every card is its own `.t3x` image, and a Negative card needs its own art. [MODDING.md](MODDING.md) covers the full API, [`dev/example_mods/ExampleJokers`](dev/example_mods/ExampleJokers) is a working example, and `dev/make_negative.py` turns a card's image into its Negative version.

## Building it yourself

`./dev/setup.sh` fetches devkitPro's 3DS packages, builds a patched LövePotion runtime, and pulls down the host tools it needs. `./dev/build.sh` then produces a CIA, or `./dev/build.sh 3dsx` a fused `.3dsx`; output lands in `dev/dist/`. [BUILD.md](BUILD.md) covers the older manual `.3dsx` recipe, which is aimed at end users rather than development.

Tests run headless under LuaJIT with `./tests/run.sh` — no console or LÖVE binary needed.

## License

This project is provided as-is for educational and fan purposes. Check the repository license file for details before redistribution.