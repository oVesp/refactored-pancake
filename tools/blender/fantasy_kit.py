"""Fantasy Props MegaKit library for Roblox: the kit props the game places.

Run headless with Blender 5.2 from the repo root:

    "%BLENDER%" -b --factory-startup -P tools/blender/fantasy_kit.py -- [--render]

Writes:
    build/fantasy_kit.glb   one object per asset and material, named `<Asset>__<Material>`
    build/fantasy_kit.json  per asset: kind and bounds in metres (Roblox axes); materials
    build/fantasy_kit.sha   geometry hash, so the upload tool skips unchanged libraries

Reads the kit's plain glTF export (Quaternius, CC0), which is not in the repo, like the village kit.
Add a piece by naming it in ASSETS and uploading again; `Exports/glTF` holds 211 of them.

Roblox compatibility:
    - the kit's root textures already use OpenGL normals (DirectX ones are in Normals-UnrealEngine);
    - textures are scaled to 1024 px, the largest size Roblox keeps;
    - `_Vertex` materials tint the same trim sheet with vertex colours, which Roblox drops, so they
      merge into the base material; pieces whose look depends on the tint are left out (Sword_Bronze,
      fruit and vegetable crates); the white banner cloth gets its colour from SurfaceAppearance.Color;
    - the second UV set belongs to the kit's wear shader and is dropped.

Each asset keeps the kit's origin (a sword's is its grip). Axes are those of tools/blender/village_kit.py.
"""

import hashlib
import json
import os
import re
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import house_generator as hg  # noqa: E402
import village_kit as vk  # noqa: E402

KIT = os.path.join(hg.REPO, "assets", "third_party", "Fantasy Props MegaKit[Pro]", "Exports", "glTF")
OUT_DIR = os.path.join(hg.REPO, "build")
MAX_TEXTURE = 1024

# Asset name -> kind. `held` pieces become ReplicatedStorage.Weapons models, `map` pieces go in the
# Map through tools/world/build.luau, `dressing` pieces are placed by WorldGen/Harbor.luau.
ASSETS = {
    "Sword_Steel": "held",
    "Shield_Wooden": "held",
    "Dummy": "map",
    "CandleStick_Stand": "map",
    "Barrel": "dressing",
    "Bench": "dressing",
    "Banner_1": "dressing",
    "Banner_Vertical_1": "dressing",
    "Sign_Pub": "dressing",
    "Stall_Empty": "dressing",
    "Stall_Cart_Empty": "dressing",
    "Bucket_Wooden_1": "dressing",
    "Rope_1": "dressing",
    "Parchment": "dressing",
    "Lantern_Wall": "dressing",
    "Table_Large": "dressing",
    "Stool": "dressing",
}

# Settings copied into the manifest; the Studio import applies them, as for the village kit.
ROBLOX_MATERIALS = {
    "MI_Banner": {"tint": [58, 84, 128]},
}


def base_material(name):
    """`MI_Trim_Metal_Vertex.003` -> `MI_Trim_Metal`."""
    return re.sub(r"(_Vertex)?(\.\d+)?$", "", name)


