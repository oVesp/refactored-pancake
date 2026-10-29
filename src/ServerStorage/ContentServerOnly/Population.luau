--!strict

--[=[
	Who lives in and moves through Midgard (docs/systems/open-world.md). Server-only so players
	cannot read nest sizes or timers. Points are `{ x, z }` on the ground; heights come from the
	world. Every route and roam loop is checked for walkable ground by
	`tests/specs/Population.spec.luau`, so keep legs on the valley floor or on generated corridors.

	Member `npc` ids resolve through `Shared/NpcDefs` (Content/Npcs or Content/Enemies). `level`
	defaults to the definition's range.
]=]

export type Point = { number }

export type Member = { npc: string, count: number, level: { number }? }

export type Formation = "Column" | "Line" | "Wedge" | "Ring"

--[=[ Stands at `at`; members wander `wander` studs around it. Respawns one by one. ]=]
export type Garrison = {
	id: string,
	at: Point,
	members: { Member },
	wander: number,
	respawnSeconds: number,
}

--[=[ Walks `points` in formation. Loops come back forever; open routes end and the group leaves. ]=]
export type Route = {
	points: { Point },
	loop: boolean,
	--[=[ Seconds to wait at a point index. ]=]
	stops: { [number]: number }?,
}

export type Troop = {
	id: string,
	members: { Member },
	formation: Formation,
	spacing: number,
	route: Route,
	--[=[ Seconds between dispatches while fewer than `max` are out. ]=]
	interval: number,
	max: number,
	--[=[ Only out at night (undead) or by day (traders). Nil: always. ]=]
	time: ("Day" | "Night")?,
}

--[=[ Townsfolk wandering a settlement. Fewer are out at night (the rest are indoors). ]=]
export type Residents = {
	id: string,
	npc: string,
	at: Point,
	radius: number,
	day: number,
	night: number,
}

--[=[
	A hidden source of monsters. `stationed` hold the lair; `squads` leave it in formation to
	roam `territory` (a loop of points). A squad is only sent out while no player is within
	`Tuning.Population.HiddenRadius` of `at`, so nobody sees it appear.
]=]
export type Nest = {
	id: string,
	at: Point,
	stationed: { Garrison },
	squads: { { members: { Member }, formation: Formation } },
	territory: { Point },
	maxSquads: number,
	interval: number,
	time: ("Day" | "Night")?,
}

local garrisons: { Garrison } = {
	{
		id = "south_gate",
		at = { 0, -84 },
		members = { { npc = "town_guard", count = 2 } },
		wander = 0,
		respawnSeconds = 120,
	},
	{
		id = "east_gate",
		at = { 84, 0 },
		members = { { npc = "town_guard", count = 1 }, { npc = "town_crossbow", count = 1 } },
		wander = 0,
		respawnSeconds = 120,
	},
	{
		id = "plaza_watch",
		at = { -20, 10 },
		members = { { npc = "town_guard", count = 1 } },
		wander = 18,
		respawnSeconds = 120,
	},
}

local patrols: { Troop } = {
	{
		id = "field_patrol",
		members = { { npc = "town_guard", count = 2 }, { npc = "town_crossbow", count = 2 } },
		formation = "Column",
		spacing = 5,
		route = {
			points = { { 0, -60 }, { 0, -200 }, { 0, -420 }, { 70, -380 }, { 70, -180 }, { 0, -60 } },
			loop = true,
			stops = { [3] = 20 },
		},
		interval = 180,
		max = 1,
	},
}

local caravans: { Troop } = {
	{
		id = "highland_caravan",
		members = {
			{ npc = "caravan_guard", count = 2 },
			{ npc = "merchant", count = 1 },
			{ npc = "caravan_guard", count = 1 },
		},
		formation = "Column",
		spacing = 6,
		route = {
			-- Down the highland stairs, through the orchard and fields, a market stop on the plaza,
			-- then back up the same way.
			points = {
				{ -291, -367 },
				{ -221, -394 },
				{ -229, -424 },
				{ -231, -456 },
				{ -227, -488 },
				{ -211, -516 },
				{ -182, -532 },
				{ -136, -533 },
				{ -99, -526 },
				{ -40, -470 },
				{ 0, -430 },
				{ 0, -205 },
				{ 0, -20 },
				{ 0, -205 },
				{ 0, -430 },
				{ -40, -470 },
				{ -99, -526 },
				{ -136, -533 },
				{ -182, -532 },
				{ -211, -516 },
				{ -227, -488 },
				{ -231, -456 },
				{ -229, -424 },
				{ -221, -394 },
				{ -291, -367 },
			},
			loop = false,
			stops = { [13] = 90 },
		},
		interval = 300,
		max = 1,
		time = "Day",
	},
}

