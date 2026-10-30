--!strict

local Types = require(script.Parent.Types)

--[=[
	Starter classes (docs/systems/classes.md; scope 01, section 4). `grants[n]` is the class skill granted at
	class level n; caster levels also grant spell picks from `spellList` (Magic.SpellPicksPerLevel).
	`growth` is added once per class level.
]=]
local Classes: { [string]: Types.ClassDef } = {
	fighter = {
		id = "fighter",
		name = "Fighter",
		cap = 15,
		categories = { "Martial" },
		growth = { MaxHp = 18, MaxMp = 2, PhysAtk = 4, PhysDef = 2, Agility = 3, MagDef = 1 },
		grants = {
			"weapon_proficiency_1",
			"precise_attack",
			"combat_conditioning",
			"gather_strength",
			"second_wind",
			"weapon_proficiency_2",
			"heightened_senses",
			"battle_rhythm",
			"disengage",
			"exploit_weakness",
			"weapon_proficiency_3",
			"gather_strength_2",
			"keen_reflexes",
			"finishing_instinct",
			"battle_trance",
		},
		spellList = {},
	},
	mage = {
		id = "mage",
		name = "Mage",
		cap = 15,
		line = "arcane",
		growth = { MaxHp = 8, MaxMp = 15, MagAtk = 5, Agility = 2, MagDef = 1, Resistance = 1 },
		grants = { "arcane_line", "mana_flow", "blink", "elemental_focus", "overcharge" },
		spellList = { "light", "kindle", "spark", "firebolt", "frost_shard", "flame_fan", "ice_patch", "arcane_shield" },
	},
	healer = {
		id = "healer",
		name = "Healer",
		cap = 15,
		line = "divine",
		growth = { MaxHp = 10, MaxMp = 14, MagAtk = 3, MagDef = 3, Resistance = 3 },
		grants = { "divine_line", "gentle_hands", "rebuke", "devotion", "lay_on_hands" },
		spellList = { "glow", "purify_water", "mend", "smite", "cleanse", "renew", "shelter", "bless" },
	},
}

--[=[ Display and hotbar order. ]=]
local ORDER = { "fighter", "mage", "healer" }

return table.freeze({
	ById = table.freeze(Classes),
	Order = table.freeze(ORDER),
})
