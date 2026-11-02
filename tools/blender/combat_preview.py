"""Renders review stills or preview frames of combat_r15.blend actions (headless).

    blender -b assets/blender/combat_r15/combat_r15.blend --factory-startup --python tools/blender/combat_preview.py -- <out_dir> <mode> <Action> [...]

`review` renders the action's keyed frames from front, side and three-quarter views
(<Action>_<frame>_<view>.png). `frames` renders every frame through Preview_Camera
(<Action>/<frame>.png) for build_animation_preview.py. Review cameras are temporary and the
.blend is never saved.
"""

import os
import sys

import bpy
from mathutils import Vector

ARM = bpy.data.objects["__AnimRigR15_Armature"]
SCENE = bpy.context.scene
TARGET = Vector((0, 0, 2.6))
VIEWS = {"front": Vector((0, 9, 2.8)), "side": Vector((9, 0, 2.8)), "threequarter": Vector((6.0, 7.6, 4.9))}


def keyed_frames(action):
    frames = set()
    bags = ([bag for layer in action.layers for strip in layer.strips for bag in strip.channelbags]
            if hasattr(action, "layers") and len(action.layers) else [action])
    for bag in bags:
        for fc in bag.fcurves:
            frames.update(int(round(p.co[0])) for p in fc.keyframe_points)
    return sorted(frames)


def look_from(camera, position):
    camera.location = position
    camera.rotation_euler = (TARGET - position).to_track_quat("-Z", "Y").to_euler()


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    out, mode, names = args[0], args[1], args[2:]
    os.makedirs(out, exist_ok=True)
    camera = bpy.data.objects["Preview_Camera"]
    SCENE.camera = camera
    SCENE.render.image_settings.file_format = "PNG"
    SCENE.render.image_settings.color_mode = "RGB"
    for name in names:
        action = bpy.data.actions[name]
        ARM.animation_data.action = action
        if mode == "review":
            SCENE.render.resolution_x = SCENE.render.resolution_y = 320
            for frame in keyed_frames(action):
                SCENE.frame_set(frame)
                for view, position in VIEWS.items():
                    look_from(camera, position)
                    SCENE.render.filepath = os.path.join(out, "%s_%02d_%s.png" % (name, frame, view))
                    bpy.ops.render.render(write_still=True)
        else:
            SCENE.render.resolution_x = SCENE.render.resolution_y = 512
            start, end = (int(round(x)) for x in action.frame_range)
            for frame in range(start, end + 1):
                SCENE.frame_set(frame)
                SCENE.render.filepath = os.path.join(out, name, "%03d.png" % frame)
                bpy.ops.render.render(write_still=True)
        print("rendered", name)


main()
