"""Village kit for Roblox: MegaKit houses, kit props and matching custom structures.

Run headless with Blender 5.2 from the repo root:

    "%BLENDER%" -b --factory-startup -P tools/blender/village_kit.py -- [--render]

Writes:
    build/village_kit.glb   one object per asset, origin at its footprint centre on the ground
    build/village_kit.json  per asset: kind, footprint and bounds in metres (Roblox axes), anchors
    build/village_kit.sha   geometry hash, so the upload tool skips unchanged libraries

Houses and barns come from tools/blender/house_generator.py. Fences, crates, the wagon and stone
borders are MegaKit pieces. Wells, braziers, scarecrows, palisades, gate towers, tents and the dais
are built here on the kit's own materials, with UVs placed on the matching trim-sheet strips.

Roblox compatibility (the kit targets engines with its own shaders):
    - normal maps come from the kit's OpenGL set (`Normals Godot-Unity`); the default set is
      DirectX-style and lights upside down in Roblox;
    - textures are scaled to 1024 px, the largest size Roblox keeps;
    - MI_WoodTrim_Wear uses the WoodTrim textures plus a wear overlay that needs the kit shader and a
      second UV set; it is merged into MI_WoodTrim and extra UV sets are dropped;
    - each asset is exported as one object per material, named `<Asset>__<Material>`, so Roblox
      makes one MeshPart per material (not one per kit piece) and the part names keep the material;
    - Roblox drops the base colour of untextured materials, so the manifest lists every material
      with its colour and whether it has textures; the Studio import applies the colours.

Roblox axes in the manifest: X = -Blender X, Y = Blender Z (up), Z = Blender Y, measured by uploading
marker cubes (the Roblox glTF import turns the glTF frame half a turn about Y). Every asset's front
faces Blender -Y, which is Roblox -Z.
"""

import hashlib
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import house_generator as hg  # noqa: E402

OUT_DIR = os.path.join(hg.REPO, "build")
NORMALS = os.path.join(hg.DEFAULT_KIT, "Textures", "Normals Godot-Unity")
MAX_TEXTURE = 1024
SEED = 20261029

HOUSE_SEEDS = list(range(1, 11))
BARNS = [(101, 8, 14), (102, 8, 12)]  # seed, width, depth; one story

# Kit pieces exported as they are: asset name -> kit piece.
KIT_PROPS = {
    "Fence": "Prop_WoodenFence_Single",
    "Crate": "Prop_Crate",
    "Wagon": "Prop_Wagon",
    "Border": "Prop_ExteriorBorder_Straight1",
    "BorderCorner": "Prop_ExteriorBorder_Corner",
}

# Kit pieces are modelled for desktop engines: a rounded window is about 1,100 triangles and a
# rubble corner about 3,100, so a three-story house reaches 45,000, over Roblox's 20,000 per mesh.
# Heavy pieces are decimated once in the library (every copy shares the result); interior floors
# are dropped because the houses are closed. Ratios per piece-name prefix; first match wins.
DECIMATE = [
    ("Roof_", 0.5),
    ("Corner_Exterior_Brick", 0.2),
    ("Window_", 0.25),
    ("WindowShutters_", 0.3),
    ("Wall_", 0.45),
    ("Door_", 0.5),
]
DECIMATE_MIN_TRIS = 300
SKIP_PIECES = ("Floor_",)

# Roblox settings per material where the import alone falls short: untextured materials need a
# Roblox material and colour, the leaf texture needs alpha cut-out. Copied into the manifest.
ROBLOX_MATERIALS = {
    "MI_WindowGlass": {"material": "Glass", "color": [138, 168, 180], "transparency": 0.35},
    "MI_MetalOrnaments": {"material": "Metal", "color": [64, 60, 56]},
    # The kit tints the grey leaf texture in its shader; Roblox tints through SurfaceAppearance.Color.
    "MI_Vine": {"alphaMode": "Transparency", "tint": [92, 132, 70]},
    "MI_Canvas": {"material": "Fabric"},
    "MI_CanvasDark": {"material": "Fabric"},
    "MI_Cloth": {"material": "Fabric"},
    "MI_Sack": {"material": "Fabric"},
    "MI_Straw": {"material": "Grass"},
}

