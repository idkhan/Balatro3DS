#!/usr/bin/env python3
"""Teach pycgfx to mark a node as a billboard.

An extended banner's logo is conventionally a billboarded sibling of the node
that turns, so it keeps facing the viewer no matter what the rest of the model
does. glTF has no way to express that, which is why pycgfx does not emit it and
its README points at editing the CGFX afterwards instead. Doing it at
conversion time is the same edit, minus the hex editor.

This is a contained change: Bone.billboard_mode already exists and is already
serialised on every bone (cgfx/sobj.py:203), so this only writes a defined value
into an existing field. That is deliberately unlike the earlier attempt to
change an animation group member's field_type, which reinterpreted how the HOME
Menu parsed the member and data aborted the ARM11.

Anchor-based and idempotent, in the same shape as dev/patch_lovepotion.py: it
fails loudly if the anchor stops matching exactly once, which is what happens
when upstream moves.
"""

import sys
from pathlib import Path

# The name suffix is the marker, so the scene decides what billboards and the
# converter stays generic.
ANCHOR = """        bone = Bone()
        bone.name = node.name or f"Node {node_id}"
        bone_dict.add(bone.name, bone)"""

PATCHED = """        bone = Bone()
        bone.name = node.name or f"Node {node_id}"
        # Balatro3DS: nodes suffixed _BB always face the viewer.
        if bone.name.endswith("_BB"):
            bone.billboard_mode = BillboardMode.YAxial
        bone_dict.add(bone.name, bone)"""

MARKER = "# Balatro3DS: nodes suffixed _BB"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <pycgfx-checkout>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1]) / "main.py"
    if not path.is_file():
        print(f"error: {path} does not exist", file=sys.stderr)
        return 1

    source = path.read_text()
    if MARKER in source:
        print(f"already patched: {path}")
        return 0

    count = source.count(ANCHOR)
    if count != 1:
        print(
            f"error: expected exactly one match in {path}, found {count}.\n"
            f"Upstream has changed; update {Path(__file__).name}.\n"
            f"--- anchor ---\n{ANCHOR}",
            file=sys.stderr,
        )
        return 1

    if "BillboardMode" not in source:
        print(f"error: {path} no longer imports BillboardMode", file=sys.stderr)
        return 1

    path.write_text(source.replace(ANCHOR, PATCHED))
    print(f"patched: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
