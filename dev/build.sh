#!/usr/bin/env bash
#
# Build Balatro3DS for the 3DS.
#
#   ./dev/build.sh            build the CIA (default)
#   ./dev/build.sh 3dsx       build the fused .3dsx for the Homebrew Launcher
#   ./dev/build.sh all        build both
#   ./dev/build.sh clean      drop staged files, converted assets and output
#
# Output goes to dev/dist. Run ./dev/setup.sh once first.
#
# Assets are converted the same way the manual instructions in BUILD.md do it
# (png -> t3x, ttf -> bcfnt), since the runtime rewrites those extensions when
# loading on 3DS. Conversions are cached by file hash, so only changed art is
# reconverted.
set -euo pipefail

# shellcheck source=dev/config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

TARGET="${1:-cia}"
JOBS="$(getconf _NPROCESSORS_ONLN)"
ASSET_CACHE="$CACHE_DIR/assets"

if [[ "$TARGET" == "clean" ]]; then
    rm -rf "$STAGE_DIR" "$BUILD_DIR" "$DIST_DIR"
    info "cleaned (asset cache kept at $ASSET_CACHE)"
    exit 0
fi

case "$TARGET" in
    cia|3dsx|all) ;;
    *) die "unknown target: $TARGET (expected cia, 3dsx, all or clean)" ;;
esac

for tool in tex3ds mkbcfnt 3dsxtool ffmpeg oggenc zip rsync python3; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool not found; run ./dev/setup.sh"
done

ELF="$(find_lovepotion_elf || true)"
[[ -n "$ELF" ]] || die "no LövePotion runtime built; run ./dev/setup.sh"

mkdir -p "$STAGE_DIR" "$BUILD_DIR" "$DIST_DIR" "$ASSET_CACHE"

# --- stage game sources ----------------------------------------------------

info "staging game sources"
STAGE_EXCLUDES=()
for asset in ${EXCLUDE_ASSETS[@]+"${EXCLUDE_ASSETS[@]}"}; do
    STAGE_EXCLUDES+=(--exclude "/$asset")
done

rsync -a --delete --delete-excluded \
    ${STAGE_EXCLUDES[@]+"${STAGE_EXCLUDES[@]}"} \
    --exclude '.git/' \
    --exclude '.github/' \
    --exclude 'dev/' \
    --exclude 'scripts/' \
    --exclude 'tools/' \
    --exclude 'reference/' \
    --exclude '.scratch/' \
    --exclude 'tests/' \
    --exclude '*.md' \
    --exclude 'LICENSE' \
    --exclude 'banner.png' \
    --exclude 'Bugs.txt' \
    --exclude '.gitignore' \
    --exclude '.luarc.json' \
    --exclude '.vscode/' \
    --exclude '.DS_Store' \
    "$REPO_ROOT/" "$STAGE_DIR/"

# The soundtrack stays Vorbis: as PCM it would add roughly 23 MB to romfs, and only two
# stems ever overlap. What made crossfades drop frames was never decoder throughput but
# burst length -- LovePotion refilled a whole 16 KiB buffer in one uninterruptible call
# while holding the audio pool mutex. sfx.lua now asks for 4 KiB, which quarters that
# stall, so the rate no longer has to be crushed to 11025 Hz to compensate. Going back up
# to 16 kHz moves Nyquist from 5.5 kHz to 8 kHz and costs about 30 KB across all five
# stems, because the encoder was already sitting under the old 26 kbps ceiling.
for music in "$STAGE_DIR"/resources/sounds/music{1,2,3,4,5}.ogg; do
    [[ -f "$music" ]] || continue
    converted="$music.converted.ogg"
    ffmpeg -hide_banner -loglevel error -i "$music" \
        -map_metadata -1 -ac 1 -ar 16000 -f wav - \
        | oggenc -Q -b 32 -o "$converted" -
    mv "$converted" "$music"
done

