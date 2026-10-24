--!strict

-- World generation settings for the first Midgard tile (docs/systems/world-generation.md).
-- Distances and heights are studs. Change a value, rerun `lune run tools/terrain/build`, commit.

export type AssetDef = {
	name: string,
	radius: number, -- footprint radius used for spacing
	scale: { number }, -- min, max uniform scale
	align: number, -- 0 = upright, 1 = fully aligned to the ground normal
	sink: number, -- fraction of the model height pushed into the ground
	maxSlope: number,
}

export type GroupDef = {
	layer: string,
	collide: "trunk" | "all" | "none",
	shadow: boolean,
	assets: { AssetDef },
}

export type BiomeDef = {
	id: number,
	name: string,
	trees: number, -- canopy trees per 1,000 studs²
	treeWeights: { [string]: number }, -- group name -> weight
	understory: { number }, -- children per tree, min..max
	understoryWeights: { [string]: number },
	rocks: number, -- rock clusters per 1,000 studs²
	cover: number, -- ground-cover probability per cover cell
	coverWeights: { [string]: number },
}

local function assets(
	names: { string },
	radius: number,
	scale: { number },
	align: number,
	sink: number,
	maxSlope: number
)
	local list: { AssetDef } = {}
	for _, name in names do
		table.insert(
			list,
			{ name = name, radius = radius, scale = scale, align = align, sink = sink, maxSlope = maxSlope }
		)
	end
	return list
end

local function numbered(prefix: string, from: number, to: number, suffix: string?): { string }
	local list = {}
	for k = from, to do
		table.insert(list, `{prefix}{k}{suffix or ""}`)
	end
	return list
end

local function concat(...: { string }): { string }
	local out = {}
	for _, list in { ... } do
		for _, v in list do
			table.insert(out, v)
		end
	end
	return out
end

-- Footprint radii are about 40% of each model's largest horizontal extent in the pack (at scale 1).
-- Scales follow the reference look the owner shared (2026-10-24): canopy trees about 2x pack size.
local GROUPS: { [string]: GroupDef } = {
	HeroTree = {
		layer = "Trees",
		collide = "trunk",
		shadow = true,
		assets = assets(numbered("F1_Tree", 1, 4), 20, { 1.0, 1.45 }, 0, 0.04, 15),
	},
	CommonTree = {
		layer = "Trees",
		collide = "trunk",
		shadow = true,
		assets = assets(numbered("CommonTree_", 1, 5), 7.5, { 1.4, 2.3 }, 0.05, 0.03, 25),
	},
	Pine = {
		layer = "Trees",
		collide = "trunk",
		shadow = true,
		assets = assets(numbered("Pine_", 1, 5), 8.5, { 1.3, 2.1 }, 0, 0.03, 35),
	},
	TwistedTree = {
		layer = "Trees",
		collide = "trunk",
		shadow = true,
		assets = assets(numbered("TwistedTree_", 1, 5), 10, { 1.4, 2.6 }, 0.15, 0.03, 40),
	},
	DeadTree = {
		layer = "Trees",
		collide = "trunk",
		shadow = true,
		assets = assets(numbered("DeadTree_", 1, 5), 8, { 1.2, 1.8 }, 0.1, 0.03, 35),
	},
	Rock = {
		layer = "Rocks",
		collide = "all",
		shadow = true,
		assets = assets(numbered("Rock_Medium_", 1, 3), 5, { 1.0, 2.6 }, 0.7, 0.18, 45),
	},
	Bush = {
		layer = "Understory",
		collide = "none",
		shadow = false,
		assets = assets(
			{ "F1_BushLow", "F1_BushMid", "F1_BushHigh", "Bush_Common", "Bush_Common_Flowers" },
			4,
			{ 1.1, 1.8 },
			0.5,
			0.08,
			30
		),
	},
	Shade = {
		layer = "Understory",
		collide = "none",
		shadow = false,
		assets = assets(
			{ "Fern_1", "Plant_1", "Plant_1_Big", "Plant_7", "Plant_7_Big", "Mushroom_Common" },
			2,
			{ 1.0, 1.8 },
			0.8,
			0.05,
			25
		),
	},
	Grass = {
		layer = "Cover",
		collide = "none",
		shadow = false,
		assets = assets({
			"F1_LowGrass",
			"F1_MidGrass",
			"F1_HighGrass",
			"Grass_Common_Short",
			"Grass_Common_Tall",
			"Grass_Wispy_Short",
			"Grass_Wispy_Tall",
		}, 1.5, { 1.2, 2.0 }, 1, 0.05, 30),
	},
	Flower = {
		layer = "Cover",
		collide = "none",
		shadow = false,
		assets = assets(
			concat(
				numbered("F1_Flower", 1, 5),
				numbered("F1_Flower", 1, 5, "Patch"),
				{ "Flower_3_Single", "Flower_3_Group", "Flower_4_Single", "Flower_4_Group" },
				numbered("Petal_", 1, 5),
				{ "Clover_1", "Clover_2" }
			),
			1.5,
			{ 1.0, 1.6 },
			1,
			0.05,
			20
		),
	},
	Foliage = {
		layer = "Cover",
		collide = "none",
		shadow = false,
		assets = assets(
			concat(
				{ "F1_Foliage1A", "F1_Foliage1B", "F1_Foliage1Patch", "F1_Foliage2A", "F1_Foliage2B" },
				{ "F1_Foliage2Patch", "F1_Foliage3A", "F1_Foliage3B", "F1_Foliage3Patch", "F1_Foliage4A" },
				{ "F1_Foliage4B", "F1_Foliage4Patch", "F1_Foliage5" },
				numbered("Misc_Folliage.", 1, 27)
			),
			1.5,
			{ 1.2, 2.0 },
			1,
			0.05,
			35
		),
	},
	Pebble = {
		layer = "Pebbles",
		collide = "none",
		shadow = false,
		assets = assets(
			concat(numbered("Pebble_Round_", 1, 5), numbered("Pebble_Square_", 1, 6)),
			0.8,
			{ 0.5, 1.5 },
			1,
			0.3,
			60
		),
	},
	PathTile = {
		layer = "Paths",
		collide = "none",
		shadow = false,
		assets = assets(
			concat(
				numbered("RockPath_Round_Small_", 1, 3),
				numbered("RockPath_Square_Small_", 1, 3),
				{ "RockPath_Round_Thin", "RockPath_Square_Thin", "RockPath_Round_Wide", "RockPath_Square_Wide" }
			),
			2.5,
			{ 0.9, 1.1 },
			1,
			0.35,
			25
		),
	},
}

