# Headless Blender: GLB -> OBJ + MTL + texture files, colours preserved.
#
#   blender --background --python tools/voxel/glb_to_obj.py -- in.glb out_dir
#
# Meshy exports its COLOURED model only as GLB (textures embedded); every
# voxelizer wants OBJ+texture. This is the bridge, and path_mode='COPY'
# is the part that matters: it unpacks the embedded textures to real
# files beside the OBJ and references them from the MTL. Eric never
# opens Blender -- this is a command-line converter.
#
# Also supports --sample-frames N: if the GLB carries an animation
# (a Meshy preset), export N evenly spaced posed frames as separate
# OBJs -- the no-posing-needed path for enemy walk cycles.
#
# --attach <mesh> [--bone NAME] [--grip x,y,z,rx,ry,rz,s]
#   Parent a prop (a gun) to a hand bone so it rides the animation. This
#   is how a weapon gets into the character WITHOUT the generator having
#   to understand weapons: nothing about the clip changes, the prop just
#   follows the bone through every pose of every clip, now and later.
#
#   Measured on this project's own models (BJ Idle.glb): a 24-bone
#   humanoid rig named Hips/Spine/LeftHand/RightHand - so the default
#   bone is RightHand and no re-rigging is needed. There are no finger
#   bones, which is fine: at 96 voxels tall a hand is about two voxels,
#   so grip detail is below the resolution either way.
#
#   The grip is 7 numbers in BONE SPACE (Blender bone space: origin at
#   the bone head, +Y along the bone) - translation, XYZ-euler rotation
#   in degrees, uniform scale. They cannot be derived, because a mesh's
#   own origin and axis convention are arbitrary; calibrate once with
#   calib_grip.py and reuse forever.
import math
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src = Path(argv[0]).resolve()
out_dir = Path(argv[1]).resolve()
frames = int(argv[argv.index("--sample-frames") + 1]) \
    if "--sample-frames" in argv else 0
# --times: explicit moments in SECONDS, straight from frame_picker.html
# (Eric picks poses by eye; seconds are unambiguous across fps guesses)
times = [float(t) for t in argv[argv.index("--times") + 1].split(",")] \
    if "--times" in argv else []
attach = Path(argv[argv.index("--attach") + 1]).resolve() \
    if "--attach" in argv else None
bone_name = argv[argv.index("--bone") + 1] if "--bone" in argv else None
grip = [float(v) for v in argv[argv.index("--grip") + 1].split(",")] \
    if "--grip" in argv else [0, 0, 0, 0, 0, 0, 1]
out_dir.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(src))


def find_bone(arm, wanted):
    """Mixamo prefixes bones 'mixamorig:'; Meshy's rig does not. Match on
    the bare name so one grip file works across both."""
    names = [b.name for b in arm.data.bones]
    for n in names:
        if n == wanted or n.split(":")[-1] == wanted:
            return n
    return None


def attach_prop(path, wanted_bone, g):
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not arms:
        sys.exit("--attach: the character GLB has no armature to bind to")
    arm = arms[0]
    bone = find_bone(arm, wanted_bone or "RightHand")
    if bone is None:
        sys.exit(f"--attach: no bone '{wanted_bone or 'RightHand'}' in "
                 f"{[b.name for b in arm.data.bones]}")

    before = set(bpy.data.objects)
    suf = path.suffix.lower()
    if suf in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif suf == ".obj":
        bpy.ops.wm.obj_import(filepath=str(path))
    else:
        sys.exit(f"--attach: unsupported mesh type {suf}")
    new = [o for o in bpy.data.objects if o not in before
           and o.type == "MESH"]
    if not new:
        sys.exit(f"--attach: no mesh found in {path.name}")

    # One CHILD_OF per imported piece, with the inverse matrix left at
    # identity so the object's own transform reads directly in bone
    # space. That is what makes the grip numbers stable and tunable -
    # Blender's default bone parenting would offset them by the bone's
    # rest matrix and by its LENGTH (children land at the tail), which
    # makes calibration numbers mean nothing between rigs.
    # Bone space is not metres. A glTF character arrives with the
    # armature scaled (measured on BJ: the hand bone's world scale is
    # ~0.02), so a 0.5 m gun parented raw came out a 1 cm speck -
    # caught because the calibration strip showed no gun at all. Divide
    # the bone's world scale out so the grip numbers mean what they say:
    # translations in metres along the bone's own axes, scale 1 = the
    # mesh at its authored size.
    bpy.context.view_layer.update()
    pb = arm.pose.bones[bone]
    k = (arm.matrix_world @ pb.matrix).to_scale()
    k = (k.x + k.y + k.z) / 3.0
    if k == 0:
        sys.exit("--attach: the target bone has zero scale")
    m = (Matrix.Translation(Vector(g[0:3]) / k)
         @ Euler([math.radians(v) for v in g[3:6]], "XYZ").to_matrix().to_4x4()
         @ Matrix.Scale(g[6] / k, 4))
    for o in new:
        con = o.constraints.new("CHILD_OF")
        con.target = arm
        con.subtarget = bone
        con.inverse_matrix = Matrix.Identity(4)
        o.matrix_basis = m
    print(f"ATTACH {path.name}: {len(new)} mesh(es) -> bone '{bone}' "
          f"(bone world scale {k:.4f}) grip loc={g[0:3]} rot={g[3:6]} "
          f"scale={g[6]}")
    return new


