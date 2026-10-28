"""Writes KeyframeSequences from per-clip FBX files for an animation set whose exporter is "fbx".

Run through the animation workflow (docs/art/animation-pipeline.md):
    python tools/anim/anim.py export <set> [clip ...]
which calls:
    blender -b --factory-startup --python tools/blender/export_clips.py -- <manifest> <clip> [...]

Each clip's FBX is imported into an empty scene and its armature action is sampled every
`rig.frameStep` frames. Poses are written only for bones in the Roblox-side bone list
(`rig.bones`, taken from the Studio import), nested as in that list and wrapped in the
`rig.poseRoot` pose names. Blender bone space maps to Roblox bone space by conjugating with a
180 degree turn about Y; translations scale by `rig.studsPerMetre` times the armature's world
scale. Bones in `rig.lockedBones` stay at rest.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TURN = Matrix.Rotation(math.pi, 4, "Y")
TURN_INV = TURN.inverted()
IDENTITY = [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]
# Enum.AnimationPriority values: Core for loops, Action for one-shots (the client sets the real one).
PRIORITY_CORE, PRIORITY_ACTION = 0, 2


def num(x):
    if abs(x) < 1e-6:
        return "0"
    return ("%.5f" % x).rstrip("0").rstrip(".")


def to_roblox(matrix, scale):
    m = TURN @ matrix @ TURN_INV
    t = m.translation * scale
    r = m.to_3x3()
    return [t.x, t.y, t.z] + [r[i][j] for i in range(3) for j in range(3)]


def cframe_xml(values):
    names = ["X", "Y", "Z"] + ["R%d%d" % (i, j) for i in range(3) for j in range(3)]
    return '<CoordinateFrame name="CFrame">%s</CoordinateFrame>' % "".join(
        "<%s>%s</%s>" % (n, num(v), n) for n, v in zip(names, values))


class Writer:
    def __init__(self):
        self.counter = 0

    def ref(self):
        self.counter += 1
        return "RBX%d" % self.counter

    def pose(self, name, cframe, children):
        return ('<Item class="Pose" referent="%s"><Properties><string name="Name">%s</string>%s'
                '<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
                '<float name="Weight">1</float></Properties>%s</Item>') % (
                    self.ref(), name, cframe, "".join(children))


def import_clip(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if len(armatures) != 1:
        sys.exit("%s: expected one armature, found %d" % (path, len(armatures)))
    rig = armatures[0]
    if not rig.animation_data or not rig.animation_data.action:
        sys.exit("%s: armature has no action" % path)
    return rig, rig.animation_data.action


def export_clip(manifest, key, clip, bones):
    rig_spec = manifest["rig"]
    rig, action = import_clip(os.path.join(REPO, manifest["sourceDir"], clip["source"]))
    missing = [name for name in bones if name not in rig.data.bones]
    if missing:
        sys.exit("%s: Roblox bones missing from the FBX armature: %s" % (key, ", ".join(missing[:10])))
    scale = rig_spec["studsPerMetre"] * rig.matrix_world.to_scale().x
    locked = set(rig_spec.get("lockedBones", []))
    children = {}
    for name, parent in bones.items():
        children.setdefault(parent, []).append(name)

    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    first, last = int(action.frame_range[0]), int(math.ceil(action.frame_range[1]))
    frames = list(range(first, last + 1, rig_spec.get("frameStep", 2)))
    if frames[-1] != last:
        frames.append(last)

    writer = Writer()
    identity = cframe_xml(IDENTITY)
    keyframes = []
    for frame in frames:
        scene.frame_set(frame)

        def walk(name):
            basis = Matrix.Identity(4) if name in locked else rig.pose.bones[name].matrix_basis
            return writer.pose(name, cframe_xml(to_roblox(basis, scale)), [walk(c) for c in children.get(name, [])])

        tree = [walk(name) for name in children.get(None, [])]
        for wrapper in reversed(rig_spec.get("poseRoot", [])):
            tree = [writer.pose(wrapper, identity, tree)]
        keyframes.append('<Item class="Keyframe" referent="%s"><Properties><string name="Name">Keyframe</string>'
                         '<float name="Time">%s</float></Properties>%s</Item>' % (
                             writer.ref(), num((frame - first) / fps), "".join(tree)))

    name = clip.get("keyframes", key)
    looped = clip["looped"]
    xml = ('<roblox version="4"><Item class="KeyframeSequence" referent="%s"><Properties>'
           '<string name="Name">%s</string><bool name="Loop">%s</bool><token name="Priority">%d</token>'
           '</Properties>%s</Item></roblox>\n') % (writer.ref(), name, "true" if looped else "false",
                                                  PRIORITY_CORE if looped else PRIORITY_ACTION, "".join(keyframes))
    out = os.path.join(REPO, manifest["outDir"])
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, name + ".rbxmx"), "w", encoding="utf8", newline="\n") as f:
        f.write(xml)
    print("%s: %d keyframes" % (key, len(frames)))


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    with open(args[0], encoding="utf8") as f:
        manifest = json.load(f)
    with open(os.path.join(REPO, manifest["rig"]["bones"]), encoding="utf8") as f:
        bones = {bone["name"]: bone["parent"] for bone in json.load(f)["bones"]}
    for key in args[1:]:
        export_clip(manifest, key, manifest["clips"][key], bones)


main()