# Trim-sheet strips (v from, v to) measured on the 2048 px base colour maps.
WOOD_LIGHT = (0.71, 0.99)
WOOD_DARK = (0.42, 0.68)
WOOD_END = (0.23, 0.37)
ROCK_RUBBLE = (0.70, 0.99)
ROCK_SLAB = (0.43, 0.67)
ROCK_BRICK = (0.02, 0.40)
DENSITY = 0.5  # UV units per metre, as on the kit walls


# ---------------------------------------------------------------- geometry helpers

class Mesh:
    """Collects faces with a material and UVs into one bmesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.materials = []

    def material(self, mat):
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def face(self, points, uvs, mat):
        verts = [self.bm.verts.new(p) for p in points]
        f = self.bm.faces.new(verts)
        f.material_index = self.material(mat)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def to_object(self, name):
        mesh = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.materials:
            mesh.materials.append(m)
        for poly in mesh.polygons:
            poly.use_smooth = False
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def band(v, strip):
    """Maps 0..1 across a strip's height."""
    return strip[0] + (strip[1] - strip[0]) * v


def log(m, mat, strip, a, b, radius, sides=7, tip=0.0, end=WOOD_END):
    """A round post from point a to point b; `tip` > 0 sharpens the top end into a point."""
    axis = (b - a)
    length = axis.length
    axis.normalize()
    side = axis.orthogonal().normalized()
    other = axis.cross(side).normalized()
    ring = lambda centre, r: [centre + (side * math.cos(t) + other * math.sin(t)) * r
                              for t in (k * math.tau / sides for k in range(sides))]
    body_end = b - axis * tip
    lo, hi = ring(a, radius), ring(body_end, radius)
    u_len = length * DENSITY
    for k in range(sides):
        n = (k + 1) % sides
        v0, v1 = band(k / sides, strip), band((k + 1) / sides, strip)
        m.face([lo[k], lo[n], hi[n], hi[k]], [(0, v0), (0, v1), (u_len, v1), (u_len, v0)], mat)
    cap = [Vector((0.5 + 0.5 * math.cos(k * math.tau / sides), 0.5 + 0.5 * math.sin(k * math.tau / sides)))
           for k in range(sides)]
    end_uv = [(0.17 + 0.15 * c.x, band(c.y, end)) for c in cap]
    m.face(list(reversed(lo)), list(reversed(end_uv)), mat)
    if tip > 0:
        for k in range(sides):
            n = (k + 1) % sides
            m.face([hi[k], hi[n], b], [(0.17, band(0.2, end)), (0.32, band(0.2, end)), (0.25, band(0.9, end))], mat)
    else:
        m.face(hi, end_uv, mat)


