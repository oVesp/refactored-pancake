"""Converts Motor6D .rbxanim bakes from assets/blender/combat_r15/ into KeyframeSequences.

The .rbxanim files come from combat_r15.blend through the Roblox Animations add-on
(object.rbxanims_bake_file, Motor6D mode); tools/blender/combat_bake.py bakes them headless. Run through the animation workflow (docs/art/animation-pipeline.md):
    python tools/anim/anim.py export Combat [clip ...]

Clips, sources, markers and looping come from content/animations/combat.json; outputs go to
src/ReplicatedStorage/Animations/Combat/*.rbxmx. Only animated joints get a weighted Pose; their R15 ancestors are written with Weight 0 so the
clip leaves the legs and hips to whatever locomotion track is playing underneath.
"""

import json
import os
import sys
import zlib

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANIFEST = os.path.join(REPO, "content", "animations", "combat.json")

# Enum.AnimationPriority.Action
PRIORITY_ACTION = 2

# R15 Motor6D tree by Part1 name.
R15_PARENT = {
    "LowerTorso": "HumanoidRootPart",
    "UpperTorso": "LowerTorso",
    "Head": "UpperTorso",
    "LeftUpperArm": "UpperTorso",
    "LeftLowerArm": "LeftUpperArm",
    "LeftHand": "LeftLowerArm",
    "RightUpperArm": "UpperTorso",
    "RightLowerArm": "RightUpperArm",
    "RightHand": "RightLowerArm",
    "LeftUpperLeg": "LowerTorso",
    "LeftLowerLeg": "LeftUpperLeg",
    "LeftFoot": "LeftLowerLeg",
    "RightUpperLeg": "LowerTorso",
    "RightLowerLeg": "RightUpperLeg",
    "RightFoot": "RightLowerLeg",
}
IDENTITY = [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1]


def num(x):
    if abs(x) < 1e-6:
        return "0"
    return ("%.5f" % x).rstrip("0").rstrip(".")


def cframe_xml(values):
    names = ["X", "Y", "Z"] + ["R%d%d" % (i, j) for i in range(3) for j in range(3)]
    return '<CoordinateFrame name="CFrame">%s</CoordinateFrame>' % "".join(
        "<%s>%s</%s>" % (n, num(v), n) for n, v in zip(names, values))


def write_clip(name, source, markers, looped, out):
    with open(source, "rb") as f:
        data = json.loads(zlib.decompress(f.read()))
    counter = [0]

    def ref():
        counter[0] += 1
        return "RBX%d" % counter[0]

    animated = set()
    for kf in data["kfs"]:
        animated.update(kf["kf"].keys())
    unknown = animated - set(R15_PARENT)
    if unknown:
        raise ValueError("%s animates non-R15 joints: %s" % (source, sorted(unknown)))

    # Joints that need a Pose: animated ones plus their ancestors.
    needed = set()
    for joint in animated:
        while joint in R15_PARENT:
            needed.add(joint)
            joint = R15_PARENT[joint]

    def pose(joint, frame):
        weighted = joint in frame
        values = frame[joint][0] if weighted else IDENTITY
        children = "".join(pose(c, frame) for c in sorted(needed) if R15_PARENT[c] == joint)
        return ('<Item class="Pose" referent="%s"><Properties><string name="Name">%s</string>%s'
                '<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
                '<float name="Weight">%d</float></Properties>%s</Item>') % (
                    ref(), joint, cframe_xml(values), 1 if weighted else 0, children)

    placed = set()
    keyframes = []
    for kf in data["kfs"]:
        time = kf["t"]
        marker_xml = ""
        for marker, at in markers.items():
            if abs(at - time) < 1e-3:
                placed.add(marker)
                marker_xml += ('<Item class="KeyframeMarker" referent="%s"><Properties>'
                               '<string name="Name">%s</string><string name="Value"></string>'
                               '</Properties></Item>') % (ref(), marker)
        root = ('<Item class="Pose" referent="%s"><Properties><string name="Name">HumanoidRootPart</string>%s'
                '<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
                '<float name="Weight">0</float></Properties>%s</Item>') % (
                    ref(), cframe_xml(IDENTITY),
                    "".join(pose(c, kf["kf"]) for c in sorted(needed) if R15_PARENT[c] == "HumanoidRootPart"))
        keyframes.append('<Item class="Keyframe" referent="%s"><Properties><string name="Name">Keyframe</string>'
                         '<float name="Time">%s</float></Properties>%s%s</Item>' % (ref(), num(time), root, marker_xml))
    missing = set(markers) - placed
    if missing:
        raise ValueError("%s has no keyframe at markers %s" % (source, sorted(missing)))

    xml = ('<roblox version="4"><Item class="KeyframeSequence" referent="%s"><Properties>'
           '<string name="Name">%s</string><bool name="Loop">%s</bool><token name="Priority">%d</token>'
           '</Properties>%s</Item></roblox>\n') % (
               ref(), name, "true" if looped else "false", PRIORITY_ACTION, "".join(keyframes))
    with open(os.path.join(out, name + ".rbxmx"), "w", encoding="utf8", newline="\n") as f:
        f.write(xml)


def main():
    with open(MANIFEST, encoding="utf8") as f:
        manifest = json.load(f)
    out = os.path.join(REPO, manifest["outDir"])
    os.makedirs(out, exist_ok=True)
    for name in sys.argv[1:] or list(manifest["clips"]):
        clip = manifest["clips"][name]
        source = os.path.join(REPO, manifest["sourceDir"], clip["source"])
        write_clip(clip.get("keyframes", name), source, clip.get("markers", {}), clip["looped"], out)
    print("Combat clips written to", out)


main()
