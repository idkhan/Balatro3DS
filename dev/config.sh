#!/usr/bin/env bash
# Shared configuration for the Balatro3DS dev tooling.
# Sourced by setup.sh and build.sh; not meant to be run directly.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_DIR="$REPO_ROOT/dev"
CACHE_DIR="$DEV_DIR/.cache"
TOOLS_DIR="$DEV_DIR/.tools"
DIST_DIR="$DEV_DIR/dist"
BUILD_DIR="$CACHE_DIR/build"
STAGE_DIR="$CACHE_DIR/stage"

# Application metadata. Version tracks lovebrew.toml so there is one source of truth.
APP_TITLE="Balatro"
APP_DESCRIPTION="Balatro"
APP_AUTHOR="rosematcha"
APP_VERSION="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/lovebrew.toml" | head -1)"
APP_ICON="$REPO_ROOT/resources/textures/1x/icon.png"   # 48x48 png
BANNER_IMAGE="$REPO_ROOT/banner.png"                   # 256x128 png, fallback
BANNER_CGFX="$REPO_ROOT/dev/banner/banner.cgfx"        # 3D banner scene, preferred
BANNER_AUDIO="$REPO_ROOT/resources/sounds/win.ogg"     # trimmed to 3s at build time

# CIA identity. UNIQUE_ID must not collide with other installed titles; the low
# 20 bits become part of the title ID, so changing it installs a second copy.
UNIQUE_ID="0xBA1A7"
PRODUCT_CODE="CTR-H-BLTR"

# Where the game lives inside the CIA's RomFS. This doubles as the LOVE save
# identity (love strips the path and extension), and the .3dsx is named from it
# too so CIA and 3dsx builds share one save directory.
#
# Deliberately NOT derived from APP_TITLE: the runtime is patched once at setup
# time to boot this exact path, so changing it silently desynchronises an
# already-built runtime from the RomFS the CIA ships (the console then shows the
# no-game screen). It is also the save directory name, so renaming it orphans
# every existing save. Change it only together with ./dev/setup.sh --rebuild.
GAME_ROOT="Balatro3DS"

# Files staged in the repo that no code loads. mkbcfnt rasterises every glyph in
# a face, so these seven CJK/Noto TTFs turn into 599MB of .bcfnt and dominate the
# build; only m6x11plus is referenced (globals.lua), and its .bcfnt is already
# checked in. Drop an entry from this list the moment something loads it.
EXCLUDE_ASSETS=(
    # The menu backdrop is generated on the GPU now (backdrop.lua plus
    # dev/shaders/backdrop.v.pica), so its 63-frame sheet no longer ships. It was the largest
    # asset in the game -- 1024x1024, 2.5 MB converted -- and it was read off the card on every
    # entry to the home screen. Kept in the repository as the reference for the look.
    "resources/textures/1x/menu.png"
    "resources/fonts/GoNotoCJKCore.ttf"
    "resources/fonts/GoNotoCurrent-Bold.ttf"
    "resources/fonts/NotoSans-Bold.ttf"
    "resources/fonts/NotoSansJP-Bold.ttf"
    "resources/fonts/NotoSansKR-Bold.ttf"
    "resources/fonts/NotoSansSC-Bold.ttf"
    "resources/fonts/NotoSansTC-Bold.ttf"
    # Cues the reference game plays that this port has no call site for yet. They are
    # kept in the repository as the spec for those gaps, but shipping them costs romfs
    # and, for the beds, would tempt someone into opening a third stream. Delete the
    # entry, don't delete the file, when the matching cue gets wired up.
    "resources/sounds/voice*.ogg"
    "resources/sounds/magic_crumple*.ogg"
    "resources/sounds/ambientFire1.ogg"
    "resources/sounds/ambientFire3.ogg"
    "resources/sounds/splash_buildup.ogg"
    "resources/sounds/whoosh_long.ogg"
    "resources/sounds/timpani.ogg"
)

# Per-cell-height pixel-font sheets, as "cellHeight:pointSize".
#
# A .bcfnt is a bitmap font, and LövePotion turns the size passed to love.graphics.newFont into a
# draw scale of size/cellHeight, so text is only sharp when the two match. mkbcfnt's -s argument is
# a point size, NOT the cell height it produces, and the mapping is neither linear nor injective
# (-s 21 and -s 22 both yield a 33 px cell). The point sizes below were measured off generated
# files; where two produced the same cell height the larger was taken, since it fills the cell with
# more ink. build.sh re-verifies each result and fails if mkbcfnt ever disagrees.
#
# The cell heights here must match Fonts.CELL_HEIGHTS in fonts.lua; tests/test_fonts.lua parses
# this file and fails if they drift apart.
PIXEL_FONT_SRC="resources/fonts/m6x11plus.ttf"
PIXEL_FONT_SHEETS=(
    "9:6"
    "13:8"
    "18:12"
    "22:14"
    "27:18"
    "33:22"
)

# LövePotion runtime source. Pin LOVEPOTION_REF to a commit for reproducible
# builds; "main" tracks upstream nightly.
LOVEPOTION_REPO="https://github.com/lovebrew/lovepotion.git"
LOVEPOTION_REF="main"
LOVEPOTION_DIR="$CACHE_DIR/lovepotion"
LOVEPOTION_BUILD="$LOVEPOTION_DIR/build-3ds"
LOVEPOTION_ELF="$LOVEPOTION_BUILD/lovepotion.elf"

# devkitPro. DEVKITPRO is normally exported by the installer.
DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
DEVKITARM="${DEVKITARM:-$DEVKITPRO/devkitARM}"

MAKEROM_VERSION="v0.19.0"
MAKEROM="${MAKEROM:-$TOOLS_DIR/makerom}"
BANNERTOOL="${BANNERTOOL:-$TOOLS_DIR/bannertool}"

export DEVKITPRO DEVKITARM
export PATH="$DEVKITPRO/tools/bin:$DEVKITARM/bin:$DEVKITPRO/portlibs/3ds/bin:$PATH"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

# catnip and the cmake wrapper drop the runtime in different directories, so
# take the newest lovepotion.elf under either build tree.
find_lovepotion_elf() {
    local candidate
    candidate="$(find "$LOVEPOTION_BUILD" "$LOVEPOTION_DIR/build" -name 'lovepotion.elf' -type f 2>/dev/null \
        | while read -r elf; do printf '%s %s\n' "$(stat -f '%m' "$elf" 2>/dev/null || stat -c '%Y' "$elf")" "$elf"; done \
        | sort -rn | head -1 | cut -d' ' -f2-)"
    [[ -n "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}
