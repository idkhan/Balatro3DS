# Build Instructions

These instructions are provided for users to create and package a Balatro3DS.3dsx file manually on their own machine. Alternative building methods can be found on the [Lovebrew wiki](https://lovebrew.org). You will need to have devkitPro and their `3ds-dev` package installed for this process. You can find the instructions for that on the [devkitPro wiki](https://devkitpro.org/wiki/Getting_Started).

Shoutout to @natesquared in the lovebrew discord, these steps are based on a similar set of instructions they gave to a different user.

> [!IMPORTANT]
> This recipe fuses the game onto a stock LövePotion release, which is missing five fixes this port depends on. A build made this way boots and plays, but sound effects lose their pitch bend, music crossfades seek to the wrong place, overlapping sounds can hard-crash the console, and the animated menu backdrop won't appear.
>
> If you just want to play, take a build from the [releases page](https://github.com/rosematcha/Balatro3DS/releases). If you're working on the port, use `./dev/setup.sh` and `./dev/build.sh` instead — they build a patched runtime and handle asset conversion, music downsampling and CIA packaging for you.

## Windows
TODO

## Linux and macOS
1. We will start off by making a folder to contain all our files.

```sh
    mkdir build_dir
    cd build_dir
```

2. Navigate to the latest release on the [lovepotion github](https://github.com/lovebrew/lovepotion/releases) and download the file labeled `Nintendo.3DS-[xxxxxxx].zip`. Extract this folder into the directory we just made in the previous step. Your file structure should look like this:

```
    build_dir/
    └── Nintendo.3DS-[xxxxxxx]/ <- the `xxxxxxx` is just a random set 
        ├── lovepotion.3dsx        of 7 characters based on whatever 
        └── lovepotion.elf         was on the releases page.
```

3. Clone the lovebrew repository. (We need the romfs folder for later.)

```sh
    git clone https://github.com/lovebrew/lovepotion.git lovepotion && rm -rf lovepotion/.git
```

4. Clone the Balatro3DS repository.

```sh
    git clone https://github.com/rosematcha/Balatro3DS.git Balatro3DS && rm -rf Balatro3DS/.git

```
5. Make a folder titled 'build'. Copy the Balatro3DS folder into it and name the folder 'game'. We will put all the files we generate in this folder.

```sh
    mkdir build
    cp -r Balatro3DS build/game
```
At this point your folder structure should look like this.
```
    build_dir/
    ├── Balatro3DS/
    │   └── ...
    ├── build/
    │   └── game/ 
    │       └── ...
    ├── lovepotion/
    │   └── ...
    └── Nintendo.3DS-[xxxxxxx]/
        └── ...
```

6. Delete the files the game doesn't load. This isn't housekeeping — `mkbcfnt` rasterizes every glyph in a face, and the seven CJK and Noto fonts sitting in the repository expand to roughly 599 MB of `.bcfnt` between them. Only `m6x11plus` is ever loaded, and its `.bcfnt` is already checked in. `menu.png` goes too: at 1024x1024 it's the largest asset in the tree, and nothing draws it anymore now that the menu backdrop is generated at runtime.

```sh
    rm -f build/game/resources/fonts/GoNotoCJKCore.ttf \
          build/game/resources/fonts/GoNotoCurrent-Bold.ttf \
          build/game/resources/fonts/NotoSans-Bold.ttf \
          build/game/resources/fonts/NotoSansJP-Bold.ttf \
          build/game/resources/fonts/NotoSansKR-Bold.ttf \
          build/game/resources/fonts/NotoSansSC-Bold.ttf \
          build/game/resources/fonts/NotoSansTC-Bold.ttf \
          build/game/resources/fonts/m6x11plus.ttf
    rm -f build/game/resources/textures/1x/menu.png
    rm -rf build/game/dev build/game/tests build/game/reference build/game/.git
```

7. Now we will convert the remaining images and fonts into `.t3x` and `.bcfnt` files. The `&& rm $0` sections are optional, this just deletes the original files to save space. 
> [!NOTE]
> This step takes a while, just be patient.
```sh
    find ./build/game -type f -name "*.png" -exec sh -c 'tex3ds -f rgba $0 -o ${0%.png}.t3x && rm $0' {} \;
    find ./build/game -type f -name "*.ttf" -exec sh -c 'mkbcfnt $0 -o ${0%.ttf}.bcfnt && rm $0' {} \;
```

8. Once that finishes we can create the metadata file.
> [!NOTE]
> Make sure to use the original `Balatro3DS` folder when referencing the `icon.png` file as the one under `build/game` could have been converted into a `.t3x` file in the previous step.

```sh 
    smdhtool --create "Balatro" "Balatro" "rosematcha" ./Balatro3DS/resources/textures/1x/icon.png ./build/metadata.smdh

```

9. Now we can build the base `.3dsx` file. (This is where we use that romfs folder from earlier.)
> [!NOTE]
> This file is a stub, if you try to execute it on your 3ds as it is now you will just get an error.
>
> Make sure to replace the `xxxxxxx` in this command with the actual name of the folder on your machine.

> [!WARNING]
> Make sure to use the `lovepotion.elf` file and NOT the `lovepotion.3dsx` in the `Nintendo.3DS-[xxxxxxx]` folder.
```sh 
    3dsxtool Nintendo.3DS-[xxxxxxx]/lovepotion.elf ./build/base.3dsx --smdh=./build/metadata.smdh --romfs=./lovepotion/platform/ctr/romfs
```

10. Next, enter the `game` directory and package the game using `zip`.

```sh
    cd ./build/game
    zip -r ../balatro.love .
```

11. Finally you can fuse the stub with the game contents to create the compiled `3dsx` file.

```sh
    cd ..
    cat base.3dsx balatro.love > Balatro3ds.3dsx

```

Copy that file into the `3ds` folder at the root of your SD card and launch it from the Homebrew Launcher.
