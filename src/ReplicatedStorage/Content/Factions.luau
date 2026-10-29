--!strict

export type FactionId = "Players" | "Town" | "Merchants" | "Travelers" | "Goblins" | "Undead" | "Neutral"

export type Standing = "Hostile" | "Neutral" | "Allied"

export type FactionDef = {
	id: FactionId,
	name: string,
	--[=[ Hostile to players: kept out of safe zones and shown as an enemy. ]=]
	monster: boolean,
}

--[=[
	Factions of the open world (docs/systems/open-world.md). Every entity's `team` is one of these.
	`Relations` lists each pair that is not Neutral; pairs are symmetric and a faction is always
	Allied with itself. Allies answer each other's calls for help; hostiles fight on sight.
]=]
local byId: { [FactionId]: FactionDef } = {
	Players = { id = "Players", name = "Adventurers", monster = false },
	Town = { id = "Town", name = "Villagers", monster = false },
	Merchants = { id = "Merchants", name = "Merchant Guild", monster = false },
	Travelers = { id = "Travelers", name = "Travelers", monster = false },
	Goblins = { id = "Goblins", name = "Goblins", monster = true },
	Undead = { id = "Undead", name = "Undead", monster = true },
	-- Training dummies: only players hit them.
	Neutral = { id = "Neutral", name = "Training", monster = false },
}

local relations: { { any } } = {
	{ "Players", "Town", "Allied" },
	{ "Players", "Merchants", "Allied" },
	{ "Players", "Travelers", "Allied" },
	{ "Town", "Merchants", "Allied" },
	{ "Town", "Travelers", "Allied" },
	{ "Merchants", "Travelers", "Allied" },
	{ "Players", "Neutral", "Hostile" },
	{ "Goblins", "Players", "Hostile" },
	{ "Goblins", "Town", "Hostile" },
	{ "Goblins", "Merchants", "Hostile" },
	{ "Goblins", "Travelers", "Hostile" },
	{ "Goblins", "Undead", "Hostile" },
	{ "Undead", "Players", "Hostile" },
	{ "Undead", "Town", "Hostile" },
	{ "Undead", "Merchants", "Hostile" },
	{ "Undead", "Travelers", "Hostile" },
}

for _, faction in byId do
	table.freeze(faction)
end

return table.freeze({
	ById = table.freeze(byId),
	Relations = table.freeze(relations),
})