local travelers: { Troop } = {
	{
		id = "field_walkers",
		members = { { npc = "traveler", count = 2 } },
		formation = "Line",
		spacing = 4,
		route = {
			points = { { 0, -20 }, { -60, -40 }, { -60, -150 }, { 0, -300 }, { 60, -200 }, { 0, -20 } },
			loop = false,
			stops = { [4] = 15 },
		},
		interval = 150,
		max = 1,
	},
	{
		id = "highland_pilgrim",
		members = { { npc = "traveler", count = 1 } },
		formation = "Column",
		spacing = 4,
		route = {
			points = {
				{ 0, -20 },
				{ 0, -430 },
				{ -99, -526 },
				{ -136, -533 },
				{ -182, -532 },
				{ -211, -516 },
				{ -227, -488 },
				{ -231, -456 },
				{ -229, -424 },
				{ -221, -394 },
				{ -291, -367 },
			},
			loop = false,
		},
		interval = 240,
		max = 1,
	},
}

local residents: { Residents } = {
	{ id = "village_folk", npc = "villager", at = { 0, 0 }, radius = 60, day = 8, night = 3 },
}

local nests: { Nest } = {
	{
		-- The camp is the one obvious lair; its raiding bands are what reach the farms.
		id = "goblin_camp",
		at = { 0, -650 },
		stationed = {
			{
				id = "chieftain",
				at = { 0, -725 },
				members = { { npc = "goblin_chieftain", count = 1, level = { 6, 6 } } },
				wander = 0,
				respawnSeconds = 240,
			},
			{
				id = "brutes",
				at = { 0, -695 },
				members = { { npc = "goblin_brute", count = 2, level = { 4, 5 } } },
				wander = 18,
				respawnSeconds = 90,
			},
			{
				id = "camp_west",
				at = { -40, -650 },
				members = {
					{ npc = "goblin_raider", count = 2, level = { 4, 4 } },
					{ npc = "goblin_trapper", count = 1, level = { 4, 4 } },
				},
				wander = 20,
				respawnSeconds = 60,
			},
			{
				id = "camp_east",
				at = { 40, -650 },
				members = {
					{ npc = "goblin_raider", count = 1, level = { 4, 4 } },
					{ npc = "goblin_slinger", count = 2, level = { 4, 4 } },
				},
				wander = 20,
				respawnSeconds = 60,
			},
		},
		squads = {
			{
				members = {
					{ npc = "goblin_raider", count = 3, level = { 3, 4 } },
					{ npc = "goblin_slinger", count = 1, level = { 3, 4 } },
				},
				formation = "Wedge",
			},
		},
		territory = { { 0, -600 }, { 0, -520 }, { -60, -480 }, { 70, -470 }, { 0, -600 } },
		maxSquads = 1,
		interval = 120,
	},
	{
		id = "orchard_thicket",
		at = { -90, -480 },
		stationed = {},
		squads = {
			{
				members = {
					{ npc = "goblin_raider", count = 2, level = { 3, 3 } },
					{ npc = "goblin_trapper", count = 1, level = { 3, 4 } },
				},
				formation = "Wedge",
			},
			{
				members = {
					{ npc = "goblin_slinger", count = 2, level = { 3, 4 } },
					{ npc = "goblin_raider", count = 1, level = { 3, 3 } },
				},
				formation = "Line",
			},
		},
		territory = { { -90, -480 }, { -40, -420 }, { 60, -480 }, { 40, -380 }, { -80, -380 }, { -90, -480 } },
		maxSquads = 2,
		interval = 90,
	},
	{
		id = "field_burrow",
		at = { -90, -260 },
		stationed = {},
		squads = {
			{
				members = { { npc = "goblin_raider", count = 3, level = { 1, 2 } } },
				formation = "Wedge",
			},
			{
				members = {
					{ npc = "goblin_raider", count = 2, level = { 2, 3 } },
					{ npc = "goblin_slinger", count = 1, level = { 2, 3 } },
				},
				formation = "Wedge",
			},
		},
		territory = { { -90, -260 }, { -60, -200 }, { 40, -170 }, { 70, -260 }, { -20, -300 }, { -90, -260 } },
		maxSquads = 2,
		interval = 60,
	},
	{
		-- Old graves at the edge of the fields; the dead walk only at night.
		id = "field_barrow",
		at = { 80, -300 },
		stationed = {},
		squads = {
			{
				members = { { npc = "skeleton", count = 2, level = { 1, 3 } } },
				formation = "Line",
			},
		},
		territory = { { 80, -300 }, { 40, -170 }, { -60, -200 }, { -20, -300 }, { 80, -300 } },
		maxSquads = 2,
		interval = 90,
		time = "Night",
	},
}

return table.freeze({
	Garrisons = garrisons,
	Patrols = patrols,
	Caravans = caravans,
	Travelers = travelers,
	Residents = residents,
	Nests = nests,
})
