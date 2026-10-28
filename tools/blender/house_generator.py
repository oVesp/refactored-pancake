"""Procedural medieval house generator built from the Quaternius Medieval Village MegaKit.

Headless:
    blender -b --factory-startup --python tools/blender/house_generator.py -- [options]

    --kit DIR       MegaKit root (default assets/third_party/Medieval Village MegaKit[Standard])
    --seed N        first seed (default 1); house k uses seed N + k
    --count N       houses to generate, laid out on a grid (default 1)
    --width N       footprint width in metres: 4, 6 or 8 (default random)
    --depth N       footprint depth in metres (default random, must suit the roof table)
    --stories N     1 to 3 (default random)
    --out FILE      save the scene as .blend
    --glb FILE      export the houses as .glb
    --render FILE   render a three-quarter overview to .png
    --views         with --render, also render <name>_front.png and <name>_back.png

Interactive: run the file from Blender's Text Editor (or install it as an add-on); the
"House" tab in the 3D view sidebar generates a house from seed and size settings.

Kit conventions (measured from the glTF files): 2 m grid, 3 m stories, walls span local
x -1..1 with the exterior facing -Y and the origin on the grid line, roofs ridge along Y.
A house occupies x 0..width, y 0..depth with its front (door) wall on y = 0.
"""

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

bl_info = {
    "name": "Medieval House Generator",
    "blender": (4, 0, 0),
    "category": "Add Mesh",
    "location": "View3D > Sidebar > House",
    "description": "Procedural houses from the Quaternius Medieval Village MegaKit",
}

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEFAULT_KIT = os.path.join(REPO, "assets", "third_party", "Medieval Village MegaKit[Standard]")
LIBRARY = "MegaKit_Library"
CELL = 2.0
STORY = 3.0

# Roof_RoundTiles_<width>x<depth>; 6x4 is a half piece (not centred) and is left out.
ROOF_DEPTHS = {4: (4, 6, 8), 6: (6, 8, 10, 12, 14), 8: (8, 10, 12, 14)}
# Ridge height above the wall top per roof width (tile surface, from the glTF bounds).
RIDGE = {4: 3.7, 6: 4.9, 8: 6.0}

# Wall piece per style and slot. "base" styles sit on the ground floor.
WALLS = {
    "brick": {
        "plain": "Wall_UnevenBrick_Straight",
        "door_flat": "Wall_UnevenBrick_Door_Flat",
        "door_round": "Wall_UnevenBrick_Door_Round",
        "thin_round": "Wall_UnevenBrick_Window_Thin_Round",
        "wide_flat": "Wall_UnevenBrick_Window_Wide_Flat",
        "wide_round": "Wall_UnevenBrick_Window_Wide_Round",
    },
    "plaster_base": {
        "plain": "Wall_Plaster_Straight_Base",
        "door_flat": "Wall_Plaster_Door_Flat",
        "door_round": "Wall_Plaster_Door_Round",
        "thin_round": "Wall_Plaster_Window_Thin_Round",
        "wide_flat": "Wall_Plaster_Window_Wide_Flat",
        "wide_round": "Wall_Plaster_Window_Wide_Round",
    },
    "plaster": {
        "plain": "Wall_Plaster_Straight",
        "grid": "Wall_Plaster_WoodGrid",
        "thin_round": "Wall_Plaster_Window_Thin_Round",
        "wide_flat": "Wall_Plaster_Window_Wide_Flat2",
        "wide_round": "Wall_Plaster_Window_Wide_Round",
    },
}
CORNERS = {"brick": "Corner_Exterior_Brick", "plaster_base": "Corner_Exterior_Wood", "plaster": "Corner_Exterior_Wood"}
WINDOWS = {
    "thin_round": ("Window_Thin_Round1", "WindowShutters_Thin_Round_Open", "WindowShutters_Thin_Round_Closed"),
    "wide_flat": ("Window_Wide_Flat1", "WindowShutters_Wide_Flat_Open", "WindowShutters_Wide_Flat_Closed"),
    "wide_round": ("Window_Wide_Round1", "WindowShutters_Wide_Round_Open", "WindowShutters_Wide_Round_Closed"),
}
DOORS = {"flat": ("Door_1_Flat", "Door_2_Flat", "Door_4_Flat", "Door_8_Flat"),
         "round": ("Door_1_Round", "Door_2_Round", "Door_4_Round", "Door_8_Round")}
