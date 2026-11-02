"""Seeded low-poly prop library for the zone-graph world (docs/systems/world-generation.md).

Run headless with Blender 5.2 from the repo root:

    "%BLENDER%" -b --factory-startup -P tools/blender/world_props.py -- [--preview]

Writes build/world_props.fbx: one mesh object per prop part, named `<Variant>_<Part>`
(`Broadleaf03_Trunk`, `Broadleaf03_Canopy`, `Boulder02_Rock`). Variants sit side by side along X
with their root at z = 0. `--preview` also renders build/world_props.png for review.

Shapes are faceted on purpose: canopies are clusters of convex hulls of a few random points on a
squashed ellipsoid, pines are stacked low-sided cones, rocks are single hulls. Every variant is
generated from its own seed, so the same script always gives the same meshes.
"""

import hashlib
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

SEED = 20261028
SPACING = 120.0
OUT_DIR = os.path.join(os.getcwd(), "build")

# Variant counts are recorded per species in content/world/props.json on upload.
LIBRARY = [
    ("Broadleaf", 8),
    ("Pine", 8),
    ("Snag", 6),
    ("Bush", 6),
    ("Boulder", 6),
    ("Wheat", 4),
    ("Sprout", 3),
    ("Fruit", 6),
    ("Hay", 2),
]


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_object(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def hull_blob(bm, rng, centre, radii, points=14):
    """Adds a faceted blob: the convex hull of points on a squashed ellipsoid."""
    verts = []
    for _ in range(points):
        theta = rng.uniform(0, math.tau)
        phi = math.acos(rng.uniform(-1, 1))
        r = rng.uniform(0.75, 1.0)
        v = Vector((
            math.sin(phi) * math.cos(theta) * radii[0] * r,
            math.sin(phi) * math.sin(theta) * radii[1] * r,
            math.cos(phi) * radii[2] * r,
        ))
        verts.append(bm.verts.new(centre + v))
    bmesh.ops.convex_hull(bm, input=verts)
    # Points the hull left inside become loose verts; drop them.
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")


def tube(bm, rng, path, radii, sides):
    """Adds a tapered tube along `path` (list of Vectors), `radii` per point, capped at the base."""
    rings = []
    for k, p in enumerate(path):
        if k == 0:
            direction = path[1] - path[0]
        elif k == len(path) - 1:
            direction = path[-1] - path[-2]
        else:
            direction = path[k + 1] - path[k - 1]
        direction.normalize()
        side = direction.orthogonal().normalized()
        other = direction.cross(side).normalized()
        twist = rng.uniform(0, math.tau / sides)
        ring = []
        for s in range(sides):
            a = twist + s * math.tau / sides
            ring.append(bm.verts.new(p + (side * math.cos(a) + other * math.sin(a)) * radii[k]))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for s in range(sides):
            bm.faces.new((a[s], a[(s + 1) % sides], b[(s + 1) % sides], b[s]))
    bm.faces.new(list(reversed(rings[0])))
    tip = bm.verts.new(path[-1] + (path[-1] - path[-2]).normalized() * radii[-1])
    last = rings[-1]
    for s in range(sides):
        bm.faces.new((last[s], last[(s + 1) % sides], tip))


def bent_path(rng, start, direction, length, segments, wander):
    path = [start.copy()]
    d = direction.normalized()
    step = length / segments
    for _ in range(segments):
        d = (d + Vector((rng.uniform(-wander, wander), rng.uniform(-wander, wander), 0))).normalized()
        path.append(path[-1] + d * step)
    return path


def broadleaf(name, rng, origin):
    height = rng.uniform(26, 34)
    trunk = bmesh.new()
    path = bent_path(rng, origin, Vector((0, 0, 1)), height, 4, 0.18)
    base = rng.uniform(2.8, 3.6)
    tube(trunk, rng, path, [base * 1.25, base, base * 0.8, base * 0.65, base * 0.5], 6)
    tips = [path[-1]]
    for b in range(rng.randint(2, 3)):
        start = path[rng.randint(2, 3)]
        angle = b * math.tau / 3 + rng.uniform(-0.4, 0.4)
        out = Vector((math.cos(angle), math.sin(angle), rng.uniform(0.7, 1.1)))
        branch = bent_path(rng, start, out, rng.uniform(8, 13), 2, 0.2)
        tube(trunk, rng, branch, [base * 0.55, base * 0.4, base * 0.28], 5)
        tips.append(branch[-1])
    new_object(f"{name}_Trunk", trunk)

    canopy = bmesh.new()
    spread = rng.uniform(16, 22)
    for tip in tips:
        hull_blob(canopy, rng, tip + Vector((0, 0, 3)), (spread, spread * rng.uniform(0.8, 1.1), spread * 0.38))
    for _ in range(rng.randint(2, 3)):
        offset = Vector((rng.uniform(-14, 14), rng.uniform(-14, 14), rng.uniform(1, 8)))
        hull_blob(canopy, rng, path[-1] + offset, (spread * 0.85, spread * 0.85, spread * 0.34))
    new_object(f"{name}_Canopy", canopy)


def pine(name, rng, origin):
    height = rng.uniform(40, 52)
    trunk = bmesh.new()
    path = bent_path(rng, origin, Vector((0, 0, 1)), height * 0.9, 3, 0.05)
    base = rng.uniform(1.6, 2.1)
    tube(trunk, rng, path, [base * 1.2, base, base * 0.7, base * 0.4], 6)
    new_object(f"{name}_Trunk", trunk)

    canopy = bmesh.new()
    tiers = rng.randint(3, 5)
    bottom = height * rng.uniform(0.22, 0.3)
    span = height - bottom
    for t in range(tiers):
        f = t / tiers
        z = bottom + span * f * 0.82
        radius = (1 - f * 0.75) * rng.uniform(10, 13)
        depth = span / tiers * 1.7
        sides = rng.choice((6, 7, 8))
        result = bmesh.ops.create_cone(
            canopy, cap_ends=True, cap_tris=True, segments=sides,
            radius1=radius, radius2=0.0, depth=depth,
            matrix=Matrix.Translation(origin + Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), z + depth / 2)))
            @ Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z"),
        )
        for v in result["verts"]:
            if v.co.z < origin.z + z + depth * 0.1:
                v.co.x += rng.uniform(-1.2, 1.2)
                v.co.y += rng.uniform(-1.2, 1.2)
                v.co.z += rng.uniform(-1.5, 0.5)
    new_object(f"{name}_Canopy", canopy)