def box(m, mat, strip, centre, size, rot=0.0, tilt=0.0):
    """A box turned `rot` radians about Z and `tilt` about its own X, with strip UVs on every face."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    turn = Matrix.Rotation(rot, 3, "Z") @ Matrix.Rotation(tilt, 3, "X")
    corner = lambda x, y, z: centre + turn @ Vector((x, y, z))
    faces = [
        ((-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), size[0], size[2]),
        ((hx, hy, -hz), (-hx, hy, -hz), (-hx, hy, hz), (hx, hy, hz), size[0], size[2]),
        ((hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz), (hx, -hy, hz), size[1], size[2]),
        ((-hx, hy, -hz), (-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz), size[1], size[2]),
        ((-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz), size[0], size[1]),
        ((-hx, hy, -hz), (hx, hy, -hz), (hx, -hy, -hz), (-hx, -hy, -hz), size[0], size[1]),
    ]
    for p0, p1, p2, p3, w, h in faces:
        u = w * DENSITY
        m.face([corner(*p0), corner(*p1), corner(*p2), corner(*p3)],
               [(0, strip[0]), (u, strip[0]), (u, strip[1]), (0, strip[1])], mat)


def ring_wall(m, mat, strip, centre, outer, inner, height, sides=12):
    """A round wall (well ring, fire pit) with a flat top."""
    pts = lambda r, z: [centre + Vector((r * math.cos(k * math.tau / sides), r * math.sin(k * math.tau / sides), z))
                        for k in range(sides)]
    ob, ot, ib, it = pts(outer, 0), pts(outer, height), pts(inner, 0), pts(inner, height)
    step = math.tau * outer / sides * DENSITY
    for k in range(sides):
        n = (k + 1) % sides
        m.face([ob[k], ob[n], ot[n], ot[k]], [(k * step, strip[0]), ((k + 1) * step, strip[0]),
                                              ((k + 1) * step, strip[1]), (k * step, strip[1])], mat)
        m.face([ib[n], ib[k], it[k], it[n]], [(k * step, strip[0]), ((k + 1) * step, strip[0]),
                                              ((k + 1) * step, strip[1]), (k * step, strip[1])], mat)
        m.face([ot[k], ot[n], it[n], it[k]], [(k * step, ROCK_SLAB[0]), ((k + 1) * step, ROCK_SLAB[0]),
                                              ((k + 1) * step, ROCK_SLAB[1]), (k * step, ROCK_SLAB[1])], mat)


def prism(m, mat, strip, centre, radius_bottom, radius_top, height, sides=8):
    """A tapered column with a top cap (brazier stand, bowl)."""
    bot = [centre + Vector((radius_bottom * math.cos(k * math.tau / sides), radius_bottom * math.sin(k * math.tau / sides), 0))
           for k in range(sides)]
    top = [centre + Vector((radius_top * math.cos(k * math.tau / sides), radius_top * math.sin(k * math.tau / sides), height))
           for k in range(sides)]
    step = math.tau * max(radius_bottom, radius_top) / sides * DENSITY
    for k in range(sides):
        n = (k + 1) % sides
        m.face([bot[k], bot[n], top[n], top[k]], [(k * step, strip[0]), ((k + 1) * step, strip[0]),
                                                  ((k + 1) * step, strip[1]), (k * step, strip[1])], mat)
    m.face(top, [(0.5 + 0.2 * math.cos(k * math.tau / sides), band(0.5 + 0.4 * math.sin(k * math.tau / sides), ROCK_SLAB))
                 for k in range(sides)], mat)
    m.face(list(reversed(bot)), [(0, ROCK_SLAB[0])] * sides, mat)


def sheet(m, points, uvs, mat, thickness=0.05):
    """A thin two-sided panel: Roblox draws one side of a face only, so cloth needs a back."""
    a, b, c = points[0], points[1], points[2]
    normal = (b - a).cross(c - a).normalized()
    m.face(points, uvs, mat)
    back = [p - normal * thickness for p in reversed(points)]
    m.face(back, list(reversed(uvs)), mat)


def flat_material(name, rgb):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*[c / 255 for c in rgb], 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


# ---------------------------------------------------------------- custom structures
# Each returns (object, anchors); anchors are named points in metres in the asset's frame.

def well(mats):
    m = Mesh()
    ring_wall(m, mats["rock"], ROCK_RUBBLE, Vector((0, 0, 0)), 1.25, 0.95, 0.85, 14)
    for x in (-1.15, 1.15):
        log(m, mats["wood"], WOOD_DARK, Vector((x, 0, 0)), Vector((x, 0, 2.6)), 0.11)
    log(m, mats["wood"], WOOD_DARK, Vector((-1.4, 0, 2.45)), Vector((1.4, 0, 2.45)), 0.09)
    # A small pitched roof of two boards over the beam.
    for side in (-1, 1):
        box(m, mats["wood"], WOOD_LIGHT, Vector((0, side * 0.5, 2.78)), (3.0, 1.15, 0.08), 0, side * 0.55)
    return m.to_object("Well"), {"water": [0.0, 0.6, 0.0], "waterRadius": 0.95}


def brazier(mats):
    m = Mesh()
    prism(m, mats["rock"], ROCK_BRICK, Vector((0, 0, 0)), 0.42, 0.3, 0.9, 8)
    prism(m, mats["rock"], ROCK_SLAB, Vector((0, 0, 0.9)), 0.32, 0.62, 0.32, 8)
    return m.to_object("Brazier"), {"bowl": [0.0, 1.22, 0.0], "bowlRadius": 0.55}


def scarecrow(mats, variant, rng):
    m = Mesh()
    lean = rng.uniform(-0.12, 0.12)
    top = Vector((lean, 0, 2.6))
    log(m, mats["wood"], WOOD_LIGHT, Vector((0, 0, -0.2)), top, 0.07)
    arms = 1.9 if variant == 1 else 1.6
    log(m, mats["wood"], WOOD_LIGHT, Vector((-arms / 2 + lean * 0.7, 0, 1.95)), Vector((arms / 2 + lean * 0.7, 0, 1.95)), 0.05)
    box(m, mats["cloth"], WOOD_DARK, Vector((lean * 0.6, 0, 1.55)), (0.75, 0.38, 0.95), rng.uniform(-0.1, 0.1))
    box(m, mats["sack"], WOOD_DARK, Vector((lean * 0.9, 0, 2.3)), (0.42, 0.38, 0.42), rng.uniform(-0.3, 0.3))
    box(m, mats["straw"], WOOD_DARK, Vector((lean * 0.95, 0, 2.58)), (0.62, 0.62, 0.08), rng.uniform(0, 1))
    return m.to_object(f"Scarecrow{variant}"), {}


def palisade(mats, variant, rng):
    """A 4 m wall segment of sharpened logs along X."""
    m = Mesh()
    count = 7
    for k in range(count):
        x = -2.0 + (k + 0.5) * 4.0 / count + rng.uniform(-0.05, 0.05)
        h = rng.uniform(3.6, 4.4)
        lean = Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.1, 0.1), 0))
        log(m, mats["wood"], WOOD_DARK if k % 2 else WOOD_LIGHT, Vector((x, 0, -0.4)), Vector((x, 0, h)) + lean,
            rng.uniform(0.26, 0.31), 7, tip=0.55)
    for z in (1.1, 2.6):
        log(m, mats["wood"], WOOD_LIGHT, Vector((-2.05, -0.36, z)), Vector((2.05, -0.36, z + rng.uniform(-0.1, 0.1))), 0.1)
    return m.to_object(f"Palisade{variant}"), {}


def gate_tower(mats):
    m = Mesh()
    for x in (-1.1, 1.1):
        for y in (-1.1, 1.1):
            log(m, mats["wood"], WOOD_DARK, Vector((x, y, -0.4)), Vector((x, y, 5.6)), 0.2, 7, tip=0.4)
    box(m, mats["wood"], WOOD_LIGHT, Vector((0, 0, 4.0)), (2.8, 2.8, 0.2))
    for y in (-1.25, 1.25):
        log(m, mats["wood"], WOOD_LIGHT, Vector((-1.3, y, 4.7)), Vector((1.3, y, 4.7)), 0.08)
    for x in (-1.25, 1.25):
        log(m, mats["wood"], WOOD_LIGHT, Vector((x, -1.3, 4.7)), Vector((x, 1.3, 4.7)), 0.08)
    return m.to_object("GateTower"), {}


def tent(mats, variant, rng):
    """An A-frame tent, ridge along Y, opening at the front (-Y)."""
    m = Mesh()
    w, d, h = (3.2, 3.6, 2.4) if variant == 1 else (4.2, 4.6, 2.9)
    cloth = mats["canvas"] if variant == 1 else mats["canvasDark"]
    hw, hd = w / 2, d / 2
    sag = rng.uniform(0.05, 0.15)
    left = [Vector((-hw, -hd, 0)), Vector((-hw, hd, 0)), Vector((0, hd, h)), Vector((0, -hd, h - sag))]
    right = [Vector((hw, hd, 0)), Vector((hw, -hd, 0)), Vector((0, -hd, h - sag)), Vector((0, hd, h))]
    for quad in (left, right):
        sheet(m, quad, [(0, 0), (1, 0), (1, 1), (0, 1)], cloth)
    sheet(m, [Vector((hw, hd, 0)), Vector((-hw, hd, 0)), Vector((0, hd, h))], [(0, 0), (1, 0), (0.5, 1)], cloth)
    for y in (-hd - 0.1, hd + 0.1):
        log(m, mats["wood"], WOOD_LIGHT, Vector((0, y, -0.2)), Vector((0, y, h + 0.35)), 0.07)
    log(m, mats["wood"], WOOD_LIGHT, Vector((0, -hd - 0.2, h + 0.05)), Vector((0, hd + 0.2, h + 0.05)), 0.05)
    return m.to_object(f"Tent{variant}"), {}


def dais(mats):
    m = Mesh()
    box(m, mats["rock"], ROCK_BRICK, Vector((0, 0, 0.2)), (7.6, 5.2, 0.8))
    box(m, mats["rock"], ROCK_SLAB, Vector((0, 0.4, 0.75)), (5.6, 3.6, 0.5))
    return m.to_object("Dais"), {}


# ---------------------------------------------------------------- joining and compatibility

def join(objs, name, offset):
    """Joins objects into one mesh named `name`, moved by `offset`; one UV set, merged materials."""
    bpy.context.view_layer.update()
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    materials = []
    for obj in objs:
        tmp = bmesh.new()
        tmp.from_mesh(obj.data)
        tmp.transform(Matrix.Translation(offset) @ obj.matrix_world)
        src_uv = tmp.loops.layers.uv[0] if tmp.loops.layers.uv else None
        remap = []
        for mat in obj.data.materials:
            mat = merged(mat)
            if mat not in materials:
                materials.append(mat)
            remap.append(materials.index(mat))
        verts = {}
        for v in tmp.verts:
            verts[v.index] = bm.verts.new(v.co)
        tmp.verts.index_update()
        for f in tmp.faces:
            try:
                nf = bm.faces.new([verts[v.index] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = remap[f.material_index] if remap else 0
            if src_uv:
                for nl, ol in zip(nf.loops, f.loops):
                    nl[uv].uv = ol[src_uv].uv
        tmp.free()
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    for mat in materials:
        mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def triangles(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def decimate_library(lib):
    """Decimates heavy library pieces in place; every placed copy shares the lighter mesh."""
    # A hidden collection is left out of the depsgraph, so its modifiers would never evaluate.
    lib.collection.hide_viewport = False
    bpy.context.view_layer.update()
    for piece in list(lib.collection.objects):
        tris = triangles(piece.data)
        ratio = next((r for prefix, r in DECIMATE if piece.name.startswith(prefix)), 1.0)
        if ratio >= 1.0 or tris < DECIMATE_MIN_TRIS:
            continue
        mod = piece.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        evaluated = piece.evaluated_get(bpy.context.evaluated_depsgraph_get())
        light = bpy.data.meshes.new_from_object(evaluated)
        piece.modifiers.remove(mod)
        old = piece.data
        old.user_remap(light)
        light.name = old.name
        print(f"decimated {piece.name}: {tris} -> {triangles(light)}")
    lib.collection.hide_viewport = True


def merged(mat):
    """MI_WoodTrim_Wear needs the kit's wear shader and second UV set; Roblox gets MI_WoodTrim."""
    if mat and mat.name.startswith("MI_WoodTrim_Wear"):
        return bpy.data.materials.get("MI_WoodTrim") or mat
    return mat


