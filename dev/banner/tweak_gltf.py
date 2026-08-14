#!/usr/bin/env python3
"""Post-export fixes to banner.glb that cannot be expressed in Blender.

Run between build_scene.py and pycgfx.
"""
import pathlib
import sys

import gltflib

GLB = pathlib.Path(__file__).resolve().parent / "banner.glb"

# pycgfx gives every material a phong specular lobe whose amplitude is
# `1 - 0.9 * roughnessFactor` (main.py:685), so even fully rough art keeps 10%
# additive white — on hardware that showed up as a grey oval sliding across the
# banner. glTF caps roughness at 1.0 and Blender clamps to it, so the amplitude
# can only be driven to zero from out here. 1.1111 lands it at ~1e-5, close
# enough to off while staying positive (a negative would wrap when it is
# quantised to a byte).
KILL_SPECULAR_ROUGHNESS = 1.1111

# Alpha masking rather than blending, which is what the banner format wants.
# pycgfx drops depth writes for BLEND materials (main.py:632) and leans on draw
# order alone, so on hardware the logo painted straight over a card that was six
# units in front of it. MASK keeps the default depth test *and* write, so the
# depth buffer sorts the scene and draw order stops mattering. The cards have no
# partial alpha at all, and the logo only has antialiased edges, so the cost is
# a slightly harder edge on the logo.
ALPHA_CUTOFF = 0.5

# Masking everything also keeps draw order predictable. pycgfx sorts meshes so
# that translucent ones draw last, so a single BLEND material jumps to the end
# of the queue -- which is how the logo ended up painted over the card in the
# first place. With every material masked the sort is a no-op and scene order
# stands.
#
# pycgfx derives mesh draw order from the order nodes appear in the scene, and
# Blender emits scene roots sorted by name.
FIRST = "LOGO_BB"


def main() -> int:
    gltf = gltflib.GLTF.load(str(GLB))
    model = gltf.model

    for material in model.materials or []:
        pmr = material.pbrMetallicRoughness
        if pmr is None:
            pmr = material.pbrMetallicRoughness = gltflib.PBRMetallicRoughness()
        pmr.roughnessFactor = KILL_SPECULAR_ROUGHNESS
        material.alphaMode = "MASK"
        material.alphaCutoff = ALPHA_CUTOFF
        print(f"{material.name}: roughness -> {pmr.roughnessFactor}, alpha -> {material.alphaMode}")

    scene = model.scenes[model.scene]
    names = [model.nodes[i].name for i in scene.nodes]
    if FIRST not in names:
        print(f"error: no {FIRST} node among scene roots {names}", file=sys.stderr)
        return 1
    scene.nodes.sort(key=lambda i: model.nodes[i].name != FIRST)
    print(f"scene roots: {[model.nodes[i].name for i in scene.nodes]}")

    gltf.export(str(GLB))
    return 0


if __name__ == "__main__":
    sys.exit(main())