-- Biome ids 1..7; 0 means no scatter (gameplay pads, water, paths).
local BIOMES: { BiomeDef } = {
	{
		id = 1,
		name = "Meadow",
		trees = 0.12,
		treeWeights = { HeroTree = 0.35, TwistedTree = 0.45, CommonTree = 0.2 },
		understory = { 0, 2 },
		understoryWeights = { Bush = 1 },
		rocks = 0.25,
		cover = 0.12,
		coverWeights = { Grass = 0.55, Flower = 0.45 },
	},
	{
		id = 2,
		name = "Field",
		trees = 0.005,
		treeWeights = { CommonTree = 1 },
		understory = { 1, 3 },
		understoryWeights = { Bush = 1 },
		rocks = 0,
		cover = 0.06,
		coverWeights = { Grass = 1 },
	},
	{
		id = 3,
		name = "MixedForest",
		trees = 3.4,
		treeWeights = { TwistedTree = 0.5, CommonTree = 0.3, HeroTree = 0.06, Pine = 0.1, DeadTree = 0.04 },
		understory = { 1, 3 },
		understoryWeights = { Bush = 0.55, Shade = 0.45 },
		rocks = 0.3,
		cover = 0.09,
		coverWeights = { Foliage = 0.7, Grass = 0.2, Flower = 0.1 },
	},
	{
		id = 4,
		name = "PineForest",
		trees = 3.0,
		treeWeights = { Pine = 0.85, DeadTree = 0.08, TwistedTree = 0.07 },
		understory = { 0, 2 },
		understoryWeights = { Shade = 0.6, Bush = 0.4 },
		rocks = 0.35,
		cover = 0.04,
		coverWeights = { Foliage = 0.8, Grass = 0.2 },
	},
	{
		id = 5,
		name = "WetForest",
		trees = 2.6,
		treeWeights = { TwistedTree = 0.35, CommonTree = 0.3, Pine = 0.25, DeadTree = 0.1 },
		understory = { 2, 4 },
		understoryWeights = { Shade = 0.8, Bush = 0.2 },
		rocks = 0.2,
		cover = 0.09,
		coverWeights = { Foliage = 0.6, Grass = 0.4 },
	},
	{
		id = 6,
		name = "Bog",
		trees = 0.15,
		treeWeights = { DeadTree = 0.7, Pine = 0.3 },
		understory = { 1, 3 },
		understoryWeights = { Shade = 1 },
		rocks = 0.05,
		cover = 0.12,
		coverWeights = { Grass = 0.8, Foliage = 0.2 },
	},
	{
		id = 7,
		name = "Ridge",
		trees = 0.25,
		treeWeights = { TwistedTree = 0.6, Pine = 0.25, DeadTree = 0.15 },
		understory = { 0, 1 },
		understoryWeights = { Bush = 1 },
		rocks = 0.6,
		cover = 0.02,
		coverWeights = { Grass = 1 },
	},
}

