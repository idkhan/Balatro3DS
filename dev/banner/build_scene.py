"""Builds the Home Menu banner scene and exports it as glTF for pycgfx.

Run inside Blender:

    blender --background --python dev/banner/build_scene.py

The Home Menu supplies its own camera when it renders a banner — pycgfx drops
cameras entirely — so world placement here is not arbitrary. Everything is laid
out against the camera in pycgfx's `banner-camera.gltf`: 30 degrees vertical
FOV, aspect 1.6667, sitting at glTF (0, 1, 44.786) with a near plane of 26.5.
That puts the visible rectangle at the z=0 plane at x in [-20, 20] and y in
[-11, 13], and it means nothing may come closer than z=+18 or it clips.

Blender is Z-up and the exporter writes Y-up, so the axes here map as
blender (x, y, z) -> glTF (x, z, -y). Concretely: glTF's "toward the camera" is
Blender -Y, and the spin about glTF Y is a spin about Blender Z.
"""

import math
import pathlib
import sys

import bpy

HERE = pathlib.Path(__file__).resolve().parent
TEXTURES = HERE / "textures"

FPS = 60
SPIN_FRAMES = 240  # one full revolution every four seconds

# (frame, degrees): hold the ace, flip, hold the deck back, flip home.
SPIN_KEYS = ((0, 0), (70, 0), (95, 90), (120, 180), (190, 180), (215, 270), (240, 360))

# Frame geometry at the z=0 plane, derived from the reference camera.
CAM_Z = 44.786
CAM_Y = 1.0
HALF_H = CAM_Z * math.tan(0.523599 / 2)  # 12.0
HALF_W = HALF_H * 1.66666666667  # 20.0

# Every node sits on the world Y axis, because the model turns as a whole: the
# rotation reaches every node rather than only the one the glTF animates, so a
# node off the axis swings around the origin instead of turning in place.
#
# The logo still needs to sit well behind the card, or the card turns through
# the logo's plane and the logo cuts it in half. That distance therefore lives
# in the logo's vertices rather than its node (see make_quad), which is stable
# under both the billboard and the turn. It has to clear the card's swept
# radius, which is half the card's width.
LOGO_DEPTH = 8.0

# Scaled by its distance so it subtends the same angle it would at the origin.
LOGO_W = 28.0 * (CAM_Z + LOGO_DEPTH) / CAM_Z
LOGO_H = LOGO_W * 165 / 256  # the logo sheet's cropped content is 256x165
LOGO_V0 = 1 - 165 / 256  # so its UVs stop short of the sheet's empty bottom

CARD_W = 6.0 * CAM_Z / 38.786
CARD_H = CARD_W * 128 / 96  # card art occupies the middle 96px of 128
CARD_U0, CARD_U1 = 0.125, 0.875
# The two card faces sit either side of the pivot, so whichever face is turned
# toward the camera is always the one in front. That is what keeps the card
# clear of the logo at the same depth: the visible face is always CARD_SPLIT
# nearer the camera than the logo plane, at every angle of the turn. Wide enough
# to stay clear of depth buffer precision at this distance.
CARD_SPLIT = 0.25


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.frame_start = 0
    scene.frame_end = SPIN_FRAMES
    # 1.6667 aspect, matching the reference camera, so viewport checks frame
    # the same way the Home Menu will.
    scene.render.resolution_x = 320
    scene.render.resolution_y = 192


def make_material(name, texture, alpha):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    # Single-sided everywhere: the exporter maps this to glTF doubleSided, and
    # pycgfx implements double-sided by duplicating every vertex backwards,
    # which is pure waste against the 512 KB ceiling.
    mat.use_backface_culling = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    # Flat art under pycgfx's fixed light rig: ambient is full white, so
    # roughness 1.0 (specular constant drops to 0.1) keeps it from glinting.
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(str(TEXTURES / texture))
    tex.image.alpha_mode = "STRAIGHT"
    tex.interpolation = "Closest"  # every source sheet is pixel art
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        for attr, value in (("blend_method", "BLEND"), ("surface_render_method", "BLENDED")):
            if hasattr(mat, attr):  # renamed in 4.2's EEVEE Next
                setattr(mat, attr, value)
    return mat


