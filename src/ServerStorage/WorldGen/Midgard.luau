--!strict

--[=[
	Midgard zone graph (docs/systems/world-generation.md). Authored data: the generator in `Gen/`
	turns it into terrain, cliffs and props, one zone at a time.

	Nodes are zones (playable areas) and pockets (hidden areas). Each owns the ground nearer to
	its site than to any other site, measured as distance / `r`, so a larger `r` claims more ground
	and borders curve. Ground farther than `r` from every site is mountain rim. A node without `x`
	and `z` is placed by the force layout next to the nodes it connects to.

	Edges say how two nodes meet. `open`: no border feature. `pass`: a gap through the ridge or
	rim between them. `ramp` and `stairs`: a sloped path between tiers, straight across the border
	or `along` the cliff. `cave`: a roofed tunnel. `drop`: one-way, down; no geometry beyond the
	cliff itself. Same-tier neighbours without an `open` or `pass` edge get a ridge between them.
]=]

export type Node = {
	id: string,
	kind: "zone" | "pocket",
	tier: number,
	floor: number?, -- overrides the tier height (ledge pockets sit between tiers)
	x: number?,
	z: number?,
	r: number,
	biome: string,
	band: number, -- danger band (game-design §3.7)
	roof: boolean?, -- pockets inside a plateau: roof slabs at the height of the ground around
	locked: boolean?, -- signed off: builds read the baked data instead of generating
}

export type Edge = {
	a: string,
	b: string,
	kind: "open" | "pass" | "ramp" | "stairs" | "cave" | "drop",
	width: number?,
	along: boolean?, -- ramps and stairs: descend along the lower zone's border instead of straight out
	secret: boolean?,
}

export type Pad = {
	name: string, -- a part in Workspace.Map.Zones
	zone: string,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	material: string,
}

export type Lake = { zone: string, x: number, z: number, r: number, level: number, depth: number }

export type Biome = {
	grass: string, -- terrain material on open ground
	ground: string, -- paths and corridor floors
	rock: string, -- cliff part material
	rockColor: { number },
	capColor: { number }, -- grass caps on cliff tops
	floorNoise: number, -- studs of gentle relief on the zone floor
	terrace: { number }?, -- noise thresholds for the first and second terrace step
	outcrops: number, -- standalone rock pillars per 100,000 square studs
	trees: number, -- trees per 10,000 square studs inside groves
	groves: number, -- share of the zone covered by groves, 0..1
	species: { [string]: number }, -- tree species weights (`props.species`)
	boulders: number, -- boulders per 100,000 square studs
}

