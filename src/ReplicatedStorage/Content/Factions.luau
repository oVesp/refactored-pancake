--!strict

export type FactionId =
	"Adventurers"
	| "HolyKingdom"
	| "DragonEmpire"
	| "Elves"
	| "Town"
	| "Merchants"
	| "Travelers"
	| "Goblins"
	| "Undead"
	| "Dragons"
	| "Neutral"

export type Standing = "Hostile" | "Neutral" | "Allied"

export type FactionDef = {
	id: FactionId,
	name: string,
	--[=[ Hostile to players: kept out of safe zones and shown as an enemy. ]=]
	monster: boolean,
}

--[=[
	Factions of the open world (docs/systems/open-world.md). Every entity's `team` is one of these.
	Players are Adventurers. The two empires are the great powers; the Adventurers are neutral to
	both. Town, Merchants and Travelers are civilian roles; the settlement they live in has an owner
	nation in the continent template (docs/systems/world-generation.md).

	`Relations` lists each pair that is not Neutral; pairs are symmetric and a faction is always
	Allied with itself. Allies answer each other's calls for help; hostiles fight on sight.
]=]
local byId: { [FactionId]: FactionDef } = {
	Adventurers = { id = "Adventurers", name = "Adventurers", monster = false },
	HolyKingdom = { id = "HolyKingdom", name = "Holy Kingdom", monster = false },
	DragonEmpire = { id = "DragonEmpire", name = "Dragon Empire", monster = false },
	Elves = { id = "Elves", name = "Elves", monster = false },
	Town = { id = "Town", name = "Villagers", monster = false },
	Merchants = { id = "Merchants", name = "Merchant Guild", monster = false },
	Travelers = { id = "Travelers", name = "Travelers", monster = false },
	Goblins = { id = "Goblins", name = "Goblins", monster = true },
	Undead = { id = "Undead", name = "Undead", monster = true },
	Dragons = { id = "Dragons", name = "Dragons", monster = true },
	-- Training dummies: only players hit them.
	Neutral = { id = "Neutral", name = "Training", monster = false },
}

local civilians = { "Adventurers", "Town", "Merchants", "Travelers" }
local nations = { "HolyKingdom", "DragonEmpire", "Elves" }

local relations: { { any } } = {
	{ "HolyKingdom", "DragonEmpire", "Hostile" },
	{ "Adventurers", "Neutral", "Hostile" },
	{ "Goblins", "Undead", "Hostile" },
	{ "Dragons", "Goblins", "Hostile" },
	{ "Dragons", "Undead", "Hostile" },
}
for i, a in civilians do
	for j = i + 1, #civilians do
		table.insert(relations, { a, civilians[j], "Allied" })
	end
end
-- Monsters fight every people; dragons leave the Dragon Empire and the Elves alone.
for _, monster in { "Goblins", "Undead", "Dragons" } do
	for _, people in civilians do
		table.insert(relations, { monster, people, "Hostile" })
	end
	for _, nation in nations do
		if monster ~= "Dragons" or nation == "HolyKingdom" then
			table.insert(relations, { monster, nation, "Hostile" })
		end
	end
end

for _, faction in byId do
	table.freeze(faction)
end

return table.freeze({
	ById = table.freeze(byId),
	Relations = table.freeze(relations),
})
