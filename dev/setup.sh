#!/usr/bin/env bash
#
# One-time toolchain setup for Balatro3DS builds.
#
#   ./dev/setup.sh              install tools, build the patched LövePotion runtime
#   ./dev/setup.sh --rebuild    force a clean rebuild of the runtime
#
# Everything lands under dev/.tools and dev/.cache, both gitignored. Nothing is
# installed outside the repo except devkitPro packages, which need sudo.
set -euo pipefail

# shellcheck source=dev/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

REBUILD=0
for arg in "$@"; do
    case "$arg" in
        --rebuild) REBUILD=1 ;;
        *) die "unknown option: $arg" ;;
    esac
done

mkdir -p "$TOOLS_DIR" "$CACHE_DIR" "$DIST_DIR"

# --- devkitPro -------------------------------------------------------------

if [[ ! -d "$DEVKITPRO" ]]; then
    cat >&2 <<EOF
devkitPro not found at $DEVKITPRO.

Install it first, then re-run this script:

  curl -LO https://github.com/devkitPro/pacman/releases/latest/download/devkitpro-pacman-installer.pkg
  sudo installer -pkg devkitpro-pacman-installer.pkg -target /

Open a new shell afterwards so DEVKITPRO is exported.
EOF
    exit 1
fi

if command -v dkp-pacman >/dev/null 2>&1; then
    PACMAN=dkp-pacman
elif [[ -x "$DEVKITPRO/pacman/bin/pacman" ]]; then
    PACMAN="$DEVKITPRO/pacman/bin/pacman"
else
    die "no devkitPro pacman found; reinstall devkitPro"
fi

# 3ds-dev is a group (devkitARM, libctru, citro3d, catnip, the 3DS tools), so it
# is detected through the binaries it provides rather than by package query. The
# rest are LövePotion's dependencies, mirroring platform/ctr/pkglist.txt.
PORTLIBS=(
    3ds-cmake
    3ds-box2d
    3ds-curl
    3ds-flac
    3ds-libconfig
    3ds-libjpeg-turbo
    3ds-libmodplug
    3ds-libogg
    3ds-libpng
    3ds-libtheora
    3ds-libvorbisidec
    3ds-liblua51
    3ds-lz4
    3ds-mbedtls
    3ds-physfs
    3ds-tinyxml2
    3ds-zlib
)

MISSING=()
if [[ ! -d "$DEVKITARM" ]] || ! command -v tex3ds >/dev/null 2>&1 \
    || ! command -v 3dsxtool >/dev/null 2>&1 || ! command -v mkbcfnt >/dev/null 2>&1; then
    MISSING+=(3ds-dev)
fi
for package in "${PORTLIBS[@]}"; do
    "$PACMAN" -Qi "$package" >/dev/null 2>&1 || MISSING+=("$package")
done

