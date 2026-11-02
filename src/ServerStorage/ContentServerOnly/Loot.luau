--!strict

export type Drop = {
	item: string,
	chance: number,
	min: number,
	max: number,
}

--[=[
	Drop tables per enemy id. Server-only: players must not see chances. Each entry rolls
	independently; drops go straight to the killer's inventory.
]=]
local Loot: { [string]: { Drop } } = {
	goblin_raider = {
		{ item = "goblin_trophy", chance = 0.6, min = 1, max = 1 },
		{ item = "bread", chance = 0.2, min = 1, max = 1 },
		{ item = "minor_health_potion", chance = 0.15, min = 1, max = 1 },
		{ item = "rusty_sword", chance = 0.04, min = 1, max = 1 },
	},
	goblin_slinger = {
		{ item = "goblin_trophy", chance = 0.6, min = 1, max = 1 },
		{ item = "water_flask", chance = 0.2, min = 1, max = 1 },
		{ item = "minor_mana_potion", chance = 0.15, min = 1, max = 1 },
		{ item = "padded_vest", chance = 0.04, min = 1, max = 1 },
	},
	goblin_trapper = {
		{ item = "goblin_trophy", chance = 0.6, min = 1, max = 2 },
		{ item = "minor_health_potion", chance = 0.2, min = 1, max = 1 },
		{ item = "apprentice_wand", chance = 0.05, min = 1, max = 1 },
		{ item = "cloth_robe", chance = 0.05, min = 1, max = 1 },
	},
	goblin_brute = {
		{ item = "goblin_trophy", chance = 1, min = 1, max = 3 },
		{ item = "cooked_meat", chance = 0.3, min = 1, max = 1 },
		{ item = "minor_health_potion", chance = 0.35, min = 1, max = 2 },
		{ item = "acolyte_staff", chance = 0.08, min = 1, max = 1 },
	},
	skeleton = {
		{ item = "minor_health_potion", chance = 0.15, min = 1, max = 1 },
		{ item = "minor_mana_potion", chance = 0.1, min = 1, max = 1 },
		{ item = "rusty_sword", chance = 0.03, min = 1, max = 1 },
	},
	zombie = {
		{ item = "minor_health_potion", chance = 0.1, min = 1, max = 1 },
	},
	goblin_chieftain = {
		{ item = "goblin_trophy", chance = 1, min = 3, max = 5 },
		{ item = "minor_health_potion", chance = 1, min = 2, max = 3 },
		{ item = "minor_mana_potion", chance = 1, min = 1, max = 2 },
		{ item = "rusty_sword", chance = 0.3, min = 1, max = 1 },
		{ item = "apprentice_wand", chance = 0.3, min = 1, max = 1 },
		{ item = "acolyte_staff", chance = 0.3, min = 1, max = 1 },
	},
}

for _, enemyId in
	{ "warband_soldier", "warband_archer", "goblin_hexer", "warband_shaman", "wolf_rider", "warband_captain" }
do
	Loot[enemyId] = { { item = "goblin_trophy", chance = 1, min = 2, max = 4 } }
end

return table.freeze(Loot)
