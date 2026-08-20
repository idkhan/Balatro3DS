#!/usr/bin/env bash
# Regenerates dev/banner/banner.cgfx, the Home Menu's 3D banner scene.
#
# The result is checked in, the same way m6x11plus.bcfnt is, because this needs
# Blender and a network clone of pycgfx and dev/build.sh should not. Run this
# only when the scene or its source art changes, and commit the .cgfx with it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
PYCGFX="$REPO_ROOT/dev/.cache/pycgfx"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"

info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

command -v uv >/dev/null || die "uv missing; brew install uv"
[[ -x "$BLENDER" ]] || die "Blender missing at $BLENDER; set BLENDER=/path/to/blender"

if [[ ! -d "$PYCGFX" ]]; then
    info "cloning pycgfx"
    git clone --depth 1 https://github.com/skyfloogle/pycgfx.git "$PYCGFX"
fi

# Reset first so a patch that has since been withdrawn cannot survive in an
# existing checkout. One did: setting a bone's animation group member field_type
# to 5 made the HOME Menu read the member through the wrong interpretation and
# data abort the ARM11 on hover.
git -C "$PYCGFX" checkout -- main.py 2>/dev/null || true

info "patching pycgfx"
python3 "$HERE/patch_pycgfx.py" "$PYCGFX"

info "cutting textures"
uv run --with pillow python3 "$HERE/make_textures.py"

info "building scene"
"$BLENDER" --background --python "$HERE/build_scene.py"

info "applying post-export glTF fixes"
uv run --with gltflib python3 "$HERE/tweak_gltf.py"

info "converting to CGFX"
( cd "$PYCGFX" && uv run --with pillow --with gltflib python main.py "$HERE/banner.glb" )

# The 3DS rejects a CGFX over 512 KB. pycgfx warns, but a warning scrolls past
# in a build log, so fail here instead.
size=$(wc -c < "$HERE/banner.cgfx")
(( size <= 512 * 1024 )) || die "banner.cgfx is $size bytes, over the 512 KB limit"
info "wrote banner.cgfx ($size bytes)"