if (( ${#MISSING[@]} )); then
    info "installing devkitPro packages: ${MISSING[*]}"
    sudo "$PACMAN" -S --needed --noconfirm "${MISSING[@]}"
else
    info "devkitPro packages already installed"
fi

for tool in tex3ds mkbcfnt 3dsxtool smdhtool; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool missing from PATH after install"
done

# --- host build tools ------------------------------------------------------
# catnip drives cmake, and prefers ninja over make when both are available.

HOST_TOOLS=()
command -v cmake >/dev/null 2>&1 || HOST_TOOLS+=(cmake)
command -v ninja >/dev/null 2>&1 || HOST_TOOLS+=(ninja)
command -v ffmpeg >/dev/null 2>&1 || HOST_TOOLS+=(ffmpeg)
command -v oggenc >/dev/null 2>&1 || HOST_TOOLS+=(vorbis-tools)

if (( ${#HOST_TOOLS[@]} )); then
    if command -v brew >/dev/null 2>&1; then
        info "installing host build tools: ${HOST_TOOLS[*]}"
        brew install "${HOST_TOOLS[@]}"
    else
        die "missing host build tools: ${HOST_TOOLS[*]} (install them, then re-run)"
    fi
fi

# --- makerom ---------------------------------------------------------------

host_slug() {
    case "$(uname -s)/$(uname -m)" in
        Darwin/arm64)  echo macos_arm64 ;;
        Darwin/x86_64) echo macos_x86_64 ;;
        Linux/x86_64)  echo ubuntu_x86_64 ;;
        *) die "no prebuilt makerom for $(uname -s)/$(uname -m); build it from https://github.com/3DSGuy/Project_CTR" ;;
    esac
}

if [[ ! -x "$MAKEROM" ]]; then
    slug="$(host_slug)"
    url="https://github.com/3DSGuy/Project_CTR/releases/download/makerom-$MAKEROM_VERSION/makerom-$MAKEROM_VERSION-$slug.zip"
    info "fetching makerom $MAKEROM_VERSION ($slug)"
    tmp="$(mktemp -d)"
    curl -fsSL "$url" -o "$tmp/makerom.zip" || die "failed to download $url"
    unzip -qo "$tmp/makerom.zip" -d "$tmp"
    found="$(find "$tmp" -type f -name 'makerom*' ! -name '*.zip' | head -1)"
    [[ -n "$found" ]] || die "makerom binary not found in release archive"
    mv "$found" "$MAKEROM"
    chmod +x "$MAKEROM"
    rm -rf "$tmp"
fi
# Both tools print usage and exit non-zero when run bare, so swallow the status
# and look at the output instead.
runs_and_prints() {
    [[ -x "$1" ]] || return 1
    { "$1" 2>&1 || true; } | grep -qiE "$2"
}

runs_and_prints "$MAKEROM" 'makerom|usage' || die "makerom is not runnable: $MAKEROM"
info "makerom: $MAKEROM"

# --- bannertool ------------------------------------------------------------
# Needed for the CIA banner (the home menu animation and its audio). makerom
# refuses to build a CIA without one.

bannertool_works() { runs_and_prints "$1" 'makebanner|usage'; }

if ! bannertool_works "$BANNERTOOL"; then
    info "fetching bannertool"
    tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/Epicpkmn11/bannertool/releases/latest/download/bannertool.zip" -o "$tmp/bannertool.zip" \
        && unzip -qo "$tmp/bannertool.zip" -d "$tmp/extracted"; then
        while read -r candidate; do
            chmod +x "$candidate" 2>/dev/null || true
            if bannertool_works "$candidate"; then
                cp "$candidate" "$BANNERTOOL"
                break
            fi
        done < <(find "$tmp/extracted" -type f -name 'bannertool*' ! -name '*.exe')
    fi
    rm -rf "$tmp"
fi

if ! bannertool_works "$BANNERTOOL"; then
    info "no usable bannertool release for this host; building from source"
    src="$CACHE_DIR/bannertool"
    [[ -d "$src" ]] || git clone --recursive https://github.com/Epicpkmn11/bannertool.git "$src"
    make -C "$src" -j"$(getconf _NPROCESSORS_ONLN)"
    built="$(find "$src" -type f -perm -u+x -name 'bannertool' | head -1)"
    [[ -n "$built" ]] || die "bannertool build produced no binary"
    cp "$built" "$BANNERTOOL"
fi
bannertool_works "$BANNERTOOL" || die "bannertool is not runnable: $BANNERTOOL"
info "bannertool: $BANNERTOOL"

# --- LövePotion runtime ----------------------------------------------------

if [[ ! -d "$LOVEPOTION_DIR/.git" ]]; then
    info "cloning LövePotion ($LOVEPOTION_REF)"
    git clone --depth 1 --branch "$LOVEPOTION_REF" "$LOVEPOTION_REPO" "$LOVEPOTION_DIR"
else
    info "updating LövePotion"
    git -C "$LOVEPOTION_DIR" fetch --depth 1 origin "$LOVEPOTION_REF"
    # Drop previous local patches so re-patching starts from pristine sources.
    git -C "$LOVEPOTION_DIR" reset --hard -q FETCH_HEAD
fi

python3 "$DEV_DIR/patch_lovepotion.py" "$LOVEPOTION_DIR" "romfs:/$GAME_ROOT"

if (( REBUILD )); then
    rm -rf "$LOVEPOTION_BUILD" "$LOVEPOTION_DIR/build"
fi

JOBS="$(getconf _NPROCESSORS_ONLN)"
if command -v catnip >/dev/null 2>&1; then
    info "building LövePotion with catnip"
    ( cd "$LOVEPOTION_DIR" && catnip -T 3DS -DLIBRARY_LOADER=linktime -DUSE_CURL_BACKEND=ON )
else
    if command -v arm-none-eabi-cmake >/dev/null 2>&1; then
        CMAKE=(arm-none-eabi-cmake)
    elif [[ -f "$DEVKITPRO/cmake/3DS.cmake" ]]; then
        CMAKE=(cmake "-DCMAKE_TOOLCHAIN_FILE=$DEVKITPRO/cmake/3DS.cmake")
    else
        die "neither catnip nor a devkitPro cmake toolchain found; install 3ds-cmake"
    fi
    info "building LövePotion with cmake"
    "${CMAKE[@]}" -S "$LOVEPOTION_DIR" -B "$LOVEPOTION_BUILD" \
        -DCMAKE_BUILD_TYPE=Release -DLIBRARY_LOADER=linktime -DUSE_CURL_BACKEND=ON
    cmake --build "$LOVEPOTION_BUILD" -j"$JOBS"
fi

elf="$(find_lovepotion_elf || true)"
[[ -n "$elf" ]] || die "build finished but no lovepotion.elf was produced"

# Say out loud what the runtime was actually built as. Neither route states a build type in a
# way that is visible from here -- the cmake fallback passes -DCMAKE_BUILD_TYPE=Release, and
# catnip picks its own preset -- and an unoptimised LövePotion is several times slower with
# nothing else in a benchmark report to show it. So the cache is read back rather than assumed.
# (love.graphics.getRuntimeInfo reports the same thing from the console, for benchmark.txt.)
report_build_type() {
    local cache
    cache="$(find "$LOVEPOTION_DIR/build" "$LOVEPOTION_BUILD" -name CMakeCache.txt -maxdepth 3 \
        2>/dev/null | head -1)"
    if [[ -z "$cache" ]]; then
        info "build type: unknown (no CMakeCache.txt found)"
        return
    fi

    local type flags
    type="$(sed -n 's/^CMAKE_BUILD_TYPE:STRING=//p' "$cache")"
    type="${type:-<unset>}"
    flags="$(sed -n "s/^CMAKE_CXX_FLAGS_$(echo "$type" | tr '[:lower:]' '[:upper:]'):STRING=//p" "$cache")"

    info "build type: $type ${flags:+($flags)}"

    case "$type" in
        Release|RelWithDebInfo|MinSizeRel) ;;
        *) info "WARNING: the runtime is not an optimised build; benchmark numbers from it mean nothing" ;;
    esac
}
report_build_type

info "runtime ready: $elf"
info "next: ./dev/build.sh cia"
