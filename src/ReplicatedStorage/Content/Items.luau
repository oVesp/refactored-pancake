--!strict

local Types = require(script.Parent.Types)

--[=[
	Grade I placeholder items (scope 01, section 6). Capacity is shown in the inspector; Imprints
	are not editable in M0.5.
]=]
local list: { Types.ItemDef } = {
	{
		id = "rusty_sword",
		name = "Rusty Sword",
		kind = "Weapon",
		grade = 1,
		capacity = 10,
		modifiers = { PhysAtk = 4 },
		stack = 1,
		description = "A village blade. Suits a Warrior.",
	},
	{
		id = "apprentice_wand",
		name = "Apprentice Wand",
		kind = "Weapon",
		grade = 1,
		capacity = 10,
		modifiers = { MagAtk = 4 },
		stack = 1,
		description = "Channels arcane power. Suits a Mage.",
	},
	{
		id = "acolyte_staff",
		name = "Acolyte Staff",
		kind = "Weapon",
		grade = 1,
		capacity = 10,
		modifiers = { MagAtk = 2, HealingDone = 0.1 },
		stack = 1,
		description = "A plain staff. Suits a Healer.",
	},
	{
		id = "padded_vest",
		name = "Padded Vest",
		kind = "Armor",
		grade = 1,
		capacity = 8,
		modifiers = { PhysDef = 3, MaxHp = 10 },
		stack = 1,
		description = "Quilted cloth armor.",
	},
	{
		id = "cloth_robe",
		name = "Cloth Robe",
		kind = "Armor",
		grade = 1,
		capacity = 8,
		modifiers = { MagDef = 3, MaxMp = 10 },
		stack = 1,
		description = "A simple robe.",
	},
	{
		id = "minor_health_potion",
		name = "Minor Health Potion",
		kind = "Consumable",
		grade = 1,
		capacity = 0,
		use = { hp = 40 },
		stack = 10,
		description = "Restores 40 HP.",
	},
	{
		id = "minor_mana_potion",
		name = "Minor Mana Potion",
		kind = "Consumable",
		grade = 1,
		capacity = 0,
		use = { mp = 30 },
		stack = 10,
		description = "Restores 30 MP.",
	},
	{
		id = "goblin_trophy",
		name = "Goblin Trophy",
		kind = "Material",
		grade = 1,
		capacity = 0,
		stack = 50,
		description = "Proof of a goblin defeated. Crafting material later.",
	},
}

local byId: { [string]: Types.ItemDef } = {}
for _, item in list do
	byId[item.id] = table.freeze(item)
end

return table.freeze({
	ById = table.freeze(byId),
	--[=[ Equipment slots and the item kind each accepts. ]=]
	Slots = table.freeze({ weapon = "Weapon", armor = "Armor" }),
	--[=[ Items every new character starts with. ]=]
	Starter = table.freeze({
		{ id = "minor_health_potion", count = 3 },
		{ id = "minor_mana_potion", count = 2 },
	}),
	InventorySize = 24,
})
