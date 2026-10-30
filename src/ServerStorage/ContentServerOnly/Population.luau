--!strict

--[=[
	Who lives in and moves through Midgard (docs/systems/open-world.md). Server-only so players
	cannot read nest sizes or timers. Points are `{ x, z }` on the ground; heights come from the
	world.

	Member `npc` ids resolve through `Shared/NpcDefs` (Content/Npcs or Content/Enemies). `level`
	defaults to the definition's range.
]=]

export type Point = { number }

export type Member = { npc: string, count: number, level: { number }? }

--[=[ Stands at `at`; members wander `wander` studs around it. Respawns one by one. ]=]
export type Garrison = {
	id: string,
	at: Point,
	members: { Member },
	wander: number,
	respawnSeconds: number,
}

--[=[ Walks `points`. Loops come back forever; open routes end and the group leaves. ]=]
export type Route = {
	points: { Point },
	loop: boolean,
	--[=[ Seconds to wait at a point index. ]=]
	stops: { [number]: number }?,
}

--[=[ The first member listed leads; the others trail it in a loose clump (Shared/Tasks). ]=]
export type Troop = {
	id: string,
	members: { Member },
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
	A hidden source of monsters. `stationed` hold the lair; `squads` leave it behind their first
	member to roam `territory` (a loop of points). A squad is only sent out while no player is within
	`Tuning.Population.HiddenRadius` of `at`, so nobody sees it appear.
]=]
export type Nest = {
	id: string,
	at: Point,
	stationed: { Garrison },
	squads: { { members: { Member } } },
	territory: { Point },
	maxSquads: number,
	interval: number,
	time: ("Day" | "Night")?,
}

-- Goblins only for now: a patrol around the camp and roaming squads from the camp and two burrows,
-- all on the Verdant Greens pads (docs/systems/world-generation.md). Other kinds return per site.
local garrisons: { Garrison } = {}
local patrols: { Troop } = {
	-- Circles just outside the goblin camp. Nobody here has `combat.leader`: without the Brute the
	-- squad falls apart until a new one is sent.
	{
		id = "goblin_camp_patrol",
		members = {
			{ npc = "goblin_brute", count = 1 },
			{ npc = "goblin_raider", count = 2, level = { 3, 4 } },
			{ npc = "goblin_slinger", count = 2 },
			{ npc = "goblin_trapper", count = 1 },
		},
		route = {
			points = { { -135, -560 }, { 135, -560 }, { 150, -700 }, { 0, -800 }, { -150, -700 } },
			loop = true,
			stops = { [3] = 6 },
		},
		interval = 180,
		max = 1,
	},
}
local caravans: { Troop } = {}
local travelers: { Troop } = {}
local residents: { Residents } = {}
local nests: { Nest } = {
	{
		-- The camp is the one obvious lair; its raiding bands are what reach the farms.
		id = "goblin_camp",
		at = { 0, -650 },
		stationed = {},
		squads = {
			{
				members = {
					{ npc = "goblin_raider", count = 3, level = { 3, 4 } },
					{ npc = "goblin_slinger", count = 1, level = { 3, 4 } },
				},
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
			},
			{
				members = {
					{ npc = "goblin_slinger", count = 2, level = { 3, 4 } },
					{ npc = "goblin_raider", count = 1, level = { 3, 3 } },
				},
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
			{ members = { { npc = "goblin_raider", count = 3, level = { 1, 2 } } } },
			{
				members = {
					{ npc = "goblin_raider", count = 2, level = { 2, 3 } },
					{ npc = "goblin_slinger", count = 1, level = { 2, 3 } },
				},
			},
		},
		territory = { { -90, -260 }, { -60, -200 }, { 40, -170 }, { 70, -260 }, { -20, -300 }, { -90, -260 } },
		maxSquads = 2,
		interval = 60,
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