# Door leaves hinge at local x = 0 and are 1.07 m wide; this centres them in the opening.
DOOR_OFFSET = -0.53
FLOORS = ("Floor_WoodDark", "Floor_WoodLight")
CHIMNEYS = ("Prop_Chimney", "Prop_Chimney2")
VINES = ("Prop_Vine1", "Prop_Vine2", "Prop_Vine4")


# ---------------------------------------------------------------- kit library

def _base_name(name):
    head, dot, tail = name.rpartition(".")
    return head if dot and tail.isdigit() else name


def _dedupe(collection):
    """Points users of `Name.001` duplicates at `Name` and removes the copies."""
    for block in list(collection):
        base = _base_name(block.name)
        if base != block.name and base in collection:
            block.user_remap(collection[base])
            collection.remove(block)


class Library:
    """Kit pieces imported on first use into a hidden collection, shared by every house."""

    def __init__(self, kit=DEFAULT_KIT):
        self.gltf_dir = os.path.join(kit, "glTF")
        if not os.path.isdir(self.gltf_dir):
            raise FileNotFoundError(f"MegaKit glTF folder not found: {self.gltf_dir}")
        lib = bpy.data.collections.get(LIBRARY)
        if lib is None:
            lib = bpy.data.collections.new(LIBRARY)
            bpy.context.scene.collection.children.link(lib)
        lib.hide_render = True
        lib.hide_viewport = True
        self.collection = lib

    def __getitem__(self, name):
        piece = self.collection.objects.get(name)
        return piece if piece else self._import(name)

    def _import(self, name):
        path = os.path.join(self.gltf_dir, name + ".gltf")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = set(bpy.data.objects) - before
        meshes = [o for o in new if o.type == "MESH"]
        if len(meshes) != 1:
            raise RuntimeError(f"{path}: expected one mesh, got {len(meshes)}")
        piece = meshes[0]
        bpy.context.view_layer.update()
        world = piece.matrix_world.copy()
        for obj in new:
            for c in obj.users_collection:
                c.objects.unlink(obj)
            if obj is not piece:
                bpy.data.objects.remove(obj)
        # Bake any import transform so copies can be placed with a plain location/rotation.
        piece.parent = None
        piece.data.transform(world)
        piece.matrix_world = Matrix.Identity(4)
        piece.rotation_mode = "XYZ"
        piece.name = piece.data.name = name
        self.collection.objects.link(piece)
        # Each import brings its own MI_*.001 materials and image copies.
        _dedupe(bpy.data.materials)
        _dedupe(bpy.data.images)
        return piece


# ---------------------------------------------------------------- placement

class Builder:
    """Places linked copies of kit pieces into one collection with a house-local transform."""

    def __init__(self, pieces, collection, origin):
        self.pieces = pieces
        self.collection = collection
        self.origin = origin

    def place(self, name, x, y, z=0.0, rot=0.0, local_x=0.0):
        """Places `name` at house point (x, y, z), turned `rot` degrees about Z.
        `local_x` shifts along the piece's own X axis after rotation."""
        src = self.pieces[name]
        obj = src.copy()
        a = math.radians(rot)
        obj.location = self.origin + Vector((x + local_x * math.cos(a), y + local_x * math.sin(a), z))
        obj.rotation_mode = "XYZ"
        obj.rotation_euler = (0.0, 0.0, a)
        self.collection.objects.link(obj)
        return obj


