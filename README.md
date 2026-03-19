## Balatro3DS

Balatro3DS is a fan-made port/implementation of the game Balatro targeting the Nintendo 3DS, built with Lua and LÖVE.

### Requirements

- Lua 5.x
- LÖVE 3.x
- A Nintendo 3DS with homebrew capabilities (for running custom software)

### Getting Started

#### Running on the 3DS

You can either package the project using the [LÖVE Bundler](https://bundle.lovebrew.org/) or you can download a release.

##### Using the Bundler
1. Clone this repository
```bash
   git clone https://github.com/idkhan/Balatro3DS.git
   ```
2. Create a directory called <strong>game</strong> and copy all files except <strong>lovepotion.toml</strong> into it
3. Download Lovepotion from the [releases](https://github.com/lovebrew/lovepotion/releases/latest) page and copy it into the main directory (not inside game).
4. Ensure this file structure
```
|-game
|  |-engine
|  |-resources
|  ...
|-lovepotion.3dsx
|-lovepotion.toml
```
5. Compress all files into a zip file
6. Go to the [LÖVE Bundler](https://bundle.lovebrew.org/) and upload the zip file
7. Download the bundled files and extract them
8. Copy the files into the 3ds folder on the root of your 3DS

##### Packaged Builds (TBA)

### License

This project is provided as-is for educational and fan purposes. Check the repository license file (if present) for details before redistribution.

