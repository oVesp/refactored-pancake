--!strict

local Types = require(script.Parent.Types)

--[=[
	Weapon types (docs/systems/weapons.md). An equipped weapon item names its type; with nothing
	equipped the character fights with fists. Each type swaps the basic attacks bound to light and
	heavy attack: sword and fists are melee chains, the bow is drawn and released, the staff mixes
	a melee chain with a charged bolt, the wand only casts bolts. Placeholder models live in
	ReplicatedStorage.Weapons.
]=]
local list: { Types.WeaponDef } = {
	{
		id = "fists",
		name = "Fists",
		hands = "One",
		light = "strike",
		heavy = "heavy_strike",
		guard = true,
	},
	{
		id = "sword",
		name = "Sword",
		hands = "One",
		light = "sword_slash",
		heavy = "sword_heavy",
		guard = true,
		model = "Sword",
		hand = "Right",
	},
	{
		id = "bow",
		name = "Bow",
		hands = "Two",
		light = "bow_shot",
		drawn = true,
		guard = false,
		model = "Bow",
		hand = "Left",
	},
	{
		id = "staff",
		name = "Staff",
		hands = "Two",
		light = "staff_strike",
		heavy = "staff_bolt",
		guard = true,
		model = "Staff",
		hand = "Right",
	},
	{
		id = "wand",
		name = "Wand",
		hands = "One",
		light = "wand_bolt",
		heavy = "wand_blast",
		guard = false,
		model = "Wand",
		hand = "Right",
	},
}

local byId: { [string]: Types.WeaponDef } = {}
for _, weapon in list do
	assert(not byId[weapon.id], `Duplicate weapon id {weapon.id}`)
	byId[weapon.id] = table.freeze(weapon)
end

return table.freeze({
	ById = table.freeze(byId),
	--[=[ Weapon type used with no weapon equipped. ]=]
	Default = "fists",
	--[=[ Basic attack a shield adds: light attack while guarding. ]=]
	ShieldBash = "shield_bash",
})