def fix_images():
    """OpenGL normals and at most 1024 px, packed so the exporter writes the changed pixels."""
    for img in bpy.data.images:
        if not img.filepath:
            continue
        base = os.path.basename(img.filepath)
        if base.endswith("_Normal.png") and os.path.exists(os.path.join(NORMALS, base)):
            img.filepath = os.path.join(NORMALS, base)
            img.reload()
        if img.size[0] > MAX_TEXTURE or img.size[1] > MAX_TEXTURE:
            img.scale(min(img.size[0], MAX_TEXTURE), min(img.size[1], MAX_TEXTURE))
        img.pack()


def split_by_material(obj):
    """Replaces `obj` with one object per material, named `<obj>__<material>`."""
    parts = []
    mesh = obj.data
    for index, mat in enumerate(mesh.materials):
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != index], context="FACES")
        if not bm.faces:
            bm.free()
            continue
        for f in bm.faces:
            f.material_index = 0
        part_mesh = bpy.data.meshes.new(f"{obj.name}__{mat.name}")
        bm.to_mesh(part_mesh)
        bm.free()
        part_mesh.materials.append(mat)
        part = bpy.data.objects.new(part_mesh.name, part_mesh)
        bpy.context.scene.collection.objects.link(part)
        parts.append(part)
    bpy.data.objects.remove(obj)
    return parts


