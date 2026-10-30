--!strict

local Types = require(script.Parent.Types)

--[=[
	Status effects (game-design.md 3.5). Magnitude and duration come from the applying effect.
	Dot/Hot magnitude = amount per tick; Move magnitude = fraction of speed removed.
	`modifiers` on Stats statuses use the same keys as passives.
	`cleanse` is not a status; applying it removes every status in `Cleansable`.
]=]
local list: { Types.StatusDef } = {
	{ id = "burn", name = "Burning", kind = "Dot", harmful = true, damageType = "fire", tickInterval = 1 },
	{ id = "poison", name = "Poisoned", kind = "Dot", harmful = true, damageType = "poison", tickInterval = 1 },
	{ id = "bleed", name = "Bleeding", kind = "Dot", harmful = true, damageType = "physical", tickInterval = 1 },
	{ id = "regen", name = "Renewing", kind = "Hot", harmful = false, tickInterval = 1 },
	{ id = "slow", name = "Slowed", kind = "Move", harmful = true },
	{ id = "root", name = "Rooted", kind = "Root", harmful = true },
	{ id = "stun", name = "Stunned", kind = "Stun", harmful = true },
	{ id = "fear", name = "Afraid", kind = "Stun", harmful = true },
	{ id = "taunt", name = "Taunted", kind = "Taunt", harmful = true },
	{ id = "shield", name = "Shielded", kind = "Shield", harmful = false },
	{ id = "light", name = "Lit", kind = "Light", harmful = false },
	{ id = "war_cry", name = "War Cry", kind = "Stats", harmful = false, modifiers = { PhysDef = 10 } },
	{
		id = "overcharge",
		name = "Overcharged",
		kind = "Stats",
		harmful = false,
		modifiers = { SpellDamage = 0.4, SpellCost = 0.5 },
	},
	{ id = "bless", name = "Blessed", kind = "Stats", harmful = false, modifiers = { PhysAtk = 5, MagAtk = 5 } },
	{ id = "hexed", name = "Hexed", kind = "Stats", harmful = true, modifiers = { DamageDone = -0.15 } },
	{
		id = "rally",
		name = "Rallied",
		kind = "Stats",
		harmful = false,
		modifiers = { PhysAtk = 4, MoveSpeedPct = 0.15 },
	},
	{
		id = "weakened",
		name = "Weakened",
		kind = "Stats",
		harmful = true,
		modifiers = { AllStatsPct = -0.1 },
	},
	{
		id = "dash_step",
		name = "Dash Step",
		kind = "Stats",
		harmful = false,
		modifiers = { MoveSpeedPct = 0.4 },
	},
	{
		id = "body_hardening",
		name = "Body Hardening",
		kind = "Stats",
		harmful = false,
		modifiers = { PhysDef = 15, MagDef = 5 },
	},

	-- Fighter (docs/systems/classes.md)
	{ id = "empowered", name = "Gathered Strength", kind = "Stats", harmful = false, nextHit = { damage = true } },
	{ id = "poised", name = "Poised", kind = "Stats", harmful = false, nextHit = { crit = true } },
	{
		id = "heightened_senses",
		name = "Heightened Senses",
		kind = "Stats",
		harmful = false,
		magnitudeStat = "AgilityPct",
	},
	{ id = "exposed", name = "Exposed", kind = "Stats", harmful = true, exposure = "physical" },
	{
		id = "battle_trance",
		name = "Battle Trance",
		kind = "Stats",
		harmful = false,
		modifiers = { DamageDone = 0.25, StaminaCost = -0.5 },
		fillsRhythm = true,
		expireSkill = "gather_strength",
	},
}

local byId: { [string]: Types.StatusDef } = {}
for _, status in list do
	byId[status.id] = table.freeze(status)
end

return table.freeze({
	ById = table.freeze(byId),
	Cleansable = table.freeze({ "poison", "bleed", "burn" }),
	--[=[ Statuses that interrupt a cast in progress when applied. ]=]
	Interrupts = table.freeze({ "stun", "fear" }),
})