# Everything that is not the soundtrack ships as PCM16 WAV, which NDSP takes directly.
# A pooled cue becomes a memcpy instead of a Tremor decode, cutting ~0.8 s of Vorbis out
# of the loading bar; the two ambient beds stop being a third decoder under a crossfade,
# which is what had confined them to the New 3DS. The beds are long, so they go at 11025
# Hz (they are low-frequency loops and the rate is inaudible on them) while the short
# cues keep 22050 Hz for their transients. Net cost is roughly +2 MB of romfs.
#
# PCM8 would halve that again but is unusable: NDSP wants signed 8-bit and LövePotion's
# WaveDecoder passes WAV's unsigned samples through unconverted.
for sound in "$STAGE_DIR"/resources/sounds/*.ogg; do
    [[ -f "$sound" ]] || continue
    case "${sound##*/}" in
        music[1-5].ogg) continue ;;
        ambient*) rate=11025 ;;
        *) rate=22050 ;;
    esac
    ffmpeg -hide_banner -loglevel error -i "$sound" \
        -map_metadata -1 -ac 1 -ar "$rate" -c:a pcm_s16le \
        "${sound%.ogg}.wav"
    rm -f "$sound"
done

# --- convert assets --------------------------------------------------------

# Pixel format for one texture. tex3ds defaults to 32-bit RGBA, which is what every sheet
# used to ship as.
#
# This map is deliberately short, because the runtime accepts exactly four t3x pixel formats
# -- GPU_RGBA8, GPU_RGB8, GPU_RGB565 and GPU_LA8
# (`platform/ctr/include/utilities/driver/renderer_ext.hpp:133`). Anything else, including
# rgba5551/rgba4/etc1, throws "PixelFormat %u is not compatible" out of T3XHandler::Decode
# and the image never loads. Widening it means patching that map in the runtime, not just
# passing a different flag here.
#
# la8 halves a sheet that is genuinely luminance-plus-alpha. The two edition sheets are:
# they carry structure only and take their colour from the mesh vertex field (see the
# asset_atli comment in game.lua), and every visible pixel in both has R == G == B exactly,
# so the conversion is lossless -- 512 KiB of padded texture becomes 256 KiB, 128 becomes 64.
# gamepad_ui.png reads like the same kind of sheet and is not: 90% of its visible pixels are
# chromatic, and la8 would flatten them to grey.
texture_format_for() {
    case "$1" in
        */textures/1x/editions/foil.png|*/textures/1x/editions/holo.png) echo "la8" ;;
        *) echo "rgba" ;;
    esac
}

convert_one() {
    local src="$1" out ext cached tmp key fmt
    case "$src" in
        *.png) out="${src%.png}.t3x";   ext="t3x" ;;
        *.ttf) out="${src%.ttf}.bcfnt"; ext="bcfnt" ;;
        *) return 0 ;;
    esac

    # Respect conversions that are already checked in, such as the pixel font.
    if [[ -f "$out" ]]; then
        rm -f "$src"
        return 0
    fi

    key="$(shasum -a 1 "$src" | cut -d' ' -f1)"
    if [[ "$ext" == "t3x" ]]; then
        # The format is part of the cache key: retargeting a sheet has to miss the cache,
        # or the build would keep serving the old conversion of identical source bytes.
        fmt="$(texture_format_for "$src")"
        cached="$ASSET_CACHE/$key.$fmt.$ext"
    else
        cached="$ASSET_CACHE/$key.$ext"
    fi

    if [[ ! -f "$cached" ]]; then
        tmp="$cached.$$.tmp"
        case "$ext" in
            t3x)   tex3ds -f "$fmt" "$src" -o "$tmp" ;;
            bcfnt) mkbcfnt "$src" -o "$tmp" ;;
        esac
        mv "$tmp" "$cached"
    fi

    cp "$cached" "$out"
    rm -f "$src"
}
export -f texture_format_for
export -f convert_one
export ASSET_CACHE

# --- per-cell-height pixel fonts -------------------------------------------
#
# One glyph sheet per size the game draws at, so love.graphics.newFont's size can equal the
# sheet's cell height and the runtime's size/cellHeight draw scale comes out at exactly 1.0.
# Without these the game falls back to the single 33 px sheet and every size below LARGE is a
# bilinear reduction of it (see fonts.lua). Named for the cell height because that is the number
# fonts.lua asks for; the point size that produces it lives in config.sh.
#
# Generated rather than checked in: they are re-rasterisations of one 35 KB face at ~513 KB each,
# and they only mean anything inside a 3DS build.
cell_height_of() {
    # TGLP block, per CFNT: cellWidth then cellHeight, 8 bytes past the block magic.
    python3 - "$1" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
index = data.find(b"TGLP")
print(data[index + 9] if index >= 0 else -1)
PY
}