def material_info(mat):
    """Colour (0..255) and whether the material has an image, for the manifest."""
    textured = False
    rgb = [200, 200, 200]
    for node in mat.node_tree.nodes if mat.node_tree else []:
        # The free kit references some images it does not ship (MetalOrnaments); those import blank.
        if node.type == "TEX_IMAGE" and node.image and node.image.has_data:
            textured = True
        if node.type == "BSDF_PRINCIPLED":
            rgb = [round(c * 255) for c in node.inputs["Base Color"].default_value[:3]]
    info = {"color": rgb, "textured": textured}
    info.update(ROBLOX_MATERIALS.get(mat.name, {}))
    return info


def bounds(obj):
    """Bounds in metres, Roblox axes: X = -x, Y = z, Z = y."""
    pts = [Vector((-v.co.x, v.co.z, v.co.y)) for v in obj.data.vertices]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    return [round(v, 3) for v in lo], [round(v, 3) for v in hi]


# ---------------------------------------------------------------- build

def build():
    for obj in list(bpy.context.scene.objects):
        bpy.data.objects.remove(obj)
    lib = hg.Library()
    # Load the materials the custom structures use.
    for piece in ("Wall_Plaster_Straight", "Prop_ExteriorBorder_Straight1"):
        lib[piece]
    mats = {
        "wood": bpy.data.materials["MI_WoodTrim"],
        "rock": bpy.data.materials["MI_RockTrim"],
        "cloth": flat_material("MI_Cloth", (110, 84, 62)),
        "sack": flat_material("MI_Sack", (176, 150, 104)),
        "straw": flat_material("MI_Straw", (196, 166, 92)),
        "canvas": flat_material("MI_Canvas", (164, 146, 116)),
        "canvasDark": flat_material("MI_CanvasDark", (118, 96, 74)),
    }
    assets = []  # (object, entry)

    def add(obj, kind, anchors=None, footprint=None, extra=None):
        lo, hi = bounds(obj)
        entry = {"kind": kind, "min": lo, "max": hi, "anchors": anchors or {}}
        if footprint:
            entry["footprint"] = footprint
        entry.update(extra or {})
        assets.append((obj, entry))

    houses = [(f"House{k + 1:02d}", seed, None, None, None) for k, seed in enumerate(HOUSE_SEEDS)]
    barns = [(f"Barn{k + 1:02d}", seed, w, d, 1) for k, (seed, w, d) in enumerate(BARNS)]
    generated = []
    for name, seed, width, depth, stories in houses + barns:
        col, plan = hg.generate_house(seed, width, depth, stories, (0.0, 0.0, 0.0))
        generated.append((name, col, plan))
    decimate_library(lib)
    for name, col, plan in generated:
        w, d = plan["width"], plan["depth"]
        pieces = [o for o in col.objects if not hg._base_name(o.data.name).startswith(SKIP_PIECES)]
        obj = join(pieces, name, Vector((-w / 2, -d / 2, 0)))
        for o in list(col.objects):
            bpy.data.objects.remove(o)
        bpy.data.collections.remove(col)
        add(obj, "building", footprint=[w, d], extra={
            "stories": plan["stories"],
            # Door centre along Roblox X from the footprint centre; the door is in the front (-Z) wall.
            "door": -(hg.CELL * plan["door_cell"] + 1 - w / 2),
        })

    for name, piece in KIT_PROPS.items():
        obj = join([lib[piece]], name, Vector((0, 0, 0)))
        add(obj, "prop")

    rng = random.Random(SEED)
    obj, anchors = well(mats)
    add(obj, "structure", anchors)
    obj, anchors = brazier(mats)
    add(obj, "structure", anchors)
    for v in (1, 2):
        obj, anchors = scarecrow(mats, v, rng)
        add(obj, "structure", anchors)
    for v in (1, 2, 3):
        obj, anchors = palisade(mats, v, rng)
        add(obj, "wall", anchors, extra={"length": 4.0})
    obj, anchors = gate_tower(mats)
    add(obj, "structure", anchors)
    for v in (1, 2):
        obj, anchors = tent(mats, v, rng)
        add(obj, "structure", anchors)
    obj, anchors = dais(mats)
    add(obj, "structure", anchors)

    # Library pieces stay out of the export.
    lib_col = bpy.data.collections.get(hg.LIBRARY)
    if lib_col:
        for o in list(lib_col.objects):
            bpy.data.objects.remove(o)
    return assets