def snag(name, rng, origin):
    height = rng.uniform(20, 28)
    trunk = bmesh.new()
    path = bent_path(rng, origin, Vector((0, 0, 1)), height, 4, 0.22)
    base = rng.uniform(1.8, 2.4)
    tube(trunk, rng, path, [base * 1.3, base, base * 0.75, base * 0.5, base * 0.3], 5)
    for _ in range(rng.randint(3, 5)):
        start = path[rng.randint(1, 3)]
        angle = rng.uniform(0, math.tau)
        out = Vector((math.cos(angle), math.sin(angle), rng.uniform(0.3, 0.9)))
        branch = bent_path(rng, start, out, rng.uniform(6, 11), 2, 0.3)
        tube(trunk, rng, branch, [base * 0.45, base * 0.3, base * 0.15], 4)
    new_object(f"{name}_Trunk", trunk)


def bush(name, rng, origin):
    canopy = bmesh.new()
    for _ in range(rng.randint(2, 4)):
        offset = Vector((rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(2.2, 3.5)))
        size = rng.uniform(3.2, 4.6)
        hull_blob(canopy, rng, origin + offset, (size, size * rng.uniform(0.8, 1.1), size * 0.75), 12)
    new_object(f"{name}_Canopy", canopy)


def boulder(name, rng, origin):
    rock = bmesh.new()
    size = rng.uniform(4.5, 6)
    hull_blob(rock, rng, origin + Vector((0, 0, size * 0.45)),
              (size * rng.uniform(1.0, 1.4), size, size * rng.uniform(0.6, 0.85)), 16)
    new_object(f"{name}_Rock", rock)


def wheat(name, rng, origin):
    """A patch of stalks about 4 x 4 units with grain heads; placed in rows on field plots."""
    canopy = bmesh.new()
    for _ in range(rng.randint(14, 18)):
        base = origin + Vector((rng.uniform(-2, 2), rng.uniform(-2, 2), 0))
        lean = Vector((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 1))
        stalk = bent_path(rng, base, lean, rng.uniform(3.4, 4.4), 2, 0.12)
        tube(canopy, rng, stalk, [0.09, 0.07, 0.05], 3)
        hull_blob(canopy, rng, stalk[-1] + Vector((0, 0, 0.35)), (0.16, 0.16, 0.5), 7)
    new_object(f"{name}_Canopy", canopy)


def sprout(name, rng, origin):
    """A low leafy crop: blades fanning out of a centre."""
    canopy = bmesh.new()
    blades = rng.randint(6, 8)
    for k in range(blades):
        angle = k * math.tau / blades + rng.uniform(-0.2, 0.2)
        length = rng.uniform(1.0, 1.5)
        out = Vector((math.cos(angle), math.sin(angle), 0))
        side = Vector((-out.y, out.x, 0)) * rng.uniform(0.22, 0.32)
        tip = origin + out * length + Vector((0, 0, rng.uniform(0.7, 1.1)))
        mid = origin + out * length * 0.5 + Vector((0, 0, 0.6))
        root = origin + Vector((0, 0, 0.05))
        verts = [canopy.verts.new(v) for v in (root, mid - side, tip, mid + side)]
        canopy.faces.new(verts)
        canopy.faces.new(list(reversed([canopy.verts.new(v.co) for v in verts])))
    new_object(f"{name}_Canopy", canopy)