local Midgard = {
	seed = 20261028,
	-- Authoring bounds: the generator only builds nodes inside a section, and the rim fills the
	-- rest of the section rectangle.
	sections = {
		centre = { x0 = -1024, z0 = -1360, x1 = 1024, z1 = 688 },
	},
	tiers = { [-1] = -28, [0] = 0, [1] = 56, [2] = 130, [3] = 210 } :: { [number]: number },
	padHeight = 0.2, -- ground level of the Map zones (tools/world/build.luau G)
	floorY = -80, -- terrain is filled down to here
	-- Mountain rim: climbs from each zone in ledges (`rise` studs up, `ledge` studs deep) to a
	-- ceiling of `floor` +- `relief`.
	rim = { floor = 330, relief = 70, scale = 340, rise = { 40, 110 }, ledge = { 22, 64 }, ledgeScale = 160 },
	-- Domain warp of the cell borders: a large scale bends whole borders, a small one roughens them.
	warp = { large = { amp = 90, scale = 560 }, small = { amp = 24, scale = 120 } },
	-- Raised shelves inside zones: noise above a biome's thresholds lifts the floor one or two steps.
	terraces = { scale = 170, step = { 12, 26 } },
	ridge = { height = 96, relief = 30, half = 24 },
	corridor = { width = 22, rampSlope = 0.32, stairsSlope = 0.55, caveHeight = 24, inset = 14 },
	cliff = {
		step = 6, -- studs of rise over one 4-stud cell that count as a cliff face
		spacing = 18, -- minimum distance between column centres
		width = { 26, 50 },
		depth = { 22, 40 },
		block = { 26, 64 }, -- height of one stacked block
		outset = 4, -- how far a face stands out over the low ground
		yaw = 9, -- degrees of jitter
		tilt = 3,
		spires = 0.05, -- share of rim columns that rise into spires
		spireHeight = { 60, 220 },
	},

	-- Terrain material colours are global per material, so the palette lives on the realm.
	materialColors = {
		Grass = { 92, 134, 96 },
		LeafyGrass = { 74, 116, 86 },
		Ground = { 108, 104, 88 },
		Mud = { 86, 80, 66 },
		Sand = { 150, 144, 118 },
		Slate = { 108, 116, 124 },
		Rock = { 100, 106, 112 },
		Pavement = { 128, 128, 122 },
	} :: { [string]: { number } },

	-- Low-poly prop library: each placement is `<prefix><two-digit variant>`, a template in
	-- ServerStorage.WorldProps built by tools/blender/world_props.py.
	props = {
		groveScale = 150,
		-- `height`: template height in studs at scale 1. Colours per part (`Trunk`, `Canopy`, `Rock`).
		species = {
			broad = {
				prefix = "Broadleaf",
				variants = 8,
				scale = { 0.8, 1.35 },
				height = 58,
				colors = { Trunk = { 74, 62, 54 }, Canopy = { 70, 112, 86 } },
			},
			pine = {
				prefix = "Pine",
				variants = 8,
				scale = { 0.8, 1.4 },
				height = 72,
				colors = { Trunk = { 70, 58, 50 }, Canopy = { 56, 92, 76 } },
			},
			dead = {
				prefix = "Snag",
				variants = 6,
				scale = { 0.8, 1.2 },
				height = 40,
				colors = { Trunk = { 98, 90, 82 } },
			},
		},
		bushes = {
			prefix = "Bush",
			variants = 6,
			perTree = 2,
			scale = { 0.8, 1.4 },
			height = 9,
			colors = { Canopy = { 78, 118, 84 } },
		},
		boulders = {
			prefix = "Boulder",
			variants = 6,
			scale = { 0.7, 1.6 },
			height = 9,
			colors = { Rock = { 116, 122, 128 } },
		},
	},

	biomes = {
		meadow = {
			grass = "Grass",
			ground = "Ground",
			rock = "Slate",
			rockColor = { 126, 134, 141 },
			capColor = { 92, 138, 86 },
			floorNoise = 4,
			terrace = { 0.35, 0.7 },
			outcrops = 1.5,
			trees = 1.6,
			groves = 0.25,
			species = { broad = 1 },
			boulders = 2,
		},
		grove = {
			grass = "LeafyGrass",
			ground = "Ground",
			rock = "Slate",
			rockColor = { 118, 128, 134 },
			capColor = { 80, 128, 82 },
			floorNoise = 6,
			terrace = { 0.25, 0.6 },
			outcrops = 3,
			trees = 2.6,
			groves = 0.5,
			species = { broad = 0.75, pine = 0.25 },
			boulders = 2,
		},
		scrub = {
			grass = "Ground",
			ground = "Mud",
			rock = "Slate",
			rockColor = { 108, 111, 113 },
			capColor = { 96, 116, 76 },
			floorNoise = 5,
			terrace = { 0.3, 0.65 },
			outcrops = 2.5,
			trees = 0.8,
			groves = 0.2,
			species = { dead = 0.6, broad = 0.4 },
			boulders = 4,
		},
		highland = {
			grass = "Grass",
			ground = "Ground",
			rock = "Slate",
			rockColor = { 134, 143, 150 },
			capColor = { 104, 144, 104 },
			floorNoise = 10,
			terrace = { 0.15, 0.5 },
			outcrops = 4,
			trees = 2.0,
			groves = 0.35,
			species = { pine = 0.7, broad = 0.3 },
			boulders = 5,
		},
		hollow = {
			grass = "LeafyGrass",
			ground = "Mud",
			rock = "Slate",
			rockColor = { 101, 114, 121 },
			capColor = { 72, 118, 92 },
			floorNoise = 3,
			terrace = { 0.4, 0.8 },
			outcrops = 3,
			trees = 2.2,
			groves = 0.4,
			species = { broad = 0.8, dead = 0.2 },
			boulders = 3,
		},
		cave = {
			grass = "Ground",
			ground = "Ground",
			rock = "Slate",
			rockColor = { 94, 99, 104 },
			capColor = { 80, 120, 84 },
			floorNoise = 2,
			outcrops = 0,
			trees = 0,
			groves = 0,
			species = {},
			boulders = 4,
		},
	} :: { [string]: Biome },

	nodes = {
		{
			id = "village",
			kind = "zone",
			tier = 0,
			x = -60,
			z = 20,
			r = 300,
			biome = "meadow",
			band = 0,
		},
		{
			id = "fields",
			kind = "zone",
			tier = 0,
			x = 0,
			z = -205,
			r = 230,
			biome = "meadow",
			band = 0,
		},
		{
			id = "orchard",
			kind = "zone",
			tier = 0,
			x = 0,
			z = -440,
			r = 230,
			biome = "grove",
			band = 1,
		},
		{
			id = "goblin-camp",
			kind = "zone",
			tier = 0,
			x = 0,
			z = -670,
			r = 210,
			biome = "scrub",
			band = 1,
		},
		{
			id = "south-hollow",
			kind = "zone",
			tier = -1,
			x = 40,
			z = 400,
			r = 260,
			biome = "hollow",
			band = 0,
		},
		{
			id = "east-terrace",
			kind = "zone",
			tier = 1,
			x = 480,
			z = -280,
			r = 320,
			biome = "grove",
			band = 1,
		},
		{
			id = "west-heights",
			kind = "zone",
			tier = 2,
			x = -560,
			z = -300,
			r = 300,
			biome = "highland",
			band = 2,
		},
		{
			id = "north-rim",
			kind = "zone",
			tier = 3,
			x = -120,
			z = -1080,
			r = 330,
			biome = "highland",
			band = 2,
		},
		{
			id = "cellar-hollow",
			kind = "pocket",
			tier = 0,
			x = -400,
			z = -150,
			r = 50,
			biome = "cave",
			band = 1,
			roof = true,
		},
		{
			id = "fern-ledge",
			kind = "pocket",
			tier = 0,
			floor = 28,
			x = 215,
			z = -140,
			r = 40,
			biome = "grove",
			band = 1,
		},
		{
			id = "camp-den",
			kind = "pocket",
			tier = 0,
			x = 90,
			z = -930,
			r = 55,
			biome = "cave",
			band = 2,
			roof = true,
		},
	} :: { Node },

	edges = {
		{ a = "village", b = "fields", kind = "open" },
		{ a = "fields", b = "orchard", kind = "open" },
		{ a = "orchard", b = "goblin-camp", kind = "pass", width = 34 },
		{ a = "village", b = "south-hollow", kind = "ramp", width = 30 },
		{ a = "fields", b = "east-terrace", kind = "ramp", along = true },
		{ a = "orchard", b = "west-heights", kind = "stairs", along = true },
		{ a = "west-heights", b = "village", kind = "drop" },
		{ a = "west-heights", b = "north-rim", kind = "ramp" },
		{ a = "north-rim", b = "goblin-camp", kind = "drop" },
		{ a = "village", b = "cellar-hollow", kind = "cave", width = 14, secret = true },
		{ a = "goblin-camp", b = "camp-den", kind = "cave", width = 16, secret = true },
		{ a = "east-terrace", b = "fern-ledge", kind = "drop", secret = true },
		{ a = "fern-ledge", b = "fields", kind = "drop" },
	} :: { Edge },

	pads = {
		{ name = "VillageCore", zone = "village", x0 = -90, z0 = -90, x1 = 90, z1 = 90, material = "Grass" },
		{ name = "DevYard", zone = "village", x0 = -240, z0 = -90, x1 = -90, z1 = 90, material = "Pavement" },
		{ name = "WheatFields", zone = "fields", x0 = -110, z0 = -320, x1 = 110, z1 = -90, material = "Grass" },
		{
			name = "OrchardEdge",
			zone = "orchard",
			x0 = -110,
			z0 = -560,
			x1 = 110,
			z1 = -320,
			material = "LeafyGrass",
		},
		{ name = "GoblinCamp", zone = "goblin-camp", x0 = -100, z0 = -760, x1 = 100, z1 = -560, material = "Mud" },
	} :: { Pad },

	lakes = {
		{ zone = "south-hollow", x = 90, z = 470, r = 80, level = -31, depth = 12 },
	} :: { Lake },
}

return Midgard