def wall_slots(width, depth):
    """Yields (side, index, x, y, rot) for every 2 m wall cell, exterior facing outward."""
    for i in range(width // 2):
        yield "front", i, CELL * i + 1, 0.0, 0.0
        yield "back", i, width - CELL * i - 1, depth, 180.0
    for j in range(depth // 2):
        yield "left", j, 0.0, depth - CELL * j - 1, -90.0
        yield "right", j, width, CELL * j + 1, 90.0


def random_plan(rng, width=None, depth=None, stories=None):
    width = width or rng.choice(sorted(ROOF_DEPTHS))
    if width not in ROOF_DEPTHS:
        raise ValueError(f"width must be one of {sorted(ROOF_DEPTHS)}")
    depth = depth or rng.choice(ROOF_DEPTHS[width])
    if depth not in ROOF_DEPTHS[width]:
        raise ValueError(f"depth for width {width} must be one of {ROOF_DEPTHS[width]}")
    stories = stories or rng.choice((1, 2, 2, 3))
    ground = rng.choice(("brick", "plaster_base"))
    return {
        "width": width,
        "depth": depth,
        "stories": stories,
        "ground": ground,
        "upper_grid": rng.random() < 0.5,
        "door_shape": rng.choice(("flat", "round")),
        "door": rng.choice(DOORS["flat"]).rsplit("_", 1)[0],
        "door_cell": rng.randrange(width // 2),
        "window": rng.choice(sorted(WINDOWS)),
        "window_chance": rng.uniform(0.45, 0.8),
        "shutters": rng.choice(("open", "closed", "mixed", "none")),
        "floor": rng.choice(FLOORS),
        "chimney": rng.choice((None,) + CHIMNEYS),
        "vines": rng.randrange(0, 3),
    }


def generate_house(seed=1, width=None, depth=None, stories=None, origin=(0.0, 0.0, 0.0), kit=DEFAULT_KIT):
    """Builds one house into a new collection `House_<seed>`; returns (collection, plan)."""
    pieces = Library(kit)
    rng = random.Random(seed)
    plan = random_plan(rng, width, depth, stories)
    width, depth, stories = plan["width"], plan["depth"], plan["stories"]

    name = f"House_{seed}"
    old = bpy.data.collections.get(name)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj)
        bpy.data.collections.remove(old)
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    b = Builder(pieces, col, Vector(origin))

    for story in range(stories):
        z = story * STORY
        style = plan["ground"] if story == 0 else "plaster"
        walls = WALLS[style]
        prev = (None, -2, None)  # side, index and shutter mode of the last window placed
        for side, index, x, y, rot in wall_slots(width, depth):
            is_door = story == 0 and side == "front" and index == plan["door_cell"]
            if is_door:
                b.place(walls["door_" + plan["door_shape"]], x, y, z, rot)
                b.place(f"{plan['door']}_{plan['door_shape'].capitalize()}", x, y, z, rot, DOOR_OFFSET)
                continue
            if rng.random() < plan["window_chance"]:
                kind = plan["window"]
                b.place(walls[kind], x, y, z, rot)
                glass, open_, closed = WINDOWS[kind]
                b.place(glass, x, y, z, rot)
                mode = plan["shutters"]
                if mode == "mixed":
                    mode = rng.choice(("open", "closed", "none"))
                # Open shutters are wider than a cell and would clip the neighbour's.
                if mode == "open" and prev[:2] == (side, index - 1) and prev[2] == "open":
                    mode = "closed"
                if mode != "none":
                    b.place(open_ if mode == "open" else closed, x, y, z, rot)
                prev = (side, index, mode)
            else:
                plain = walls["grid"] if style == "plaster" and plan["upper_grid"] else walls["plain"]
                b.place(plain, x, y, z, rot)
        corner = CORNERS[style]
        for x, y, rot in ((0, 0, 0), (width, 0, 90), (width, depth, 180), (0, depth, -90)):
            b.place(corner, x, y, z, rot)
        for i in range(width // 2):
            for j in range(depth // 2):
                b.place(plan["floor"], CELL * i + 1, CELL * j + 1, z + (0.0 if story else 0.01))

    top = stories * STORY
    b.place(f"Roof_RoundTiles_{width}x{depth}", width / 2, depth / 2, top)
    b.place(f"Roof_Front_Brick{width}", width / 2, 0.0, top, 0.0)
    b.place(f"Roof_Front_Brick{width}", width / 2, depth, top, 180.0)

    if plan["chimney"]:
        # Stand the stack on the slope a quarter of the width in from the eave; its top clears
        # the ridge line there by about a metre.
        x = width * rng.choice((0.25, 0.75))
        slope_z = RIDGE[width] * (1 - abs(x - width / 2) / (width / 2))
        b.place(plan["chimney"], x, CELL * rng.randrange(1, depth // 2), top + slope_z - 1.8)

    sides = [s for s in wall_slots(width, depth)]
    for _ in range(plan["vines"]):
        side, index, x, y, rot = rng.choice(sides)
        b.place(rng.choice(VINES), x, y, rng.randrange(1, stories + 1) * STORY - 0.2, rot)

    col["plan"] = str(plan)
    return col, plan


# ---------------------------------------------------------------- scene / output

def clear_houses():
    for col in list(bpy.data.collections):
        if col.name.startswith("House_"):
            for obj in list(col.objects):
                bpy.data.objects.remove(obj)
            bpy.data.collections.remove(col)


def _bounds(cols):
    bpy.context.view_layer.update()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for col in cols:
        for obj in col.objects:
            for corner in obj.bound_box:
                p = obj.matrix_world @ Vector(corner)
                lo = Vector(map(min, lo, p))
                hi = Vector(map(max, hi, p))
    return lo, hi


def setup_render(scene):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.7, 0.9, 1.0)
    bg.inputs[1].default_value = 0.8
    sun = bpy.data.objects.get("HouseGen_Sun")
    if sun is None:
        sun = bpy.data.objects.new("HouseGen_Sun", bpy.data.lights.new("HouseGen_Sun", "SUN"))
        scene.collection.objects.link(sun)
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(-35))
    ground = bpy.data.objects.get("HouseGen_Ground")
    if ground is None:
        mesh = bpy.data.meshes.new("HouseGen_Ground")
        mesh.from_pydata([(-1, -1, 0), (1, -1, 0), (1, 1, 0), (-1, 1, 0)], [], [(0, 1, 2, 3)])
        ground = bpy.data.objects.new("HouseGen_Ground", mesh)
        mat = bpy.data.materials.new("HouseGen_Ground")
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (0.25, 0.35, 0.18, 1.0)
        mesh.materials.append(mat)
        scene.collection.objects.link(ground)
    ground.scale = (500, 500, 1)
    ground.location.z = -0.02


def render_view(scene, cols, path, direction):
    """Renders `cols` from `direction` (house-relative unit-ish vector) framing their bounds."""
    lo, hi = _bounds(cols)
    cam = bpy.data.objects.get("HouseGen_Camera")
    if cam is None:
        cam = bpy.data.objects.new("HouseGen_Camera", bpy.data.cameras.new("HouseGen_Camera"))
        scene.collection.objects.link(cam)
    cam.data.lens = 35
    cam.rotation_euler = (-Vector(direction)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    bpy.context.view_layer.update()
    corners = [c for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z) for c in (x, y, z)]
    location, _ = cam.camera_fit_coords(bpy.context.evaluated_depsgraph_get(), corners)
    # Back off a little so the silhouette does not touch the frame edge.
    cam.location = location + Vector(direction).normalized() * 0.08 * (hi - lo).length
    scene.render.filepath = os.path.abspath(path)
    bpy.ops.render.render(write_still=True)


def export_glb(cols, path):
    bpy.ops.object.select_all(action="DESELECT")
    for col in cols:
        for obj in col.objects:
            obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(path), use_selection=True, export_format="GLB")


# ---------------------------------------------------------------- Blender UI

class HOUSEGEN_OT_generate(bpy.types.Operator):
    """Generate a medieval house from the MegaKit"""

    bl_idname = "housegen.generate"
    bl_label = "Generate House"
    bl_options = {"REGISTER", "UNDO"}

    seed: bpy.props.IntProperty(name="Seed", default=1, min=0)
    width: bpy.props.EnumProperty(name="Width", items=[("0", "Random", ""), ("4", "4 m", ""), ("6", "6 m", ""), ("8", "8 m", "")])
    depth: bpy.props.IntProperty(name="Depth", description="0 = random", default=0, min=0, max=14, step=2)
    stories: bpy.props.IntProperty(name="Stories", description="0 = random", default=0, min=0, max=3)
    kit: bpy.props.StringProperty(name="Kit", subtype="DIR_PATH", default=DEFAULT_KIT)

    def execute(self, context):
        try:
            col, plan = generate_house(self.seed, int(self.width) or None, self.depth or None,
                                       self.stories or None, tuple(context.scene.cursor.location), bpy.path.abspath(self.kit))
        except (ValueError, FileNotFoundError, RuntimeError) as err:
            self.report({"ERROR"}, str(err))
            return {"CANCELLED"}
        self.report({"INFO"}, f"{col.name}: {plan['width']}x{plan['depth']} m, {plan['stories']} stories")
        return {"FINISHED"}


class HOUSEGEN_PT_panel(bpy.types.Panel):
    bl_label = "Medieval House"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "House"

    def draw(self, context):
        settings = context.window_manager.operator_properties_last(HOUSEGEN_OT_generate.bl_idname)
        layout = self.layout
        if settings:
            for prop in ("seed", "width", "depth", "stories", "kit"):
                layout.prop(settings, prop)
        op = layout.operator(HOUSEGEN_OT_generate.bl_idname)
        if settings:
            for prop in ("seed", "width", "depth", "stories", "kit"):
                setattr(op, prop, getattr(settings, prop))


CLASSES = (HOUSEGEN_OT_generate, HOUSEGEN_PT_panel)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


# ---------------------------------------------------------------- CLI

def _arg(args, flag, cast=str, default=None):
    if flag in args:
        return cast(args[args.index(flag) + 1])
    return default


def main(args):
    kit = _arg(args, "--kit", default=DEFAULT_KIT)
    seed = _arg(args, "--seed", int, 1)
    count = _arg(args, "--count", int, 1)
    width, depth, stories = _arg(args, "--width", int), _arg(args, "--depth", int), _arg(args, "--stories", int)
    scene = bpy.context.scene
    # Start from an empty scene (drops the factory cube, camera and light).
    for obj in [o for o in scene.objects if LIBRARY not in {c.name for c in o.users_collection}]:
        bpy.data.objects.remove(obj)
    clear_houses()
    cols = []
    columns = math.ceil(math.sqrt(count))
    for k in range(count):
        origin = ((k % columns) * 16.0, (k // columns) * 22.0, 0.0)
        col, plan = generate_house(seed + k, width, depth, stories, origin, kit)
        cols.append(col)
        print(f"{col.name}: {plan}")
    if _arg(args, "--render"):
        setup_render(scene)
        path = _arg(args, "--render")
        render_view(scene, cols, path, (-0.8, -1.0, 0.55) if count == 1 else (-0.35, -1.0, 0.6))
        if "--views" in args:
            stem, ext = os.path.splitext(path)
            render_view(scene, cols, f"{stem}_front{ext}", (0.0, -1.0, 0.25))
            render_view(scene, cols, f"{stem}_back{ext}", (0.8, 1.0, 0.55))
    if _arg(args, "--glb"):
        export_glb(cols, _arg(args, "--glb"))
    if _arg(args, "--out"):
        bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(_arg(args, "--out")))


if __name__ == "__main__":
    if bpy.app.background and "--" in sys.argv:
        main(sys.argv[sys.argv.index("--") + 1:])
    else:
        register()
