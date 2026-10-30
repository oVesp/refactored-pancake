--!strict

export type PartyMember = {
	npc: string,
	count: number,
	level: { number },
}

export type QuestDef = {
	id: string,
	name: string,
	description: string,
	--[=[ Enemy ids whose kills count toward the quest. ]=]
	targets: { string },
	count: number,
	reward: { gold: number, xp: number },
	--[=[ The goblin party accepting the quest spawns in the world. ]=]
	party: { PartyMember },
}

--[=[
	Extermination quests on the guild hall's board (docs/systems/economy.md). Accepting one spawns its
	party `Tuning.Quests.SpawnMin` to `SpawnMax` studs from the board, away from water and safe zones.
]=]
local list: { QuestDef } = {
	{
		id = "thin_the_raiders",
		name = "Thin the Raiders",
		description = "Goblin raiders are scouting the fields. Cut down three of them.",
		targets = { "goblin_raider" },
		count = 3,
		reward = { gold = 30, xp = 40 },
		party = { { npc = "goblin_raider", count = 3, level = { 1, 2 } } },
	},
	{
		id = "slingers_in_the_grass",
		name = "Slingers in the Grass",
		description = "A band of slingers and raiders pelts travellers. Put down four of them.",
		targets = { "goblin_raider", "goblin_slinger" },
		count = 4,
		reward = { gold = 55, xp = 80 },
		party = {
			{ npc = "goblin_raider", count = 2, level = { 2, 3 } },
			{ npc = "goblin_slinger", count = 2, level = { 2, 3 } },
		},
	},
	{
		id = "brute_and_band",
		name = "The Brute and His Band",
		description = "A goblin brute leads a raiding band close to town. Kill the whole party.",
		targets = { "goblin_brute", "goblin_raider", "goblin_trapper" },
		count = 4,
		reward = { gold = 90, xp = 150 },
		party = {
			{ npc = "goblin_brute", count = 1, level = { 4, 4 } },
			{ npc = "goblin_raider", count = 2, level = { 3, 4 } },
			{ npc = "goblin_trapper", count = 1, level = { 3, 4 } },
		},
	},
}

local byId: { [string]: QuestDef } = {}
for _, quest in list do
	byId[quest.id] = table.freeze(quest)
end

return table.freeze({
	ById = table.freeze(byId),
	List = table.freeze(list),
})