font_src="$STAGE_DIR/$PIXEL_FONT_SRC"
if [[ -f "$font_src" ]]; then
    font_key="$(shasum -a 1 "$font_src" | cut -d' ' -f1)"
    info "baking ${#PIXEL_FONT_SHEETS[@]} pixel-font sheets"
    for sheet in "${PIXEL_FONT_SHEETS[@]}"; do
        cell_h="${sheet%%:*}"
        point_size="${sheet##*:}"
        # Keyed on the point size, not the cell height: retuning the map has to miss the cache.
        cached="$ASSET_CACHE/$font_key.s$point_size.bcfnt"

        if [[ ! -f "$cached" ]]; then
            tmp="$cached.$$.tmp"
            mkbcfnt "$font_src" -s "$point_size" -o "$tmp" >/dev/null
            produced="$(cell_height_of "$tmp")"
            # mkbcfnt is a devkitPro package and can be updated out from under this map. A silent
            # mismatch here ships text that is blurry in exactly the way this whole step exists to
            # prevent, and nothing on-console would say so.
            if [[ "$produced" != "$cell_h" ]]; then
                rm -f "$tmp"
                die "mkbcfnt -s $point_size produced a ${produced}px cell, expected ${cell_h}px; retune PIXEL_FONT_SHEETS in dev/config.sh"
            fi
            mv "$tmp" "$cached"
        fi

        cp "$cached" "${font_src%.ttf}_h$cell_h.bcfnt"
    done
fi

pending="$(find "$STAGE_DIR" \( -name '*.png' -o -name '*.ttf' \) | wc -l | tr -d ' ')"
if (( pending > 0 )); then
    info "converting $pending assets (cached in $ASSET_CACHE)"
    find "$STAGE_DIR" \( -name '*.png' -o -name '*.ttf' \) -print0 \
        | xargs -0 -P "$JOBS" -I{} bash -c 'convert_one "$@"' _ {}
fi

# --- metadata --------------------------------------------------------------

SMDH="$BUILD_DIR/meta.smdh"

# $1 output path, $2 comma-separated SMDH flags, rest passed to bannertool. The
# CIA needs `extendedbanner` to tell the Home Menu the banner is a 3D scene
# rather than a still; the .3dsx has no banner at all, so it does not get it.
build_smdh() {
    local out="$1" flags="$2"
    shift 2
    if [[ -x "$BANNERTOOL" ]]; then
        "$BANNERTOOL" makesmdh \
            -s "$APP_TITLE" -l "$APP_DESCRIPTION" -p "$APP_AUTHOR" \
            -i "$APP_ICON" -f "$flags" "$@" -o "$out" >/dev/null
    else
        smdhtool --create "$APP_TITLE" "$APP_DESCRIPTION" "$APP_AUTHOR" "$APP_ICON" "$out"
    fi
}

info "building metadata"
build_smdh "$SMDH" nosavebackups,visible

# --- targets ---------------------------------------------------------------

build_3dsx() {
    info "packaging .3dsx"
    ( cd "$STAGE_DIR" && rm -f "$BUILD_DIR/game.love" && zip -qr "$BUILD_DIR/game.love" . )
    3dsxtool "$ELF" "$BUILD_DIR/base.3dsx" \
        --smdh="$SMDH" \
        --romfs="$LOVEPOTION_DIR/platform/ctr/romfs"
    cat "$BUILD_DIR/base.3dsx" "$BUILD_DIR/game.love" > "$DIST_DIR/$APP_TITLE.3dsx"
    info "wrote $DIST_DIR/$APP_TITLE.3dsx"
}