def make_quad(name, width, height, material, uvs, facing_camera=True, rise=0.0, back=0.0):
    """A quad in Blender's XZ plane, normal along -Y (toward the camera).

    `rise` and `back` move the geometry rather than the object, for billboarded
    nodes: a billboard's node transform has to stay identity or its own rotation
    compounds with the one the billboard applies, and the plane collapses to a
    vertical line.

    Offsetting the geometry instead is not just safe, it is the only way to put
    a billboard anywhere but the origin here, because the model turns as a
    whole. A node moved off the axis orbits it. Geometry offset inside a
    billboarded node does not: the offset is applied in the billboard's own
    space, which is re-aimed at the viewer every frame, so `back` holds the
    plane a fixed distance behind the origin no matter how far the model has
    turned.
    """
    hw, hh = width / 2, height / 2
    verts = [
        (-hw, back, rise - hh), (hw, back, rise - hh),
        (hw, back, rise + hh), (-hw, back, rise + hh),
    ]
    (u0, v0), (u1, v1) = uvs
    corners = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    face = [0, 1, 2, 3] if facing_camera else [3, 2, 1, 0]

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], [face])
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        uv_layer.data[loop.index].uv = corners[loop.vertex_index]
    mesh.materials.append(material)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    clear_scene()

    # No backdrop plane. The first hardware build had one behind the logo and it
    # carried a grey specular oval across half the loop; a big flat surface is
    # the worst possible place for pycgfx's fixed phong lobe, and the Home Menu's
    # own background behind a transparent banner looks better than a dark slab.
    # _BB marks it as a billboard for patch_pycgfx.py, so it keeps facing the
    # viewer while the model turns. Its node stays at the origin with identity
    # rotation and the framing offset baked into the geometry, which is what
    # billboarding requires.
    logo = make_quad(
        "LOGO_BB", LOGO_W, LOGO_H, make_material("Logo", "logo.png", alpha=True),
        ((0, LOGO_V0), (1, 1)), rise=CAM_Y, back=LOGO_DEPTH,
    )
    logo.location = (0, 0, 0)

    # The card is a hinge, not a swing: the pivot is the card's own centre, which
    # is also where the menu's ace sits over the logo (main_menu_ui.lua:220 puts
    # it within a couple of pixels of the logo's centre). It sits on the world Y
    # axis so that the spin is in place no matter which node the spin binds to.
    pivot = bpy.data.objects.new("CARD_PIVOT", None)
    pivot.location = (0, 0, CAM_Y)
    pivot.rotation_mode = "XYZ"
    bpy.context.collection.objects.link(pivot)

    ace = make_quad(
        "ACE", CARD_W, CARD_H, make_material("Ace", "ace.png", alpha=True),
        ((CARD_U0, 0), (CARD_U1, 1)),
    )
    ace.location = (0, -CARD_SPLIT, 0)
    ace.parent = pivot

    back = make_quad(
        "DECK_BACK", CARD_W, CARD_H,
        make_material("DeckBack", "deck_back.png", alpha=True),
        ((CARD_U0, 0), (CARD_U1, 1)),
        facing_camera=False,
    )
    back.location = (0, CARD_SPLIT, 0)
    back.parent = pivot

    animate(pivot)
    add_camera()
    return pivot


def action_fcurves(action):
    """Blender 4.4 moved an action's curves behind layers/strips/channelbags."""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    return [
        fcurve
        for layer in action.layers
        for strip in layer.strips
        for channelbag in strip.channelbags
        for fcurve in channelbag.fcurves
    ]


def animate(pivot):
    # Spin about Blender Z (glTF Y). The card is a zero-thickness quad, so it
    # disappears entirely at 90 degrees; a constant-rate spin spends a visible
    # beat as nothing at all. Instead it holds a face to the camera and flips
    # through the invisible angles quickly, which also reads closer to the
    # menu's ace than a turntable does.
    #
    # Every key is LINEAR and no two are a half turn apart, because glTF stores
    # rotations as quaternions and pycgfx (main.py:1150) only unwraps them back
    # into continuous euler angles under exactly those two conditions. Violate
    # either and the card reverses direction mid-flip.
    for frame, degrees in SPIN_KEYS:
        pivot.rotation_euler = (0, 0, math.radians(degrees))
        pivot.keyframe_insert("rotation_euler", frame=frame)

    # Rotation only, no bob. A translation that binds to the model root shifts
    # the entire banner rather than lifting one card, and the loop does not need
    # it badly enough to risk that.
    for fcurve in action_fcurves(pivot.animation_data.action):
        for keyframe in fcurve.keyframe_points:
            keyframe.interpolation = "LINEAR"


def add_camera():
    """Framing aid only — pycgfx ignores cameras, the Home Menu brings its own."""
    cam_data = bpy.data.cameras.new("BannerCamera")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = 0.523599
    cam_data.clip_start = 26.5
    cam_data.clip_end = 1000
    cam = bpy.data.objects.new("BannerCamera", cam_data)
    cam.location = (0, -CAM_Z, CAM_Y)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam


def export(path):
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode="SCENE",
        export_cameras=False,
        export_lights=False,
        export_extras=False,
    )


if __name__ == "__main__":
    build()
    out = HERE / "banner.glb"
    export(out)
    print(f"wrote {out} ({out.stat().st_size} bytes)", file=sys.stderr)
