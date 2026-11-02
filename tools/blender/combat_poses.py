"""Authors the light chain and guard clips on the R15 rig in assets/blender/combat_r15/combat_r15.blend.

Run headless from the repo root (the add-on is not needed for authoring):
    blender -b assets/blender/combat_r15/combat_r15.blend --factory-startup --python tools/blender/combat_poses.py

Writes the Strike2, Strike3, GuardHold and GuardParry actions (upper body only, Bezier keys) and
saves the .blend. Poses are written as world-space aims: each arm bone is swung from its
parent-inherited orientation so its head-to-tail axis points along a direction, and the torso and
head are twisted or leaned in armature space. Armature space: +Y is the character's front, +X its
right side, +Z up. The .rbxanim bake and preview renders are separate steps (combat_bake.py).
"""

import math
import sys

import bpy
from mathutils import Euler, Quaternion, Vector

ARM = bpy.data.objects["__AnimRigR15_Armature"]
UPPER = ["UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperArm", "RightLowerArm", "RightHand"]


def update():
    bpy.context.view_layer.update()


def reset():
    for name in UPPER:
        ARM.pose.bones[name].rotation_quaternion = Quaternion()
    update()


def turn(bone, twist=0.0, lean=0.0, roll=0.0):
    """Rotates a bone in armature space by degrees: `twist` about +Z (positive brings the left
    shoulder back and the right one forward), `lean` about -X (positive tips toward the front),
    `roll` about +Y (positive drops the right shoulder)."""
    pb = ARM.pose.bones[bone]
    rotation = Euler((math.radians(-lean), math.radians(roll), math.radians(twist)), "ZXY").to_matrix().to_4x4()
    matrix = pb.matrix.copy()
    head = matrix.translation.copy()
    turned = rotation @ matrix
    turned.translation = head
    pb.matrix = turned
    update()


