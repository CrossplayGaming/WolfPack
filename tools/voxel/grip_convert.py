# Convert a grip_lab.html capture into the pipeline's 7-number grip.
#
#   blender --background --python tools/voxel/grip_convert.py -- \
#       "<character.glb>" grip.json [--bone RightHand]
#
# The browser tool cannot emit bone-space numbers directly, because
# Blender's pose-bone frame (+Y along the bone, roll from the importer)
# is not the glTF node frame three.js sees - reconciling the two per
# bone is exactly the kind of convention math that produced the
# barrel-backwards gun. So the tool exports something with only ONE
# convention in it: the weapon's WORLD matrix (glTF axes, relative to
# the character root) at a captured clip time. This script replays that
# same clip at that same time in Blender, converts glTF world axes to
# Blender's with the fixed Y-up -> Z-up rotation, and solves
#
#   matrix_basis = inv(bone_world) @ weapon_world
#
# which is precisely what the CHILD_OF attach in glb_to_obj.py applies.
# Decomposed and rescaled, that IS the legacy grip line - so the whole
# bake pipeline stays untouched and every existing grip stays valid.
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
char = Path(argv[0]).resolve()
grip = json.loads(Path(argv[1]).read_text())
bone_name = argv[argv.index("--bone") + 1] if "--bone" in argv \
    else grip.get("bone", "RightHand")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(char))

arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
if not arms:
    sys.exit("no armature in " + char.name)
arm = arms[0]


def find_bone(wanted):
    for b in arm.data.bones:
        if b.name == wanted or b.name.split(":")[-1] == wanted:
            return b.name
    sys.exit(f"no bone '{wanted}' in {[b.name for b in arm.data.bones]}")


bone = find_bone(bone_name)

# replay the captured instant, subframe-exact
sc = bpy.context.scene
f = grip["t"] * sc.render.fps
sc.frame_set(int(f), subframe=f - int(f))
bpy.context.view_layer.update()

B = arm.matrix_world @ arm.pose.bones[bone].matrix

# three.js Matrix4.toArray() is COLUMN-major; mathutils wants rows
m = grip["world_gltf"]
W_gltf = Matrix([[m[0], m[4], m[8],  m[12]],
                 [m[1], m[5], m[9],  m[13]],
                 [m[2], m[6], m[10], m[14]],
                 [m[3], m[7], m[11], m[15]]])

# glTF is Y-up. Blender's importer does NOT rotate objects to convert -
# it rewrites the MESH DATA to Z-up (measured: armature imports at pure
# scale, a plain weapon mesh at identity, raw vertices already Z-up).
# So the world map is the +90-about-X, but the attached weapon's
# geometry is already-converted data, which costs a trailing inverse:
#
#   basis = inv(B) @ Y @ W_gltf @ inv(Y)
#
# The first fix omitted the trailing inv(Y): every weapon baked with the
# same fixed local twist (owner: "all upside down, in the left hand").
# The synthetic round-trip test could not catch it - it generated its
# capture by inverting this very code, so the error cancelled.
YUP2ZUP = Matrix.Rotation(math.radians(90), 4, 'X')
basis = B.inverted() @ YUP2ZUP @ W_gltf @ YUP2ZUP.inverted()
loc, rot, scl = basis.decompose()
eul = rot.to_euler('XYZ')

# glb_to_obj applies T(loc/k) @ R @ S(s/k): fold the bone scale back in
k = sum(B.to_scale()) / 3.0
s = sum(scl) / 3.0
if max(scl) - min(scl) > 0.02 * s:
    print(f"WARNING: non-uniform scale {tuple(round(v, 4) for v in scl)} - "
          f"the grip format is uniform; using the mean")

line = "%.4f,%.4f,%.4f,%.1f,%.1f,%.1f,%.4f" % (
    loc.x * k, loc.y * k, loc.z * k,
    math.degrees(eul.x), math.degrees(eul.y), math.degrees(eul.z),
    s * k)
print(f"bone: {bone}  (clip {grip.get('clip', '?')} @ t={grip['t']})")
print(f"GRIP {line}")
