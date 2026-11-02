"""Bakes combat_r15.blend actions to Motor6D .rbxanim files through the Roblox Animations add-on.

    blender -b assets/blender/combat_r15/combat_r15.blend --factory-startup --python tools/blender/combat_bake.py -- <skill_scripts_dir> <out_dir> <Action> [...]

Headless. The animate-roblox-characters skill's `authentic_rig.enable_bundled_addon()` registers
the hash-checked add-on; the bake then follows the skill's `export_rbxanim()` steps directly,
because its authenticity gate does not recognise the add-on 3.x collection layout of this rig
(decision log, 2026-10-25). The head mesh's Armature modifier is detached for the bake so the
add-on keeps Motor6D serialization. Writes <out_dir>/<Action>.rbxanim; the .blend is not saved.
"""

import os
import sys

import bpy

args = sys.argv[sys.argv.index("--") + 1:]
sys.path.insert(0, args[0])

import authentic_rig  # noqa: E402

ARMATURE = "__AnimRigR15_Armature"

addon = authentic_rig.enable_bundled_addon()
if not addon.get("ok"):
    sys.exit("add-on unavailable: %s" % addon.get("errors"))

out, names = args[1], args[2:]
os.makedirs(out, exist_ok=True)
armature = bpy.data.objects[ARMATURE]
scene = bpy.context.scene
scene.rbx_anim_settings.rbx_anim_armature = ARMATURE
for track in armature.animation_data.nla_tracks:
    track.mute = True
for obj in scene.objects:
    for modifier in getattr(obj, "modifiers", []):
        if modifier.type == "ARMATURE" and modifier.object == armature:
            modifier.object = None
bpy.ops.object.select_all(action="DESELECT")
armature.select_set(True)
bpy.context.view_layer.objects.active = armature

for name in names:
    action = bpy.data.actions[name]
    armature.animation_data.action = action
    scene.frame_start, scene.frame_end = (int(round(x)) for x in action.frame_range)
    path = os.path.join(out, name + ".rbxanim")
    result = bpy.ops.object.rbxanims_bake_file(filepath=path)
    if "FINISHED" not in result or not os.path.getsize(path):
        sys.exit("bake failed for %s: %s" % (name, sorted(result)))
    print("baked", name, scene.frame_start, scene.frame_end)
