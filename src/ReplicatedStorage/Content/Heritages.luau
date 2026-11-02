--!strict

--[=[
	Heritages (races) by family (game-design.md 3.1). Human is the only playable heritage at
	launch; the rest are shown locked in the character creator so the roster reads as a world of
	many races. `playable` is the only gate; locked entries carry no stats yet.
]=]
export type HeritageDef = {
	id: string,
	name: string,
	family: string,
	playable: boolean,
	description: string,
}

local FAMILIES = { "Human", "Demi-Human", "Heteromorph" }

local LIST: { HeritageDef } = {
	{
		id = "human",
		name = "Human",
		family = "Human",
		playable = true,
		description = "Adaptable and short-lived. Humans have no heritage levels: every level goes into classes, so they reach the widest range of builds.",
	},
	{
		id = "dwarf",
		name = "Dwarf",
		family = "Human",
		playable = false,
		description = "Stout smiths and miners of the deep halls.",
	},
	{
		id = "forest_elf",
		name = "Forest Elf",
		family = "Human",
		playable = false,
		description = "Long-lived wardens of the old woods.",
	},
	{
		id = "goblin",
		name = "Goblin",
		family = "Demi-Human",
		playable = false,
		description = "Small, quick and quarrelsome raiders.",
	},
	{
		id = "orc",
		name = "Orc",
		family = "Demi-Human",
		playable = false,
		description = "Strong-backed warriors of the wild clans.",
	},
	{
		id = "ogre",
		name = "Ogre",
		family = "Demi-Human",
		playable = false,
		description = "Huge and hard to bring down.",
	},
	{
		id = "skeleton",
		name = "Skeleton",
		family = "Heteromorph",
		playable = false,
		description = "Undead bones bound by old magic.",
	},
	{
		id = "vampire",
		name = "Vampire",
		family = "Heteromorph",
		playable = false,
		description = "Undead nobles who feed on the living.",
	},
	{
		id = "slime",
		name = "Slime",
		family = "Heteromorph",
		playable = false,
		description = "A living ooze that dissolves what it touches.",
	},
}

local byId: { [string]: HeritageDef } = {}
local order: { string } = {}
for _, def in LIST do
	byId[def.id] = table.freeze(def)
	table.insert(order, def.id)
end

return table.freeze({
	ById = table.freeze(byId),
	--[=[ Display order: by family, playable first within each. ]=]
	Order = table.freeze(order),
	Families = table.freeze(FAMILIES),
	Default = "human",
})