-- Terrain material palette. Index is the byte stored per column; names are Enum.Material names.
local MATERIALS = { "Grass", "LeafyGrass", "Ground", "Mud", "Sand", "Rock", "Slate", "Pavement" }

-- Nordic tints applied with Terrain:SetMaterialColor (muted greens, cold greys).
local MATERIAL_COLORS: { [string]: { number } } = {
	Grass = { 96, 128, 68 },
	LeafyGrass = { 74, 104, 56 },
	Ground = { 112, 94, 72 },
	Mud = { 78, 66, 52 },
	Sand = { 172, 160, 128 },
	Rock = { 118, 120, 116 },
	Slate = { 92, 96, 98 },
	Pavement = { 132, 126, 116 },
}

return table.freeze({
	seed = 20261024,
	-- Tile placement: 512 x 512 columns of 4 studs (2,048 studs), covering the M0.5 greybox.
	n = 512,
	cell = 4,
	originX = -1024,
	originZ = -1360,
	floorY = -80, -- terrain is filled down to here (streaming drops features thinner than 64 studs)
	waterLevel = -3, -- lake surface
	padHeight = 0.2, -- ground level of the Map zones (tools/world/build.luau G)
	-- Terrain material under each Map zone, by zone part name.
	padMaterials = {
		VillageCore = "Grass",
		DevYard = "Pavement",
		WheatFields = "Grass",
		OrchardEdge = "LeafyGrass",
		GoblinCamp = "Mud",
	},
	-- Dirt roads painted into the terrain: x0, z0, x1, z1, half-width.
	roads = {
		{ 0, -80, 0, -770, 8 },
	},

	heightfield = {
		valleyNear = 40, -- distance from pads where hills start rising
		valleyFar = 520, -- distance where hills reach full amplitude
		hillAmp = 120,
		hillAmpVariation = 60,
		hillWavelength = 900,
		detailWavelength = 256,
		detailOctaves = 5,
		warpStrength = 0.35,
		redistribution = 1.4,
		ridgeStartZ = -900, -- north barrier ridge behind the goblin camp
		ridgeFullZ = -1250,
		ridgeHeight = 190,
		borderWidth = 260, -- hills rise toward the tile edge so the world reads enclosed
		borderHeight = 80,
		padFeather = 36,
	},

	erosion = {
		dropletsPerCell = 0.5,
		radius = 2,
		inertia = 0.05,
		capacity = 4,
		minSlope = 0.01,
		erodeSpeed = 0.3,
		depositSpeed = 0.3,
		evaporate = 0.01,
		gravity = 4,
		lifetime = 30,
		heightScale = 400, -- heights are divided by this so the droplet constants keep their meaning
		talusDeg = 38,
		thermalPasses = 10,
		baseLevel = 1, -- erosion never cuts below this where the ground started above it
	},

	water = {
		creekWidth = 10, -- half-width of the wet channel
		creekDepth = 5,
		creekBank = 22, -- half-width of the carved valley around the channel
		lakeDepth = 22,
		riverThreshold = 0.004, -- share of cells draining through a column to count as wet
	},

	paths = {
		maxGradeDeg = 20,
		halfWidth = 5,
		feather = 6,
		slopeCost = 12,
		waterCost = 40,
		tileSpacing = 7,
		poiRadius = 20,
		poiMinSpacing = 400,
	},

	scatter = {
		treeSampleRadius = 9, -- Poisson radius for canopy candidates
		rockSampleRadius = 12,
		canopyOverlap = 0.45, -- tree spacing as a share of summed footprint radii; crowns may interlock
		trunkClearance = 0.3, -- understory and cover keep this share of a tree or rock footprint clear
		coverCell = 6,
		padMargin = 6, -- keep props this far from gameplay pads and greybox parts
		maxCover = 9000,
	},

	materials = MATERIALS,
	materialColors = MATERIAL_COLORS,
	groups = GROUPS,
	biomes = BIOMES,
})
