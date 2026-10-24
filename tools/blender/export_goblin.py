"""Writes the goblin rig data and placeholder animation clips for Roblox from goblin.blend.

Run inside Blender with assets/blender/goblin/goblin.blend open:
    exec(open(r"<repo>/tools/blender/export_goblin.py").read())

Outputs (both committed):
- tools/world/goblin_rig.json: bone tree in Roblox space, read by tools/world/build.luau.
- src/ReplicatedStorage/Animations/Goblin/*.rbxmx: KeyframeSequences used until clips are uploaded.

Blender bone space maps to Roblox bone space by conjugating with a 180 degree turn about Y;
translations scale by the importer's studs per metre. Size changes happen at spawn through
Model:ScaleTo, which keeps skinning and animation translations consistent.
"""

import math
import os

import bpy
from mathutils import Matrix

REPO = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
RIG_DATA = "GoblinRig"

# Studs per metre used by the Studio importer for Goblin.fbx (MeshPart.Size / MeshSize).
STUDS_PER_METRE = 2.935483
SCALE = STUDS_PER_METRE

# Root bone CFrame relative to the MeshPart, as created by the importer (unscaled).
ROOT_CFRAME = [0, -1.822832, 0.059765, 1, 0, 0, 0, 0, -1, 0, 1, 0]
MESH_SIZE = [1.518027, 1.238071, 0.480719]

# Clip -> (source action without the Goblin_ prefix, looped).
CLIPS = {
    "Idle": ("Idle_A", True),
    "Walk": ("Walk", True),
    "Run": ("Jog", True),
    "Attack": ("Punch_Jab", False),
    "Throw": ("OverhandThrow", False),
    "Hit": ("Hit_Chest", False),
    "Death": ("Death_B", False),
}
FRAME_STEP = 2

TURN = Matrix.Rotation(math.pi, 4, "Y")
TURN_INV = TURN.inverted()


def imported(bone):
    """Bones the Studio importer keeps: no leaf bones and no unweighted ring tips."""
    return "leaf" not in bone.name and bone.name not in ("ring_02_l", "ring_03_l", "ring_02_r", "ring_03_r")


def animated(bone):
    """Bones that get poses: imported bones minus finger joints past the first."""
    if not imported(bone) or bone.name.startswith("ring_"):
        return False
    for finger in ("index", "middle", "pinky", "thumb"):
        if bone.name.startswith(finger) and not bone.name.startswith(finger + "_01"):
            return False
    return True


def to_roblox(matrix, scale):
    m = TURN @ matrix @ TURN_INV
    t = m.translation * scale
    r = m.to_3x3()
    return [t.x, t.y, t.z] + [r[i][j] for i in range(3) for j in range(3)]


def num(x):
    if abs(x) < 1e-6:
        return "0"
    return ("%.5f" % x).rstrip("0").rstrip(".")


def write_rig(rig):
    import json

    bones = []

    def walk(bone):
        if not imported(bone):
            return
        if bone.parent is None:
            cframe = ROOT_CFRAME
        else:
            rest = bone.parent.matrix_local.inverted() @ bone.matrix_local
            cframe = to_roblox(rest, SCALE)
        bones.append({"name": bone.name, "parent": bone.parent.name if bone.parent else None,
                      "cframe": [round(v, 6) for v in cframe]})
        for child in bone.children:
            walk(child)

    walk(rig.data.bones["root"])
    data = {
        "source": "assets/blender/goblin/goblin.blend",
        # MeshPart.InitialSize is the mesh's native size; Size is what the importer gave it.
        "initialSize": MESH_SIZE,
        "size": [round(v * SCALE, 6) for v in MESH_SIZE],
        "rootHeight": round(-ROOT_CFRAME[1], 6),
        "bones": bones,
    }
    path = os.path.join(REPO, "tools", "world", "goblin_rig.json")
    with open(path, "w", encoding="utf8", newline="\n") as f:
        f.write(json.dumps(data, indent="\t") + "\n")


def cframe_xml(values):
    names = ["X", "Y", "Z"] + ["R%d%d" % (i, j) for i in range(3) for j in range(3)]
    return '<CoordinateFrame name="CFrame">%s</CoordinateFrame>' % "".join(
        "<%s>%s</%s>" % (n, num(v), n) for n, v in zip(names, values))


def write_clips(rig):
    out = os.path.join(REPO, "src", "ReplicatedStorage", "Animations", "Goblin")
    os.makedirs(out, exist_ok=True)
    identity = cframe_xml([0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1])
    counter = [0]

    def ref():
        counter[0] += 1
        return "RBX%d" % counter[0]

    def pose(name, cframe, children):
        return ('<Item class="Pose" referent="%s"><Properties><string name="Name">%s</string>%s'
                '<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
                '<float name="Weight">1</float></Properties>%s</Item>') % (ref(), name, cframe, "".join(children))

    scene = bpy.context.scene
    fps = scene.render.fps
    for clip, (source, looped) in CLIPS.items():
        action = bpy.data.actions["Goblin_" + source]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        first, last = int(action.frame_range[0]), int(math.ceil(action.frame_range[1]))
        frames = list(range(first, last + 1, FRAME_STEP))
        if frames[-1] != last:
            frames.append(last)

        keyframes = []
        for frame in frames:
            scene.frame_set(frame)

            def walk(bone):
                if not animated(bone):
                    return ""
                basis = Matrix.Identity(4) if bone.parent is None else rig.pose.bones[bone.name].matrix_basis
                return pose(bone.name, cframe_xml(to_roblox(basis, SCALE)), [walk(c) for c in bone.children])

            tree = pose("HumanoidRootPart", identity, [pose("Body", identity, [walk(rig.data.bones["root"])])])
            keyframes.append('<Item class="Keyframe" referent="%s"><Properties><string name="Name">Keyframe</string>'
                             '<float name="Time">%s</float></Properties>%s</Item>' % (ref(), num((frame - first) / fps), tree))

        name = "Goblin" + clip
        xml = ('<roblox version="4"><Item class="KeyframeSequence" referent="%s"><Properties>'
               '<string name="Name">%s</string><bool name="Loop">%s</bool><token name="Priority">%d</token>'
               '</Properties>%s</Item></roblox>\n') % (ref(), name, "true" if looped else "false",
                                                      0 if looped else 2, "".join(keyframes))
        with open(os.path.join(out, name + ".rbxmx"), "w", encoding="utf8", newline="\n") as f:
            f.write(xml)


def main():
    rig = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o.data.name == RIG_DATA)
    previous = (rig.animation_data.action, rig.animation_data.action_slot)
    write_rig(rig)
    write_clips(rig)
    rig.animation_data.action, rig.animation_data.action_slot = previous
    print("Goblin rig and clips written to", REPO)


main()
