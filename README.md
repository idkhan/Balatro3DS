# Balatro for Nintendo 3DS

Forked from [a project by idkhan,](https://github.com/idkhan/Balatro3DS) this port of Balatro for Nintendo 3DS targets extreme accuracy to the original game.

It runs on [LövePotion](https://github.com/lovebrew/lovepotion), TurtleP's implementation of the LÖVE API for homebrew consoles.

## Installation

The easiest way to install is using FBI. Open the [releases page](https://github.com/rosematcha/Balatro3DS/releases) and scan the QR code using FBI's "Remote Install" feature.

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

**This port has only been tested for performance on a New 3DS,** as I do not have physical access to an original 3DS. Acceptable performance is presently not guaranteed on original 3DS models.

A few things are deliberately turned down or off on an original 3DS, which has a much less powerful CPU. The animated menu backdrop doesn't run at all, and some particle effects draw on a coarser grid.

## Building it yourself

`./dev/setup.sh` fetches devkitPro's 3DS packages, builds a patched LövePotion runtime, and pulls down the host tools it needs. `./dev/build.sh` then produces a CIA, or `./dev/build.sh 3dsx` a fused `.3dsx`; output lands in `dev/dist/`. [BUILD.md](BUILD.md) covers the older manual `.3dsx` recipe, which is aimed at end users rather than development.

Tests run headless under LuaJIT with `./tests/run.sh` — no console or LÖVE binary needed.

## License

This project is provided as-is for educational and fan purposes. Check the repository license file for details before redistribution.