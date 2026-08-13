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
import sys
from pathlib import Path

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src = Path(argv[0]).resolve()
out_dir = Path(argv[1]).resolve()
frames = int(argv[argv.index("--sample-frames") + 1]) \
    if "--sample-frames" in argv else 0
# --times: explicit moments in SECONDS, straight from frame_picker.html
# (Eric picks poses by eye; seconds are unambiguous across fps guesses)
times = [float(t) for t in argv[argv.index("--times") + 1].split(",")] \
    if "--times" in argv else []
out_dir.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(src))

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
print("DONE")
