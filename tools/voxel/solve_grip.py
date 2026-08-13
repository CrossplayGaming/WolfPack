"""Solve a weapon's grip ROTATION instead of sweeping for it by eye.

    blender --background --python tools/voxel/solve_grip.py -- \
        char.glb gun.glb --time 0.295 [--bone RightHand] [--axis x]

A grip has seven numbers but only three of them are hard to see: the
rotation. The other four follow from geometry - scale from the gun's
authored length, offset from where along the barrel a hand belongs.

The rotation has an objective test, so it does not need an eye: in the
FIRING pose the barrel must point where the character is aiming. This
searches bone-space rotations for the one that puts the gun's long axis
along the body's forward direction and keeps it level, and prints the
grip line to use. Judge the result on a strip; do not judge candidates
one at a time.
"""
import math, sys
import bpy
from mathutils import Euler, Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
char, gun = argv[0], argv[1]
t = float(argv[argv.index("--time") + 1]) if "--time" in argv else 0.0
bone = argv[argv.index("--bone") + 1] if "--bone" in argv else "RightHand"
# signed: "-x" means the MUZZLE is at the mesh's minimum X. Getting this
# wrong points the gun backwards, which is exactly what happened on the
# first pass - the solver dutifully aimed the stock forwards.
axis = argv[argv.index("--axis") + 1] if "--axis" in argv else "x"
sign = -1.0 if axis.startswith("-") else 1.0
AX = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)),
      "z": Vector((0, 0, 1))}[axis.lstrip("+-")] * sign

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=char)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=gun)
gunobj = [o for o in bpy.data.objects if o not in before and o.type == "MESH"][0]

sc = bpy.context.scene
sc.frame_set(sc.frame_start + round(t * sc.render.fps))
bpy.context.view_layer.update()

# character forward: the exporter treats -Y as forward, and the hips
# bone confirms which way the body actually faces at this moment
hips = (arm.matrix_world @ arm.pose.bones["Hips"].matrix)
fwd = Vector((0, -1, 0))
up = Vector((0, 0, 1))

pb = arm.pose.bones[bone]
bone_m = arm.matrix_world @ pb.matrix
k = bone_m.to_scale(); k = (k.x + k.y + k.z) / 3

# gun length along its own long axis, in metres, before grip scale
co = [gunobj.matrix_world @ v.co for v in gunobj.data.vertices]
proj = [c.dot(AX) for c in co]
length = max(proj) - min(proj)

# Which way does the GRIP hang? Roll about the barrel was unconstrained
# on the first pass, so the gun came out with its grips in the air. A
# gun's mass sits below its bore - grip, magazine, trigger guard - so
# the centroid is offset from the bounding-box centre in the direction
# the grip points. That gives the roll an objective test too.
ctr = sum(co, Vector()) / len(co)
lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
box = (lo + hi) / 2
d = ctr - box
d = d - AX * d.dot(AX)                      # perpendicular to the barrel
GRIPDIR = d.normalized() if d.length > 1e-6 else Vector((0, 0, -1))
print("GRIPDIR (%.2f,%.2f,%.2f) offset %.4f m" % (GRIPDIR.x, GRIPDIR.y,
                                                  GRIPDIR.z, d.length))

best = None
step = 15
for rx in range(0, 360, step):
    for ry in range(0, 360, step):
        for rz in range(0, 360, step):
            R = Euler([math.radians(rx), math.radians(ry), math.radians(rz)],
                      "XYZ").to_matrix().to_4x4()
            rot3 = bone_m.to_3x3().normalized() @ R.to_3x3()
            world_dir = (rot3 @ AX).normalized()
            world_grip = (rot3 @ GRIPDIR).normalized()
            # want: barrel along forward and level, grip hanging DOWN
            err = ((1 - world_dir.dot(fwd)) + abs(world_dir.dot(up))
                   + (1 - world_grip.dot(-up)))
            if best is None or err < best[0]:
                best = (err, rx, ry, rz, world_dir.copy())

# refine around the coarse winner at 3-degree resolution
c = best
for dx in range(-14, 15, 3):
    for dy in range(-14, 15, 3):
        for dz in range(-14, 15, 3):
            rx, ry, rz = c[1] + dx, c[2] + dy, c[3] + dz
            R = Euler([math.radians(rx), math.radians(ry), math.radians(rz)],
                      "XYZ").to_matrix().to_4x4()
            rot3 = bone_m.to_3x3().normalized() @ R.to_3x3()
            wd = (rot3 @ AX).normalized()
            wg = (rot3 @ GRIPDIR).normalized()
            err = ((1 - wd.dot(fwd)) + abs(wd.dot(up)) + (1 - wg.dot(-up)))
            if err < best[0]:
                best = (err, rx, ry, rz, wd.copy())

err, rx, ry, rz, d = best
# --roll: spin the gun about its own barrel by hand. The grip direction
# is detected from where the mesh's mass hangs off the bore, which is a
# weak signal on a slim weapon (0.04 m on a 1.9 m gun), so if it lands
# upside down this is the one-number fix - no re-solve, no re-sweep.
roll = float(argv[argv.index("--roll") + 1]) if "--roll" in argv else 0.0
if roll:
    R0 = Euler([math.radians(rx), math.radians(ry), math.radians(rz)],
               "XYZ").to_matrix()
    spin = Matrix.Rotation(math.radians(roll), 3, (R0 @ AX).normalized())
    e = (spin @ R0).to_euler("XYZ")
    rx, ry, rz = (round(math.degrees(e.x)), round(math.degrees(e.y)),
                  round(math.degrees(e.z)))
    print("ROLL %+.0f deg -> rot (%d,%d,%d)" % (roll, rx, ry, rz))
# scale: the target barrel length in metres over the authored length
target = float(argv[argv.index("--length") + 1]) if "--length" in argv else 0.76
s_grip = target / length
# offset: the mesh origin is the gun's CENTRE, so slide it along its own
# barrel until the hand sits GRIPFRAC of the way back from the muzzle
gripfrac = float(argv[argv.index("--gripfrac") + 1])     if "--gripfrac" in argv else 0.30
R = Euler([math.radians(rx), math.radians(ry), math.radians(rz)],
          "XYZ").to_matrix()
barrel_bone = (R @ AX).normalized()          # barrel direction in BONE space
off = barrel_bone * ((0.5 - gripfrac) * target)

print("GUNLEN %.3f m (axis %s)" % (length, axis))
print("BEST rot (%d,%d,%d) err=%.4f barrel dir (%.2f,%.2f,%.2f)"
      % (rx, ry, rz, err, d.x, d.y, d.z))
print("BONESCALE %.4f" % k)
print("GRIP %.4f,%.4f,%.4f,%d,%d,%d,%.4f"
      % (off.x, off.y, off.z, rx, ry, rz, s_grip))