build_cia() {
    [[ -x "$MAKEROM" ]] || die "makerom missing; run ./dev/setup.sh"
    [[ -x "$BANNERTOOL" ]] || die "bannertool missing; run ./dev/setup.sh"

    # The stock runtime cannot find a game when launched as a title, so refuse
    # to ship a CIA that would boot to the no-game screen.
    if ! LC_ALL=C grep -aq "romfs:/$GAME_ROOT" "$ELF"; then
        die "runtime at $ELF is not patched for RomFS booting; run ./dev/setup.sh"
    fi

    # Generated after staging so it is embedded only in the CIA, never local
    # development or 3dsx builds. CST6 is fixed Central Standard Time (UTC-6),
    # independent of the builder's machine and daylight-saving time.
    local cia_build_timestamp
    cia_build_timestamp="$(LC_ALL=C TZ=CST6 date '+%m/%d, %-I:%M%p CST')"
    printf 'return { timestamp = "%s" }\n' "$cia_build_timestamp" > "$STAGE_DIR/build_info.lua"

    local romfs="$BUILD_DIR/romfs" banner_audio="$DEV_DIR/cia/banner.wav"

    info "assembling RomFS"
    rm -rf "$romfs"
    mkdir -p "$romfs/$GAME_ROOT"
    cp -R "$LOVEPOTION_DIR/platform/ctr/romfs/." "$romfs/"
    rsync -a "$STAGE_DIR/" "$romfs/$GAME_ROOT/"

    # dev/cia/banner.wav wins if someone drops one in; otherwise the cue the
    # game already ships is converted for the Home Menu. Banner audio is capped
    # at three seconds and this cue runs 3.16, but its last fifth of a second is
    # below -70 dB, so the trim takes only the inaudible tail.
    #
    # 44.1 kHz 16-bit stereo, which is what banner audio is documented as
    # everywhere, even though the source is 22050 mono and upsampling adds
    # nothing but bytes. Handing bannertool the source's own format produced a
    # CWAV the Home Menu would not play: hovering the title played a completely
    # unrelated installed game's banner sound, i.e. it fell through to whatever
    # was already in the audio buffer.
    if [[ ! -f "$banner_audio" && -f "$BANNER_AUDIO" ]]; then
        banner_audio="$BUILD_DIR/banner_audio.wav"
        info "converting banner audio"
        ffmpeg -hide_banner -loglevel error -y -i "$BANNER_AUDIO" \
            -af "atrim=end=3.0,afade=t=out:st=2.85:d=0.15" \
            -ar 44100 -ac 2 -c:a pcm_s16le "$banner_audio"
    fi

    if [[ ! -f "$banner_audio" ]]; then
        banner_audio="$BUILD_DIR/silence.wav"
        [[ -f "$banner_audio" ]] || python3 - "$banner_audio" <<'PY'
import struct, sys, wave

# Home menu banners need audio; half a second of silence keeps it quiet.
rate, seconds = 32728, 0.5
with wave.open(sys.argv[1], "wb") as out:
    out.setnchannels(2)
    out.setsampwidth(2)
    out.setframerate(rate)
    out.writeframes(struct.pack("<h", 0) * 2 * int(rate * seconds))
PY
    fi

    # A CGFX banner is a 3D scene the Home Menu renders live, with stereoscopic
    # depth off the 3D slider; banner.png is the flat fallback. Regenerate the
    # scene with dev/banner/build_banner.sh.
    info "building banner"
    if [[ -f "$BANNER_CGFX" ]]; then
        "$BANNERTOOL" makebanner -ci "$BANNER_CGFX" -a "$banner_audio" \
            -o "$BUILD_DIR/banner.bnr" >/dev/null
        # No -obf: the SMDH's optimal banner frame is a float, but bannertool
        # writes the argument as a raw integer, so any value lands as a
        # denormal and reads back as frame 0. That is the pose we want anyway —
        # the scene holds the ace facing the camera from frame 0 to 70.
        build_smdh "$SMDH" nosavebackups,visible,extendedbanner
    else
        warn "$BANNER_CGFX missing; falling back to the flat banner image"
        "$BANNERTOOL" makebanner -i "$BANNER_IMAGE" -a "$banner_audio" \
            -o "$BUILD_DIR/banner.bnr" >/dev/null
    fi

    local major minor micro
    IFS='.' read -r major minor micro <<< "$APP_VERSION"
    major="${major:-0}"; minor="${minor:-0}"; micro="${micro:-0}"

    info "building .cia (makerom)"
    "$MAKEROM" -f cia \
        -o "$DIST_DIR/$APP_TITLE.cia" \
        -target t \
        -exefslogo \
        -elf "$ELF" \
        -rsf "$DEV_DIR/cia/balatro.rsf" \
        -banner "$BUILD_DIR/banner.bnr" \
        -icon "$SMDH" \
        -major "$major" -minor "$minor" -micro "$micro" \
        -DAPP_TITLE="$APP_TITLE" \
        -DAPP_PRODUCT_CODE="$PRODUCT_CODE" \
        -DAPP_UNIQUE_ID="$UNIQUE_ID" \
        -DAPP_ROMFS="$romfs" \
        -DAPP_VERSION_MAJOR="$major"

    info "wrote $DIST_DIR/$APP_TITLE.cia ($(du -h "$DIST_DIR/$APP_TITLE.cia" | cut -f1))"
}

case "$TARGET" in
    3dsx) build_3dsx ;;
    cia)  build_cia ;;
    all)  build_3dsx; build_cia ;;
esac