def fruit(name, rng, origin):
    """A small orchard tree: short trunk, round canopy, fruit on the canopy surface."""
    trunk = bmesh.new()
    height = rng.uniform(9, 12)
    path = bent_path(rng, origin, Vector((0, 0, 1)), height, 3, 0.15)
    base = rng.uniform(1.0, 1.3)
    tube(trunk, rng, path, [base * 1.2, base, base * 0.75, base * 0.55], 6)
    new_object(f"{name}_Trunk", trunk)
    canopy = bmesh.new()
    spread = rng.uniform(6.5, 8.5)
    centre = path[-1] + Vector((0, 0, 2.5))
    hull_blob(canopy, rng, centre, (spread, spread * rng.uniform(0.85, 1.1), spread * 0.72), 16)
    for _ in range(2):
        offset = Vector((rng.uniform(-3, 3), rng.uniform(-3, 3), rng.uniform(-1, 2)))
        hull_blob(canopy, rng, centre + offset, (spread * 0.7, spread * 0.7, spread * 0.55), 12)
    new_object(f"{name}_Canopy", canopy)
    fruits = bmesh.new()
    for _ in range(rng.randint(8, 12)):
        theta = rng.uniform(0, math.tau)
        z = rng.uniform(-0.6, 0.3)
        r = math.sqrt(1 - z * z)
        p = centre + Vector((math.cos(theta) * r * spread * 0.95, math.sin(theta) * r * spread * 0.95, z * spread * 0.7))
        hull_blob(fruits, rng, p, (0.6, 0.6, 0.6), 8)
    new_object(f"{name}_Fruit", fruits)


def hay(name, rng, origin):
    """A round hay bale lying on its side."""
    bale = bmesh.new()
    radius = rng.uniform(1.6, 1.9)
    length = rng.uniform(2.2, 2.6)
    path = [origin + Vector((-length / 2, 0, radius)), origin + Vector((length / 2, 0, radius))]
    tube(bale, rng, path, [radius, radius], 9)
    new_object(f"{name}_Bale", bale)


BUILDERS = {
    "Broadleaf": broadleaf,
    "Pine": pine,
    "Snag": snag,
    "Bush": bush,
    "Boulder": boulder,
    "Wheat": wheat,
    "Sprout": sprout,
    "Fruit": fruit,
    "Hay": hay,
}


def build():
    reset_scene()
    index = 0
    for prefix, count in LIBRARY:
        for v in range(1, count + 1):
            name = f"{prefix}{v:02d}"
            rng = random.Random(f"{SEED}:{name}")
            BUILDERS[prefix](name, rng, Vector((index * SPACING, 0, 0)))
            index += 1


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export():
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "world_props.fbx")
    bpy.ops.export_scene.fbx(
        filepath=path,
        object_types={"MESH"},
        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        bake_space_transform=True,
    )
    # FBX files carry export timestamps, so the upload tool compares this geometry hash instead.
    digest = hashlib.sha256()
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        digest.update(obj.name.encode())
        for v in obj.data.vertices:
            digest.update(("%.4f %.4f %.4f;" % tuple(v.co)).encode())
        for poly in obj.data.polygons:
            digest.update((" ".join(str(i) for i in poly.vertices) + ";").encode())
    with open(os.path.join(OUT_DIR, "world_props.sha"), "w", encoding="utf-8") as f:
        f.write(digest.hexdigest())
    worst = max(bpy.data.objects, key=triangles)
    print(f"world_props: {len(bpy.data.objects)} objects, max {triangles(worst)} triangles ({worst.name}) -> {path}")


def preview():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("World")
    world.color = (0.55, 0.68, 0.75)
    scene.world = world
    trunk = bpy.data.materials.new("Trunk")
    trunk.diffuse_color = (0.25, 0.2, 0.16, 1)
    leaf = bpy.data.materials.new("Leaf")
    leaf.diffuse_color = (0.22, 0.42, 0.3, 1)
    rock = bpy.data.materials.new("Rock")
    rock.diffuse_color = (0.45, 0.48, 0.5, 1)
    fruit_mat = bpy.data.materials.new("Fruit")
    fruit_mat.diffuse_color = (0.7, 0.18, 0.12, 1)
    straw = bpy.data.materials.new("Straw")
    straw.diffuse_color = (0.75, 0.62, 0.3, 1)
    by_suffix = {"Canopy": leaf, "Rock": rock, "Fruit": fruit_mat, "Bale": straw}
    for obj in list(bpy.data.objects):
        obj.data.materials.append(by_suffix.get(obj.name.rsplit("_", 1)[-1], trunk))
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.data.type = "ORTHO"
    camera.rotation_euler = (math.radians(80), 0, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 300
    # One image per species row.
    index = 0
    for prefix, count in LIBRARY:
        first = index
        index += count
        camera.data.ortho_scale = count * SPACING
        camera.location = ((first + (count - 1) / 2) * SPACING, -500, 25 + 88)
        scene.render.filepath = os.path.join(OUT_DIR, f"world_props_{prefix}.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build()
    export()
    if "--preview" in args:
        preview()