def drop_vertex_tint(mat):
    """The importer multiplies base colour by COLOR_0 on every material of a tinted mesh; wires the
    texture straight in, since the colour attribute goes away."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    tints = [n for n in nodes if n.type in ("VERTEX_COLOR", "ATTRIBUTE")]
    if not tints:
        return
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    socket = bsdf.inputs["Base Color"]
    pending = [link.from_node for link in socket.links]
    texture = None
    while pending and not texture:
        node = pending.pop()
        if node.type == "TEX_IMAGE":
            texture = node
        else:
            pending.extend(link.from_node for s in node.inputs for link in s.links)
    if texture:
        links.new(texture.outputs["Color"], socket)
    for node in tints:
        nodes.remove(node)


def import_asset(name, shared):
    """Imports one kit piece as one object; materials are shared between pieces by base name."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(KIT, f"{name}.gltf"))
    meshes = [o for o in set(bpy.data.objects) - before if o.type == "MESH"]
    assert len(meshes) == 1, f"{name}: expected one mesh, got {len(meshes)}"
    obj = meshes[0]
    obj.name = name
    obj.data.name = name
    for extra in set(bpy.data.objects) - before - {obj}:
        bpy.data.objects.remove(extra)
    for k, mat in enumerate(obj.data.materials):
        base = base_material(mat.name)
        if base not in shared:
            mat.name = base
            drop_vertex_tint(mat)
            shared[base] = mat
        obj.data.materials[k] = shared[base]
    while len(obj.data.uv_layers) > 1:
        obj.data.uv_layers.remove(obj.data.uv_layers[-1])
    for attribute in list(obj.data.color_attributes):
        obj.data.color_attributes.remove(attribute)
    return obj


def fix_images():
    """At most 1024 px, packed so the exporter writes the changed pixels."""
    for img in bpy.data.images:
        if not img.filepath or img.size[0] == 0:
            continue
        if img.size[0] > MAX_TEXTURE or img.size[1] > MAX_TEXTURE:
            img.scale(min(img.size[0], MAX_TEXTURE), min(img.size[1], MAX_TEXTURE))
        img.pack()


def build():
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj)
    shared = {}
    assets = []
    for name, kind in ASSETS.items():
        obj = import_asset(name, shared)
        lo, hi = vk.bounds(obj)
        assets.append((obj, {"kind": kind, "min": lo, "max": hi}))
    return assets


def export(assets):
    os.makedirs(OUT_DIR, exist_ok=True)
    fix_images()
    materials = {}
    for obj, _ in assets:
        for mat in obj.data.materials:
            materials[mat.name] = ROBLOX_MATERIALS.get(mat.name, {})
    tris = {obj.name: vk.triangles(obj.data) for obj, _ in assets}
    entries = {obj.name: entry for obj, entry in assets}
    digest = hashlib.sha256()
    for obj, _ in sorted(assets, key=lambda a: a[0].name):
        digest.update(obj.name.encode())
        for v in obj.data.vertices:
            digest.update(("%.4f %.4f %.4f;" % tuple(v.co)).encode())
        for mat in obj.data.materials:
            digest.update(mat.name.encode())
    split = [part for obj, _ in assets for part in vk.split_by_material(obj)]
    bpy.ops.object.select_all(action="DESELECT")
    for part in split:
        part.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "fantasy_kit.glb"), use_selection=True,
                              export_format="GLB", export_texcoords=True, export_normals=True)
    manifest = {"source": "tools/blender/fantasy_kit.py", "unit": "metre", "front": "-Z",
                "materials": materials, "assets": entries}
    with open(os.path.join(OUT_DIR, "fantasy_kit.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent="\t", sort_keys=True)
        f.write("\n")
    digest.update(json.dumps(manifest, sort_keys=True).encode())
    with open(os.path.join(OUT_DIR, "fantasy_kit.sha"), "w", encoding="utf-8") as f:
        f.write(digest.hexdigest())
    worst = max(tris, key=tris.get)
    print(f"fantasy_kit: {len(assets)} assets, {len(split)} parts, max {tris[worst]} triangles ({worst})")


def render(assets):
    scene = bpy.context.scene
    hg.setup_render(scene)
    for k, (obj, _) in enumerate(assets):
        obj.location = ((k % 6) * 3.5, (k // 6) * 4.0, 0)
    cols_like = [type("C", (), {"objects": [o for o, _ in assets]})()]
    hg.render_view(scene, cols_like, os.path.join(OUT_DIR, "fantasy_kit.png"), (-0.35, -1.0, 0.6))
    for obj, _ in assets:
        obj.location = (0, 0, 0)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    assets = build()
    if "--render" in args:
        render(assets)
    export(assets)