def aim(bone, direction):
    """Points a bone's head-to-tail axis along `direction` with the smallest swing from the
    orientation its parent gives it."""
    pb = ARM.pose.bones[bone]
    pb.rotation_quaternion = Quaternion()
    update()
    matrix = pb.matrix.copy()
    current = (matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
    swing = current.rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()
    head = matrix.translation.copy()
    aimed = swing @ matrix
    aimed.translation = head
    pb.matrix = aimed
    update()


# Poses. Each starts from the rest pose.

def rest():
    pass


def guard(breath=0.0):
    """Block: elbows forward, forearms upright in front of the face, chin tucked."""
    turn("UpperTorso", lean=6 + breath)
    aim("LeftUpperArm", (0.08, 0.85, -0.45 - breath * 0.02))
    aim("LeftLowerArm", (0.22, 0.05, 0.97))
    aim("RightUpperArm", (-0.08, 0.85, -0.45 - breath * 0.02))
    aim("RightLowerArm", (-0.22, 0.05, 0.97))
    turn("Head", lean=10 + breath * 0.5)


def cross_load():
    """Strike2 anticipation: left shoulder pulled back, left fist cocked at the chin."""
    turn("UpperTorso", twist=22, lean=4)
    aim("LeftUpperArm", (-0.35, -0.25, -0.90))
    aim("LeftLowerArm", (0.15, 0.55, 0.82))
    aim("RightUpperArm", (0.15, 0.55, -0.82))
    aim("RightLowerArm", (-0.15, 0.40, 0.90))
    turn("Head", twist=-20)


def cross_hit():
    """Strike2 contact: shoulders turned through, left arm straight across the centre line."""
    turn("UpperTorso", twist=-38, lean=10)
    aim("LeftUpperArm", (0.30, 1.0, 0.10))
    aim("LeftLowerArm", (0.28, 1.0, 0.12))
    aim("RightUpperArm", (0.10, 0.10, -0.99))
    aim("RightLowerArm", (-0.10, 0.55, 0.83))
    turn("Head", twist=36, lean=4)


def cross_follow():
    turn("UpperTorso", twist=-44, lean=8)
    aim("LeftUpperArm", (0.40, 0.90, -0.05))
    aim("LeftLowerArm", (0.30, 0.85, 0.30))
    aim("RightUpperArm", (0.08, 0.05, -1.0))
    aim("RightLowerArm", (-0.10, 0.50, 0.86))
    turn("Head", twist=40, lean=3)


def cross_settle():
    turn("UpperTorso", twist=-10, lean=3)
    aim("LeftUpperArm", (-0.05, 0.25, -0.97))
    aim("LeftLowerArm", (0.10, 0.40, -0.91))
    turn("Head", twist=8)


def hook_load():
    """Strike3 anticipation: torso dipped and turned away, right fist dropped low and back."""
    turn("UpperTorso", twist=-30, lean=18, roll=-10)
    aim("RightUpperArm", (0.45, -0.35, -0.82))
    aim("RightLowerArm", (0.05, 0.75, 0.10))
    aim("LeftUpperArm", (-0.15, 0.45, -0.88))
    aim("LeftLowerArm", (0.30, 0.45, 0.84))
    turn("Head", twist=20, lean=-4)


def hook_hit():
    """Strike3 contact: torso rises and turns through, right fist drives up at chin height."""
    turn("UpperTorso", twist=36, lean=-6, roll=8)
    aim("RightUpperArm", (-0.15, 0.85, 0.15))
    aim("RightLowerArm", (-0.45, 0.55, 0.70))
    aim("LeftUpperArm", (-0.30, -0.10, -0.95))
    aim("LeftLowerArm", (0.10, 0.35, 0.93))
    turn("Head", twist=-22, lean=-6)


def hook_over():
    turn("UpperTorso", twist=46, lean=-10, roll=10)
    aim("RightUpperArm", (-0.25, 0.75, 0.40))
    aim("RightLowerArm", (-0.55, 0.35, 0.76))
    aim("LeftUpperArm", (-0.35, -0.20, -0.92))
    aim("LeftLowerArm", (0.05, 0.25, 0.97))
    turn("Head", twist=-26, lean=-8)


def hook_recover():
    turn("UpperTorso", twist=18, lean=8, roll=2)
    aim("RightUpperArm", (0.05, 0.30, -0.95))
    aim("RightLowerArm", (-0.05, 0.55, -0.83))
    aim("LeftUpperArm", (-0.10, 0.15, -0.98))
    aim("LeftLowerArm", (0.05, 0.30, -0.95))
    turn("Head", twist=-8, lean=6)


def hook_settle():
    turn("UpperTorso", twist=4, lean=3)
    aim("RightUpperArm", (0.02, 0.08, -1.0))
    turn("Head", twist=-2, lean=2)


def parry_out():
    """GuardParry: left forearm swings outward off the centre line."""
    turn("UpperTorso", twist=14, lean=4)
    aim("LeftUpperArm", (-0.55, 0.75, -0.35))
    aim("LeftLowerArm", (-0.75, 0.50, 0.45))
    aim("RightUpperArm", (-0.08, 0.85, -0.45))
    aim("RightLowerArm", (-0.22, 0.05, 0.97))
    turn("Head", twist=-10, lean=6)


def parry_wide():
    turn("UpperTorso", twist=18, lean=2)
    aim("LeftUpperArm", (-0.80, 0.50, -0.30))
    aim("LeftLowerArm", (-0.90, 0.20, 0.40))
    aim("RightUpperArm", (-0.08, 0.85, -0.45))
    aim("RightLowerArm", (-0.22, 0.05, 0.97))
    turn("Head", twist=-12, lean=5)


# Action -> [(frame, pose, kwargs)] at 30 FPS. Markers live in content/animations/combat.json.
PLANS = {
    "Strike2": [(0, rest, {}), (2, cross_load, {}), (4, cross_hit, {}), (7, cross_follow, {}),
                (9, cross_settle, {}), (12, rest, {})],
    "Strike3": [(0, rest, {}), (3, hook_load, {}), (7, hook_hit, {}), (10, hook_over, {}),
                (14, hook_recover, {}), (16, hook_settle, {}), (18, rest, {})],
    "GuardHold": [(0, guard, {}), (15, guard, {"breath": 2.0}), (30, guard, {})],
    "GuardParry": [(0, guard, {}), (2, parry_out, {}), (5, parry_wide, {}), (10, guard, {})],
}


def fcurves(action):
    if hasattr(action, "layers") and len(action.layers):
        return [fc for layer in action.layers for strip in layer.strips
                for bag in strip.channelbags for fc in bag.fcurves]
    return list(action.fcurves)


def build(name):
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    ARM.animation_data.action = action
    previous = {}
    for frame, pose, kwargs in PLANS[name]:
        reset()
        pose(**kwargs)
        for bone in UPPER:
            pb = ARM.pose.bones[bone]
            q = pb.rotation_quaternion.normalized()
            # Keep neighbouring keys in the same hemisphere so Bezier curves take the short way.
            if bone in previous and previous[bone].dot(q) < 0:
                q.negate()
            previous[bone] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone)
    for fc in fcurves(action):
        for point in fc.keyframe_points:
            point.interpolation = "BEZIER"
            point.handle_left_type = "AUTO_CLAMPED"
            point.handle_right_type = "AUTO_CLAMPED"
        fc.update()
    return action


def main():
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(PLANS)
    keep = ARM.animation_data.action
    for name in names:
        build(name)
        print("built", name)
    ARM.animation_data.action = keep
    reset()
    bpy.ops.wm.save_mainfile()


main()
