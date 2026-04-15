## Balatro3DS

Balatro3DS is a fan-made port/implementation of the game Balatro targeting the Nintendo 3DS, built with Lua and LÖVE.

### Requirements

- Lua 5.x
- LÖVE 3.x
- A Nintendo 3DS with homebrew capabilities (for running custom software)

### Getting Started

#### Controls

Play - R or Y
Discard - L or X
Sort by Rank - D Pad Left  
Sort by Suit - D Pad Right
Show Jokers - D Pad Up
Hide Jokers - D Pad Down

#### Running on the 3DS

You can either download a release or package it yourself.

##### Packaged Builds
1. Copy the Balatro3DS.3dsx file into the 3ds folder on the root of your SD Card
2. Open Homebrew launcher
3. Play the game (It will show up as LOVE Potion for now)

##### Using the Bundler
1. Clone this repository
```bash
   git clone https://github.com/idkhan/Balatro3DS.git
   ```
2. Create a directory called <strong>game</strong> and copy all files except <strong>lovepotion.toml</strong> into it
3. Ensure this file structure
```
|-game
|  |-engine
|  |-resources
|  ...
|-lovepotion.3dsx
|-lovepotion.toml
```
4. Compress all files into a zip file
5. Go to the [LÖVE Bundler](https://bundle.lovebrew.org/) and upload the zip file
6. Download the bundled files and extract them
7. Copy the files into the 3ds folder on the root of your 3DS
8. Open Homebrew Launcher and play the game

##### No Bundler
1. Clone this repository
```bash
   git clone https://github.com/idkhan/Balatro3DS.git
   ```
2. Zip everything and rename the file to Game.love
3. Download Lovepotion from the [releases](https://github.com/lovebrew/lovepotion/releases/latest) page and copy it into the main directory.
4. Fuse the .love file with Lovepotion.3dsx

Linux:
```bash
   cat lovepotion.3dsx Game.love > Balatro3DS.3dsx
```
Windows:
```batch
   copy /b lovepotion.3dsx+Game.love Balatro3DS.3dsx
```
5. Copy the file to the 3ds folder in the root of your SD card
6. Open the Homebrew Launcher to play the game (It will show up as LOVE Potion)

### License

This project is provided as-is for educational and fan purposes. Check the repository license file for details before redistribution.

