--!strict

--[=[
	Midgard continent template (docs/systems/world-generation.md). Authored data: `Gen/Continent`
	turns it and a seed into a continent map of regions, coast, mountains, sites and roads.

	Coordinates are unit map coordinates: `u` west to east and `v` north to south, both 0..1, so the
	layout reads like the sketch it came from. `size` turns them into studs. The template fixes where
	each region and named site roughly is; the seed varies the coastline, borders, mountain lines,
	minor sites and roads, so every seed is a similar but different Midgard.
]=]

export type Anchor = { number } -- { u, v, r }: a seed point of the region and its reach

export type Region = {
	id: string,
	name: string,
	biome: string,
	owner: string?, -- faction id (Content/Factions); nil: unclaimed
	height: number, -- base elevation 0..1
	relief: number, -- noise elevation 0..1 added on top
	anchors: { Anchor },
	-- Islands: `count` extra anchors spread around the first one, each a separate islet.
	scatter: { count: number, spread: number, r: { number } }?,
	sky: boolean?, -- floating isles above the land: no roads lead in
	towns: number,
	pois: number,
	dungeons: number,
	camps: number?, -- goblin camps (Gen/Camp)
}

export type SiteKind = "capital" | "city" | "town" | "harbor" | "poi" | "dungeon" | "portal" | "camp"

export type Site = {
	id: string,
	name: string,
	kind: SiteKind,
	region: string,
	owner: string?,
	at: { number }, -- { u, v } before jitter
	coastal: boolean?, -- moved to the nearest coast cell of its region
	fixed: boolean?, -- placed exactly at `at` (the Harbor village, which is the world origin)
}

export type Biome = {
	color: { number }, -- preview
	grass: string, -- terrain material on open ground
	ground: string, -- patches, roads and steep ground
	rock: string, -- cliffs and mountains
	sand: string, -- beaches and shallow beds
	detail: { number }, -- { studs, wavelength in studs } of small relief on top of the region height
	hills: { number }?, -- { studs, wavelength in studs } of rolling hills on top of that
	trees: number, -- trees per 10,000 square studs inside groves
	groves: number, -- share of the ground covered by groves, 0..1
	species: { [string]: number }, -- weights over `props.species`
	boulders: number, -- per 100,000 square studs
}

