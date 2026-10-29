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

-- Empty until the continent's regions are built: the centre section these lived in was replaced
-- by the continent generator (docs/systems/world-generation.md).
local garrisons: { Garrison } = {}
local patrols: { Troop } = {}
local caravans: { Troop } = {}
local travelers: { Troop } = {}
local residents: { Residents } = {}
local nests: { Nest } = {}

return table.freeze({
	Garrisons = garrisons,
	Patrols = patrols,
	Caravans = caravans,
	Travelers = travelers,
	Residents = residents,
	Nests = nests,
})