def muzzle_world(objs, ax):
    """Where the barrel ENDS, in world metres, for the current pose.

    A muzzle flash cannot be baked into the body poses - the fire rate is
    the weapon's, not the animation's - so it is drawn as its own actor,
    and that actor needs to know where the barrel tip is. Recording it
    here is free: the gun is already attached and posed, so the tip is
    just its furthest vertex along its own long axis."""
    best, bestd = None, None
    for o in objs:
        ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
        for v in ev.data.vertices:
            w = ev.matrix_world @ v.co
            d = w.dot(ax)
            if bestd is None or d > bestd:
                bestd, best = d, w.copy()
    return best


gun_objs = attach_prop(attach, bone_name, grip) if attach else []
# --attach-only: export the PROP alone, posed by the animation. The gun
# is a separate actor in-engine, so it is baked as its own voxel set in
# the body's exact voxel grid (voxelize --frame-from). Keeping it out of
# the body models means the uniform recolor cannot paint it - measured:
# 338 of the gun's 1147 voxels fall inside the uniform's colour band -
# and one gun serves all four uniforms instead of four baked copies.
if "--attach-only" in argv and gun_objs:
    keep = set(gun_objs)
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    print(f"ATTACH-ONLY: exporting the prop alone ({len(keep)} mesh)")
# the gun's long axis, in ITS OWN space, after the grip rotation - the
# barrel points along this once posed
muzzle_axis = None
if gun_objs:
    import math as _m
    from mathutils import Euler as _E
    _ax = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)),
           "z": Vector((0, 0, 1))}[
        argv[argv.index("--gun-axis") + 1] if "--gun-axis" in argv else "x"]
    muzzle_axis = _ax
muzzles = []

# unpack any embedded images so path_mode COPY has real files to copy
for img in bpy.data.images:
    if img.packed_file:
        img.filepath_raw = str(out_dir / (img.name.replace(" ", "_")
                                          + ".png"))
        img.file_format = "PNG"
        img.save()


def export(path):
    bpy.ops.wm.obj_export(filepath=str(path), export_materials=True,
                          path_mode="COPY", export_triangulated_mesh=True,
                          up_axis="Z", forward_axis="NEGATIVE_Y")


if times:
    scene = bpy.context.scene
    fps = scene.render.fps
    for i, t in enumerate(times):
        scene.frame_set(scene.frame_start + round(t * fps))
        bpy.context.evaluated_depsgraph_get()
        export(out_dir / f"{src.stem}_p{i:02d}.obj")
        if gun_objs:
            w = muzzle_world(gun_objs, muzzle_axis)
            muzzles.append({"pose": f"{src.stem}_p{i:02d}",
                            "muzzle_world": [w.x, w.y, w.z]})
            print(f"MUZZLE p{i:02d} ({w.x:.3f},{w.y:.3f},{w.z:.3f})")
        print(f"OK pose {i} at {t}s (frame {scene.frame_current})")
elif frames <= 0:
    export(out_dir / (src.stem + ".obj"))
    print(f"OK static: {src.stem}.obj")
else:
    scene = bpy.context.scene
    span = scene.frame_end - scene.frame_start
    for i in range(frames):
        f = scene.frame_start + round(span * i / max(1, frames - 1)) \
            if span else scene.frame_start
        scene.frame_set(f)
        # bake the armature pose into the meshes for this frame
        deps = bpy.context.evaluated_depsgraph_get()
        export(out_dir / f"{src.stem}_f{i:02d}.obj")
        print(f"OK frame {i} (timeline {f})")
if muzzles:
    import json
    (out_dir / "muzzle.json").write_text(json.dumps(muzzles, indent=1))
    print(f"wrote muzzle.json ({len(muzzles)} poses)")
print("DONE")
