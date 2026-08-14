# Dump hand-bone world positions at each baked pose time of each clip -
# the ground truth half of the weapon-follow audit.
import json, sys
import bpy
argv = sys.argv[sys.argv.index("--") + 1:]
glb, times, bones_csv, out = argv[0], argv[1], argv[2], argv[3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
sc = bpy.context.scene
res = {}
for t in [float(v) for v in times.split(",")]:
    f = t * sc.render.fps
    sc.frame_set(int(f), subframe=f - int(f))
    bpy.context.view_layer.update()
    for bn in bones_csv.split(","):
        p = (arm.matrix_world @ arm.pose.bones[bn].matrix).to_translation()
        res.setdefault(bn, []).append([round(v, 5) for v in p])
json.dump(res, open(out, "w"), indent=1)
print("dumped", out)
