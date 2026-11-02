--!strict

export type Phase = "cast" | "launch" | "impact" | "resolve" | "swing" | "hit"

local LAUNCH_BY_TYPE: { [string]: string } = {
	physical = "ArrowRelease",
	force = "ArcaneCast",
	fire = "Fire",
	cold = "FrostCast",
	lightning = "Zap",
	holy = "HolyCast",
	poison = "PoisonCast",
	negative = "DarkCast",
	water = "WaterCast",
}

local IMPACT_BY_TYPE: { [string]: string } = {
	physical = "ArrowHit",
	force = "ArcaneHit",
	fire = "FireHit",
	cold = "FrostHit",
	lightning = "ZapHit",
	holy = "HolyHit",
	poison = "PoisonHit",
	negative = "DarkHit",
	water = "WaterHit",
}

local PUNCH = { swing = "PunchSwing" }
local BLADE = { hit = "BladeHit" }
local HEAVY_BLADE = { swing = "SwingHeavy", hit = "BladeHit" }
local CLAW = { hit = "ClawHit" }

-- Skills whose sound differs from their damage type's. `resolve` is an instant skill's only sound.
local BY_SKILL: { [string]: { [string]: string } } = {
	strike = PUNCH,
	strike_2 = PUNCH,
	strike_3 = PUNCH,
	shield_bash = PUNCH,
	heavy_strike = { swing = "SwingHeavy" },
	sword_slash = BLADE,
	sword_slash_2 = BLADE,
	sword_slash_3 = BLADE,
	sword_heavy = HEAVY_BLADE,
	cleave = HEAVY_BLADE,
	goblin_stab = BLADE,
	guard_strike = BLADE,
	soldier_strike = BLADE,
	chief_cleave = HEAVY_BLADE,
	skeleton_scratch = CLAW,
	zombie_claw = CLAW,
	flame_fan = { swing = "Fire" },
	sling_shot = { launch = "SlingWhip", impact = "StoneHit" },
	sleep = { launch = "DarkCast", impact = "SpellFizzle" },
	gather_strength = { resolve = "Buff" },
	second_wind = { resolve = "Heal" },
	heightened_senses = { resolve = "Buff" },
	battle_trance = { resolve = "Buff" },
	disengage = { resolve = "Dash" },
	charge = { resolve = "Dash" },
	wolf_charge = { resolve = "Dash" },
	war_cry = { resolve = "WarCry" },
	captain_rally = { resolve = "WarCry" },
	blink = { resolve = "Blink" },
	overcharge = { resolve = "Zap" },
	rebuke = { resolve = "HolyHit" },
	lay_on_hands = { resolve = "HolyHit" },
	mend = { resolve = "Heal" },
	shaman_heal = { resolve = "Heal" },
	renew = { resolve = "Heal" },
	cleanse = { resolve = "Heal" },
	bless = { resolve = "Buff" },
	glow = { resolve = "Buff" },
	light = { resolve = "Buff" },
	quick_march = { resolve = "Buff" },
	shelter = { resolve = "Ward" },
	arcane_shield = { resolve = "Ward" },
	anti_evil_protection = { resolve = "Ward" },
	ice_patch = { resolve = "FrostHit" },
	kindle = { resolve = "Fire" },
	purify_water = { resolve = "WaterHit" },
	create_water = { resolve = "WaterHit" },
	create_undead = { resolve = "Summon" },
	brute_slam = { resolve = "Quake" },
	chief_stomp = { resolve = "Quake" },
	archer_volley = { resolve = "ArrowHit" },
	poison_snare = { resolve = "PoisonHit" },
}

--[=[
	Which `Assets.Audio` key each skill plays at each phase of its use: per skill where it has its
	own sound, else by damage type. Cosmetic and read by the client's `VfxController`.
]=]
local SkillSounds = {}

--[=[ The audio key for `skill` at `phase`, or nil when that phase is silent. ]=]
function SkillSounds.For(skill: { [string]: any }, phase: Phase): string?
	local own = BY_SKILL[skill.id]
	if own and own[phase] then
		return own[phase]
	end
	local damageType = skill.damage and skill.damage.type
	if phase == "cast" then
		return if skill.castTime then "SpellCharge" else nil
	elseif phase == "launch" then
		return LAUNCH_BY_TYPE[damageType or "force"]
	elseif phase == "impact" then
		return IMPACT_BY_TYPE[damageType or "force"]
	elseif phase == "swing" then
		return "Swing"
	elseif phase == "hit" then
		return "Hit"
	end
	return nil
end

return table.freeze(SkillSounds)