local Continent = {
	seed = 20261029,
	size = 20480, -- studs edge to edge (owner, 2026-10-29)
	res = 256, -- grid cells per edge (80 studs each)
	-- The Harbor village sits at studs 0, 0: the Map (spawn, trainers, zones) is built around it.
	origin = { 0.205, 0.815 },
	-- Heights in studs: water level, deepest seabed, beach rise over the water, height of region
	-- height 1, mountain peaks as a share of that, and the Map ground (tools/world/build.luau G).
	heights = { sea = -8, seabed = -70, beach = 3, scale = 300, mountain = 1.15, ground = 0.2 },
	-- Ground held flat at `heights.ground` under the Map's zones (studs from the origin), fading over
	-- `blend`; they count as `region` and stay dry. A test keeps them over Map.rbxmx's zones.
	pads = {
		region = "verdant",
		blend = 260,
		rects = {
			{ -100, -100, 100, 110 }, -- VillageCore
			{ -250, -100, -90, 100 }, -- DevYard
			{ -120, -330, 120, -90 }, -- WheatFields
			{ -120, -570, 120, -320 }, -- OrchardEdge
			{ -110, -770, 110, -550 }, -- GoblinCamp
		},
	} :: { region: string, blend: number, rects: { { number } } },
	bay = { x = 40, z = 470, r = 300 }, -- sea held south of the village, for the docks
	blend = 0.35, -- width of the slope between neighbouring regions, in anchor reaches
	offshore = 0.5, -- sea a region builds, in anchor reaches out from its coast
	offshoreMargin = 900, -- studs around a region's cells searched for its sea
	-- Signed-off regions: id to `Gen/Region.fingerprint`. Builds refuse to touch them unless forced.
	approved = {} :: { [string]: string },
	margin = 0.035, -- open sea kept around the map edge
	-- Land reaches `reach` times an anchor's `r`, give or take `amp` of coastline noise.
	coast = { reach = 1.45, amp = 0.25, scale = 0.09, octaves = 4 },
	warp = { amp = 0.05, scale = 0.16 }, -- bends region borders
	ridge = { width = 0.03, noise = 0.6 }, -- mountain bands along `ridges` borders
	spacing = { town = 0.06, poi = 0.035, dungeon = 0.04, camp = 0.04 }, -- minimum distance from any other site
	roads = { extra = 1.35, mountain = 9, slope = 6, reuse = 0.45 },

	-- Preview colours of what is not a biome.
	colors = {
		sea = { 34, 62, 72 },
		lake = { 52, 92, 104 },
		mountain = { 104, 102, 112 },
	} :: { [string]: { number } },

	-- Terrain material colours are global per material, so the palette lives on the realm.
	materialColors = {
		Grass = { 96, 136, 82 },
		LeafyGrass = { 78, 116, 80 },
		Ground = { 112, 102, 84 },
		Mud = { 86, 80, 66 },
		Sand = { 196, 182, 140 },
		Slate = { 108, 112, 118 },
		Rock = { 112, 112, 116 },
		Snow = { 226, 232, 238 },
		Basalt = { 62, 58, 60 },
		Sandstone = { 168, 132, 96 },
		Cobblestone = { 122, 120, 112 },
	} :: { [string]: { number } },

	biomes = {
		volcanic = {
			color = { 150, 66, 50 },
			grass = "Basalt",
			ground = "Ground",
			rock = "Basalt",
			sand = "Sand",
			detail = { 14, 260 },
			trees = 0.3,
			groves = 0.1,
			species = { dead = 1 },
			boulders = 6,
		},
		tundra = {
			color = { 196, 212, 220 },
			grass = "Snow",
			ground = "Glacier",
			rock = "Slate",
			sand = "Sand",
			detail = { 10, 300 },
			trees = 1.2,
			groves = 0.2,
			species = { pine = 1 },
			boulders = 4,
		},
		canyon = {
			color = { 112, 96, 104 },
			grass = "Sandstone",
			ground = "Ground",
			rock = "Sandstone",
			sand = "Sand",
			detail = { 18, 220 },
			trees = 0.2,
			groves = 0.1,
			species = { dead = 1 },
			boulders = 6,
		},
		highland = {
			color = { 124, 112, 150 },
			grass = "Grass",
			ground = "Ground",
			rock = "Slate",
			sand = "Sand",
			detail = { 12, 260 },
			hills = { 80, 1200 },
			trees = 3,
			groves = 0.35,
			species = { pine = 0.7, broad = 0.3 },
			boulders = 4,
		},
		sky = {
			color = { 214, 218, 236 },
			grass = "Grass",
			ground = "Ground",
			rock = "Slate",
			sand = "Sand",
			detail = { 6, 200 },
			trees = 1.5,
			groves = 0.3,
			species = { broad = 1 },
			boulders = 2,
		},
		wasteland = {
			color = { 192, 160, 108 },
			grass = "Sand",
			ground = "Sandstone",
			rock = "Sandstone",
			sand = "Sand",
			detail = { 8, 300 },
			trees = 0.2,
			groves = 0.1,
			species = { dead = 1 },
			boulders = 5,
		},
		magma = {
			color = { 178, 82, 46 },
			grass = "CrackedLava",
			ground = "Basalt",
			rock = "Basalt",
			sand = "Sand",
			detail = { 16, 240 },
			trees = 0.1,
			groves = 0.05,
			species = { dead = 1 },
			boulders = 6,
		},
		swamp = {
			color = { 70, 104, 62 },
			grass = "LeafyGrass",
			ground = "Mud",
			rock = "Slate",
			sand = "Mud",
			detail = { 3, 180 },
			trees = 1.8,
			groves = 0.4,
			species = { dead = 0.5, broad = 0.5 },
			boulders = 1,
		},
		plains = {
			color = { 124, 160, 76 },
			grass = "Grass",
			ground = "Ground",
			rock = "Slate",
			sand = "Sand",
			detail = { 5, 220 },
			hills = { 120, 1500 },
			trees = 7,
			groves = 0.32,
			species = { broad = 0.6, pine = 0.4 },
			boulders = 3,
		},
		forest = {
			color = { 46, 84, 58 },
			grass = "LeafyGrass",
			ground = "Ground",
			rock = "Slate",
			sand = "Sand",
			detail = { 8, 220 },
			hills = { 60, 900 },
			trees = 5,
			groves = 0.7,
			species = { broad = 0.6, pine = 0.4 },
			boulders = 2,
		},
		undead = {
			color = { 82, 70, 104 },
			grass = "Ground",
			ground = "Mud",
			rock = "Slate",
			sand = "Sand",
			detail = { 6, 240 },
			trees = 0.8,
			groves = 0.25,
			species = { dead = 1 },
			boulders = 3,
		},
		coast = {
			color = { 210, 196, 156 },
			grass = "Sand",
			ground = "Ground",
			rock = "Sandstone",
			sand = "Sand",
			detail = { 3, 200 },
			trees = 0.3,
			groves = 0.1,
			species = { broad = 1 },
			boulders = 1,
		},
		isles = {
			color = { 118, 140, 82 },
			grass = "Grass",
			ground = "Ground",
			rock = "Slate",
			sand = "Sand",
			detail = { 6, 200 },
			trees = 1.5,
			groves = 0.3,
			species = { broad = 0.5, pine = 0.5 },
			boulders = 2,
		},
	} :: { [string]: Biome },

	-- Goblin camps (Gen/Camp): palisade ring of `radius` studs, ground flattened under it and eased
	-- back over `flatten` studs. Village-kit models are `kitScale` studs per kit metre.
	camp = {
		radius = 86,
		gateWidth = 2,
		tents = 7,
		tentRing = 52,
		flatten = 60,
		clutter = { Crate = 8, Wagon = 1 },
	},
	kitScale = 3.2,

	-- Low-poly prop library (ServerStorage.WorldProps, tools/blender/world_props.py): each placement
	-- is `<prefix><two-digit variant>`; templates are already scaled to `height`.
	props = {
		groveScale = 700,
		species = {
			broad = { prefix = "Broadleaf", variants = 8, scale = { 0.8, 1.35 } },
			pine = { prefix = "Pine", variants = 8, scale = { 0.8, 1.4 } },
			dead = { prefix = "Snag", variants = 6, scale = { 0.8, 1.2 } },
		},
		bushes = { prefix = "Bush", variants = 6, perTree = 1.5, scale = { 0.8, 1.4 } },
		boulders = { prefix = "Boulder", variants = 6, scale = { 0.8, 4 } },
	},

	-- Territory colours on the preview.
	factionColors = {
		Adventurers = { 255, 214, 64 },
		HolyKingdom = { 236, 232, 200 },
		DragonEmpire = { 210, 60, 48 },
		Elves = { 120, 210, 120 },
		Dragons = { 255, 120, 40 },
		Undead = { 170, 110, 230 },
	} :: { [string]: { number } },

	regions = {
		{
			id = "dragons",
			name = "Land of Dragons",
			biome = "volcanic",
			owner = "Dragons",
			height = 0.55,
			relief = 0.35,
			anchors = { { 0.2, 0.19, 0.13 }, { 0.3, 0.14, 0.09 } },
			towns = 0,
			pois = 2,
			dungeons = 2,
		},
		{
			id = "tundra",
			name = "Tundras",
			biome = "tundra",
			owner = "DragonEmpire",
			height = 0.5,
			relief = 0.25,
			anchors = { { 0.29, 0.31, 0.09 }, { 0.4, 0.26, 0.1 }, { 0.51, 0.22, 0.09 } },
			towns = 2,
			pois = 2,
			dungeons = 1,
		},
		{
			id = "canyon",
			name = "Triad Canyon",
			biome = "canyon",
			owner = "DragonEmpire",
			height = 0.45,
			relief = 0.4,
			anchors = { { 0.62, 0.22, 0.09 }, { 0.66, 0.31, 0.07 } },
			towns = 1,
			pois = 2,
			dungeons = 1,
		},
		{
			id = "highlands",
			name = "The Highlands",
			biome = "highland",
			owner = "HolyKingdom",
			height = 0.35,
			relief = 0.2,
			anchors = { { 0.36, 0.43, 0.11 }, { 0.47, 0.38, 0.1 }, { 0.43, 0.52, 0.09 } },
			towns = 3,
			pois = 2,
			dungeons = 1,
		},
		{
			id = "sky",
			name = "Sky Isles",
			biome = "sky",
			owner = "HolyKingdom",
			height = 0.6,
			relief = 0.1,
			anchors = { { 0.27, 0.47, 0.045 } },
			sky = true,
			towns = 0,
			pois = 1,
			dungeons = 1,
		},
		{
			id = "wastelands",
			name = "Wastelands",
			biome = "wasteland",
			owner = "DragonEmpire",
			height = 0.25,
			relief = 0.15,
			anchors = { { 0.58, 0.44, 0.08 }, { 0.65, 0.39, 0.07 } },
			towns = 2,
			pois = 2,
			dungeons = 1,
		},
		{
			id = "magma",
			name = "Magma Wastelands",
			biome = "magma",
			owner = "DragonEmpire",
			height = 0.4,
			relief = 0.3,
			anchors = { { 0.73, 0.43, 0.07 }, { 0.75, 0.53, 0.07 } },
			towns = 1,
			pois = 1,
			dungeons = 2,
		},
		{
			id = "swamps",
			name = "Swamps",
			biome = "swamp",
			owner = "HolyKingdom",
			height = 0.06,
			relief = 0.05,
			anchors = { { 0.19, 0.5, 0.06 }, { 0.2, 0.59, 0.05 } },
			towns = 1,
			pois = 1,
			dungeons = 1,
		},
		{
			id = "verdant",
			name = "Verdant Greens",
			biome = "plains",
			owner = "HolyKingdom",
			height = 0.15,
			relief = 0.1,
			anchors = { { 0.28, 0.67, 0.09 }, { 0.35, 0.73, 0.07 }, { 0.225, 0.79, 0.035 } },
			towns = 3,
			pois = 2,
			dungeons = 1,
			camps = 2,
		},
		{
			id = "forests",
			name = "Deep Forests",
			biome = "forest",
			owner = "Elves",
			height = 0.2,
			relief = 0.12,
			anchors = { { 0.45, 0.66, 0.08 }, { 0.47, 0.76, 0.06 } },
			towns = 1,
			pois = 2,
			dungeons = 1,
		},
		{
			id = "undeadFields",
			name = "Undead Fields",
			biome = "undead",
			owner = "Undead",
			height = 0.18,
			relief = 0.12,
			anchors = { { 0.59, 0.64, 0.08 }, { 0.61, 0.75, 0.06 } },
			towns = 0,
			pois = 2,
			dungeons = 2,
		},
		{
			id = "undeadKingdom",
			name = "Undead Kingdom",
			biome = "undead",
			owner = "Undead",
			height = 0.22,
			relief = 0.15,
			anchors = { { 0.71, 0.73, 0.07 }, { 0.72, 0.83, 0.05 } },
			towns = 0,
			pois = 1,
			dungeons = 2,
		},
		{
			id = "coasts",
			name = "The Coasts",
			biome = "coast",
			height = 0.03,
			relief = 0.03,
			anchors = { { 0.34, 0.84, 0.05 }, { 0.46, 0.86, 0.055 }, { 0.58, 0.85, 0.05 } },
			towns = 2,
			pois = 1,
			dungeons = 0,
		},
		{
			id = "archipelago",
			name = "Archipelago",
			biome = "isles",
			height = 0.1,
			relief = 0.15,
			anchors = { { 0.82, 0.18, 0.02 } },
			scatter = { count = 10, spread = 0.09, r = { 0.007, 0.016 } },
			towns = 1,
			pois = 1,
			dungeons = 1,
		},
	} :: { Region },

	-- Pairs whose shared border is a mountain range.
	ridges = {
		{ "dragons", "tundra" },
		{ "tundra", "highlands" },
		{ "tundra", "canyon" },
		{ "canyon", "wastelands" },
		{ "wastelands", "magma" },
		{ "highlands", "swamps" },
	} :: { { string } },

	lakes = {
		{ 0.56, 0.33, 0.022, 0.3 }, -- { u, v, r, water level as a region height }
	} :: { { number } },

	-- Named sites. Names are placeholders until the content pass.
	sites = {
		{
			id = "central-capital",
			name = "Central Capital",
			kind = "capital",
			region = "highlands",
			owner = "Adventurers",
			at = { 0.46, 0.41 },
		},
		{
			id = "harbor",
			name = "Harbor",
			kind = "harbor",
			region = "verdant",
			owner = "Adventurers",
			at = { 0.205, 0.815 }, -- the origin
			fixed = true,
		},
		{
			-- The starter slice's camp, on the Map's GoblinCamp zone north of the Harbor.
			id = "goblin-camp",
			name = "Goblin Camp",
			kind = "camp",
			region = "verdant",
			owner = "Goblins",
			at = { 0.205, 0.815 - 660 / 20480 },
			fixed = true,
		},
		{
			id = "holy-capital",
			name = "Highland Capital",
			kind = "capital",
			region = "highlands",
			owner = "HolyKingdom",
			at = { 0.35, 0.47 },
		},
		{
			id = "dragon-capital",
			name = "Frosthold",
			kind = "capital",
			region = "tundra",
			owner = "DragonEmpire",
			at = { 0.47, 0.25 },
		},
		{
			id = "elf-city",
			name = "Eldergrove",
			kind = "city",
			region = "forests",
			owner = "Elves",
			at = { 0.46, 0.7 },
		},
		{ id = "dragons-roost", name = "Dragons Roost", kind = "dungeon", region = "dragons", at = { 0.17, 0.17 } },
		{ id = "sky-keep", name = "Sky Keep", kind = "poi", region = "sky", at = { 0.27, 0.47 } },
		{
			id = "fallen-kingdom",
			name = "Fallen Kingdom",
			kind = "dungeon",
			region = "undeadKingdom",
			owner = "Undead",
			at = { 0.7, 0.8 },
		},
		{
			id = "niflheim-gate",
			name = "Niflheim Gate",
			kind = "portal",
			region = "undeadKingdom",
			at = { 0.77, 0.76 },
			coastal = true,
		},
	} :: { Site },
}

return Continent
