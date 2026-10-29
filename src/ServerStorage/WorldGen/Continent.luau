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
}

export type SiteKind = "capital" | "city" | "town" | "harbor" | "poi" | "dungeon" | "portal"

export type Site = {
	id: string,
	name: string,
	kind: SiteKind,
	region: string,
	owner: string?,
	at: { number }, -- { u, v } before jitter
	coastal: boolean?, -- moved to the nearest coast cell of its region
}

export type Biome = { color: { number } }

local Continent = {
	seed = 20261029,
	size = 10240, -- studs edge to edge, provisional (game-design §12)
	res = 256, -- grid cells per edge
	margin = 0.035, -- open sea kept around the map edge
	-- Land reaches `reach` times an anchor's `r`, give or take `amp` of coastline noise.
	coast = { reach = 1.45, amp = 0.25, scale = 0.09, octaves = 4 },
	warp = { amp = 0.05, scale = 0.16 }, -- bends region borders
	ridge = { width = 0.03, noise = 0.6 }, -- mountain bands along `ridges` borders
	spacing = { town = 0.06, poi = 0.035, dungeon = 0.04 }, -- minimum distance from any other site
	roads = { extra = 1.35, mountain = 9, slope = 6, reuse = 0.45 },

	biomes = {
		sea = { color = { 34, 62, 72 } },
		lake = { color = { 52, 92, 104 } },
		mountain = { color = { 104, 102, 112 } },
		volcanic = { color = { 150, 66, 50 } },
		tundra = { color = { 196, 212, 220 } },
		canyon = { color = { 112, 96, 104 } },
		highland = { color = { 124, 112, 150 } },
		sky = { color = { 214, 218, 236 } },
		wasteland = { color = { 192, 160, 108 } },
		magma = { color = { 178, 82, 46 } },
		swamp = { color = { 70, 104, 62 } },
		plains = { color = { 124, 160, 76 } },
		forest = { color = { 46, 84, 58 } },
		undead = { color = { 82, 70, 104 } },
		coast = { color = { 210, 196, 156 } },
		isles = { color = { 118, 140, 82 } },
	} :: { [string]: Biome },

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
			anchors = { { 0.28, 0.67, 0.09 }, { 0.35, 0.73, 0.07 } },
			towns = 3,
			pois = 2,
			dungeons = 1,
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
		{ 0.56, 0.33, 0.022 },
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
			at = { 0.22, 0.8 },
			coastal = true,
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