def export(assets):
    os.makedirs(OUT_DIR, exist_ok=True)
    fix_images()
    materials = {}
    for obj, _ in assets:
        for mat in obj.data.materials:
            materials[mat.name] = material_info(mat)
    tris = {obj.name: sum(len(p.vertices) - 2 for p in obj.data.polygons) for obj, _ in assets}
    entries = {obj.name: entry for obj, entry in assets}
    digest = hashlib.sha256()
    for obj, _ in sorted(assets, key=lambda a: a[0].name):
        digest.update(obj.name.encode())
        for v in obj.data.vertices:
            digest.update(("%.4f %.4f %.4f;" % tuple(v.co)).encode())
        for mat in obj.data.materials:
            digest.update(mat.name.encode())
    split = [part for obj, _ in assets for part in split_by_material(obj)]
    bpy.ops.object.select_all(action="DESELECT")
    for part in split:
        part.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "village_kit.glb"), use_selection=True,
                              export_format="GLB", export_texcoords=True, export_normals=True)
    manifest = {"source": "tools/blender/village_kit.py", "unit": "metre", "front": "-Z",
                "materials": materials, "assets": entries}
    with open(os.path.join(OUT_DIR, "village_kit.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent="\t", sort_keys=True)
        f.write("\n")
    digest.update(json.dumps(manifest, sort_keys=True).encode())
    with open(os.path.join(OUT_DIR, "village_kit.sha"), "w", encoding="utf-8") as f:
        f.write(digest.hexdigest())
    worst = max(tris, key=tris.get)
    print(f"village_kit: {len(assets)} assets, {len(split)} parts, max {tris[worst]} triangles ({worst})")


def render(assets):
    scene = bpy.context.scene
    hg.setup_render(scene)
    for k, (obj, _) in enumerate(assets):
        obj.location = ((k % 8) * 14.0, (k // 8) * 18.0, 0)
    cols_like = [type("C", (), {"objects": [o for o, _ in assets]})()]
    hg.render_view(scene, cols_like, os.path.join(OUT_DIR, "village_kit.png"), (-0.35, -1.0, 0.6))
    for obj, _ in assets:
        obj.location = (0, 0, 0)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    assets = build()
    if "--render" in args:
        render(assets)
    export(assets)
