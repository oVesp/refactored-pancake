--!strict

--[=[
	Pure game math shared by server and client. No requires and no Roblox services: callers pass
	content and tuning tables in, so every function is unit-testable under Lune.
]=]
local Formulas = {}

export type ClassEntry = { id: string, level: number }
export type StatBlock = { [string]: number }

local STAT_NAMES = { "MaxHp", "MaxMp", "PhysAtk", "PhysDef", "Agility", "MagAtk", "MagDef", "Resistance", "Special" }
Formulas.StatNames = table.freeze(STAT_NAMES)

local EXTRA_NAMES = {
	"MaxHpPct",
	"AllStatsPct",
	"MoveSpeedPct",
	"MpRegen",
	"HealingDone",
	"StatusChance",
	"HeavySpeed",
	"DamageDone",
	"SpellDamage",
	"SpellCost",
	"Haste",
	"AgilityPct",
	"MaxStamina",
	"StaminaRegenPct",
	"StaminaCost",
	"ExecuteDamage",
}
Formulas.ExtraNames = table.freeze(EXTRA_NAMES)

--[=[ Damage multiplier against a higher-level target: 1 for equal or lower, falling smoothly toward 0. ]=]
function Formulas.LevelGapMultiplier(attackerLevel: number, targetLevel: number, softness: number): number
	local gap = targetLevel - attackerLevel
	if gap <= 0 then
		return 1
	end
	return 1 / (1 + (gap / softness) ^ 2)
end

--[=[ Multiplier from a target's immune/resist/vulnerable tags for one damage or status type. ]=]
function Formulas.TypeMultiplier(
	kind: string,
	tags: { [string]: { string }? },
	multipliers: { [string]: number }
): number
	if tags.immune and table.find(tags.immune, kind) then
		return multipliers.immune
	end
	local result = 1
	if tags.resist and table.find(tags.resist, kind) then
		result *= multipliers.resist
	end
	if tags.vulnerable and table.find(tags.vulnerable, kind) then
		result *= multipliers.vulnerable
	end
	return result
end

--[=[ Fraction of damage that gets through a defense value. ]=]
function Formulas.Mitigation(defense: number, constant: number): number
	return constant / (constant + math.max(defense, 0))
end

--[=[
	Duration of the GCD or a cast after the `Haste` item affix (a fraction, clamped to
	[0, maxHaste]). Stats never shorten either.
]=]
function Formulas.Hasted(seconds: number, haste: number, maxHaste: number): number
	return seconds * (1 - math.clamp(haste, 0, maxHaste))
end

--[=[ Crit chance from agility, clamped to [0, 0.75]. ]=]
function Formulas.CritChance(agility: number, base: number, perAgility: number): number
	return math.clamp(base + agility * perAgility, 0, 0.75)
end

export type DamageInput = {
	base: number,
	attackStat: number,
	ratio: number,
	damageType: string,
	attackerLevel: number,
	targetLevel: number,
	defense: number,
	tags: { [string]: { string }? },
	critChance: number,
	--[=[ Uniform random in [0, 1); injected for determinism. ]=]
	roll: number,
	--[=[ Additive outgoing bonus, e.g. 0.4 for +40%. ]=]
	bonus: number,
	--[=[ Added to the crit multiplier, e.g. 0.15 for Weapon Proficiency III. ]=]
	critDamage: number?,
}

export type DamageConfig = {
	DefenseConstant: number,
	TypeMultiplier: { [string]: number },
	LevelGapSoftness: number,
	CritMultiplier: number,
}

--[=[
	Resolves one hit: (base + stat * ratio) * (1 + bonus) * type * crit * level gap * mitigation.
	Returns the rounded amount (0 only when immune) and whether it crit.
]=]
function Formulas.ResolveDamage(input: DamageInput, config: DamageConfig): (number, boolean)
	local typeMult = Formulas.TypeMultiplier(input.damageType, input.tags, config.TypeMultiplier)
	if typeMult == 0 then
		return 0, false
	end

	local crit = input.roll < input.critChance
	local raw = (input.base + input.attackStat * input.ratio) * math.max(0, 1 + input.bonus)
	local amount = raw
		* typeMult
		* (if crit then config.CritMultiplier + (input.critDamage or 0) else 1)
		* Formulas.LevelGapMultiplier(input.attackerLevel, input.targetLevel, config.LevelGapSoftness)
		* Formulas.Mitigation(input.defense, config.DefenseConstant)

	return math.max(1, math.floor(amount + 0.5)), crit
end

--[=[ Healing or shield amount: (base + stat * ratio) * (1 + bonus), rounded. ]=]
function Formulas.ResolveHeal(base: number, stat: number, ratio: number, bonus: number): number
	return math.max(0, math.floor((base + stat * ratio) * (1 + bonus) + 0.5))
end

--[=[
	Character level from total XP. Returns level, XP into that level, and XP needed for the next
	level (nil at the cap).
]=]
function Formulas.CharacterLevel(xp: number, xpToNext: { number }, cap: number): (number, number, number?)
	local level = 1
	local remaining = xp
	while level < cap do
		local need = xpToNext[level]
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return cap, remaining, nil
end

--[=[ XP for a kill, scaled by the level difference. ]=]
function Formulas.KillXp(
	enemyXp: number,
	enemyLevel: number,
	playerLevel: number,
	step: number,
	min: number,
	max: number
): number
	local scale = math.clamp(1 + step * (enemyLevel - playerLevel), min, max)
	return math.floor(enemyXp * enemyLevel * scale + 0.5)
end

--[=[ Applies an XP gain: debt is repaid first, the rest becomes XP. Returns new XP and new debt. ]=]
function Formulas.GainXp(xp: number, debt: number, gain: number): (number, number)
	local repaid = math.min(debt, gain)
	return xp + gain - repaid, debt - repaid
end

--[=[ Casting-line level needed for a Tier: 1 for Tiers 0-1, else step * (tier - 1) + 1. ]=]
function Formulas.TierUnlockLevel(tier: number, step: number): number
	if tier <= 1 then
		return 1
	end
	return step * (tier - 1) + 1
end

--[=[ Sum of class levels. ]=]
function Formulas.TotalClassLevels(classes: { ClassEntry }): number
	local total = 0
	for _, entry in classes do
		total += entry.level
	end
	return total
end

--[=[ Levels per casting line. ]=]
function Formulas.LineLevels(classes: { ClassEntry }, classDefs: { [string]: any }): { [string]: number }
	local lines: { [string]: number } = {}
	for _, entry in classes do
		local line = classDefs[entry.id] and classDefs[entry.id].line
		if line then
			lines[line] = (lines[line] or 0) + entry.level
		end
	end
	return lines
end

export type MagicConfig = {
	TierStep: number,
	MaxTier: number,
	MixedLinePenalty: number,
	Compatible: { [string]: { [string]: boolean } },
	SpellPicksPerLevel: number,
}

--[=[
	Highest Tier castable per casting line (game-design.md 3.2). The ceiling follows levels in that
	line only, since lines never sum; having levels in an incompatible line costs MixedLinePenalty
	Tiers, never below Tier 1.
]=]
function Formulas.TierCeilings(
	classes: { ClassEntry },
	classDefs: { [string]: any },
	config: MagicConfig
): { [string]: number }
	local lineLevels = Formulas.LineLevels(classes, classDefs)
	local ceilings: { [string]: number } = {}

	for line in lineLevels do
		local compatibleLevels = 0
		local mixed = false
		local compatible = config.Compatible[line] or {}
		for other, levels in lineLevels do
			if compatible[other] then
				compatibleLevels += levels
			else
				mixed = true
			end
		end

		local ceiling = 0
		for tier = 1, config.MaxTier do
			if compatibleLevels >= Formulas.TierUnlockLevel(tier, config.TierStep) then
				ceiling = tier
			end
		end
		if mixed and ceiling > 1 then
			ceiling = math.max(1, ceiling - config.MixedLinePenalty)
		end
		ceilings[line] = ceiling
	end

	return ceilings
end

local function levelOf(classes: { ClassEntry }, classId: string): number
	for _, entry in classes do
		if entry.id == classId then
			return entry.level
		end
	end
	return 0
end
Formulas.ClassLevel = levelOf

--[=[ Whether a character may put one unspent level into a class. Returns ok and a reason code. ]=]
function Formulas.CanTrain(
	classes: { ClassEntry },
	classId: string,
	classDefs: { [string]: any },
	characterLevel: number
): (boolean, string?)
	local def = classDefs[classId]
	if not def then
		return false, "UnknownClass"
	end
	if Formulas.TotalClassLevels(classes) >= characterLevel then
		return false, "NoUnspentLevel"
	end
	if levelOf(classes, classId) >= def.cap then
		return false, "ClassCapped"
	end
	return true, nil
end

--[=[ Class skills granted by current class levels, in build-path order. ]=]
function Formulas.GrantedSkills(classes: { ClassEntry }, classDefs: { [string]: any }): { string }
	local granted = {}
	for _, entry in classes do
		local def = classDefs[entry.id]
		if def then
			for level = 1, math.min(entry.level, #def.grants) do
				table.insert(granted, def.grants[level])
			end
		end
	end
	return granted
end

--[=[ Remaining spell picks per caster class: level * picksPerLevel minus spells known from its list. ]=]
function Formulas.SpellPicks(
	classes: { ClassEntry },
	knownSpells: { string },
	classDefs: { [string]: any },
	picksPerLevel: number
): { [string]: number }
	local picks: { [string]: number } = {}
	for _, entry in classes do
		local def = classDefs[entry.id]
		if def and #def.spellList > 0 then
			local known = 0
			for _, spellId in knownSpells do
				if table.find(def.spellList, spellId) then
					known += 1
				end
			end
			picks[entry.id] = math.max(0, entry.level * picksPerLevel - known)
		end
	end
	return picks
end

--[=[
	Whether a spell may be learned now: unknown, on the list of a class with a free pick, and at or
	below that line's Tier ceiling. Returns ok, a reason code and the class that pays the pick.
]=]
function Formulas.CanLearnSpell(
	classes: { ClassEntry },
	knownSpells: { string },
	spellId: string,
	classDefs: { [string]: any },
	skillDefs: { [string]: any },
	config: MagicConfig
): (boolean, string?, string?)
	local spell = skillDefs[spellId]
	if not spell or spell.source ~= "Spell" then
		return false, "UnknownSpell", nil
	end
	if table.find(knownSpells, spellId) then
		return false, "AlreadyKnown", nil
	end

	local ceilings = Formulas.TierCeilings(classes, classDefs, config)
	local picks = Formulas.SpellPicks(classes, knownSpells, classDefs, config.SpellPicksPerLevel)
	local reason = "NotOnClassList"
	for _, entry in classes do
		local def = classDefs[entry.id]
		if def and table.find(def.spellList, spellId) then
			if (ceilings[def.line] or -1) < (spell.tier or 0) then
				reason = "TierLocked"
			elseif (picks[entry.id] or 0) <= 0 then
				reason = "NoPick"
			else
				return true, nil, entry.id
			end
		end
	end
	return false, reason, nil
end

export type StatInput = {
	base: StatBlock,
	classes: { ClassEntry },
	classDefs: { [string]: any },
	--[=[ Flat and extra modifiers from passives, equipment and statuses. ]=]
	modifiers: { StatBlock },
}

--[=[
	Final stats: base + class growth + flat modifiers, then per-stat `<Stat>Pct` extras and AllStatsPct.
	Returns the nine stats and the extras (MoveSpeedPct, MpRegen, HealingDone, ...), extras default 0.
]=]
function Formulas.ComputeStats(input: StatInput): (StatBlock, StatBlock)
	local stats: StatBlock = {}
	for _, name in STAT_NAMES do
		stats[name] = input.base[name] or 0
	end
	local extras: StatBlock = {}
	for _, name in EXTRA_NAMES do
		extras[name] = 0
	end

	for _, entry in input.classes do
		local def = input.classDefs[entry.id]
		if def then
			for name, amount in def.growth do
				stats[name] = (stats[name] or 0) + amount * entry.level
			end
		end
	end

	for _, block in input.modifiers do
		for name, amount in block do
			if stats[name] ~= nil then
				stats[name] += amount
			elseif extras[name] ~= nil then
				extras[name] += amount
			end
		end
	end

	for _, name in STAT_NAMES do
		local pct = extras[name .. "Pct"]
		if pct then
			stats[name] *= 1 + pct
		end
	end
	if extras.AllStatsPct ~= 0 then
		for _, name in STAT_NAMES do
			stats[name] *= 1 + extras.AllStatsPct
		end
	end
	for _, name in STAT_NAMES do
		stats[name] = math.max(0, math.floor(stats[name] + 0.5))
	end

	return stats, extras
end

export type Traits = {
	--[=[ Highest Weapon Proficiency tier granted. ]=]
	proficiency: { damage: number, critDamage: number? }?,
	rhythm: { window: number, perStack: number, maxStacks: number }?,
	critEffects: { any },
	--[=[ Skill id -> overrides from upgrade passives; later grants win per field. ]=]
	upgrades: { [string]: { charges: number?, selfEffects: { any }? } },
}

--[=[
	Combat traits from granted passives (Weapon Proficiency, Battle Rhythm, crit effects, skill
	upgrades). Proficiency tiers override, they never add: the largest damage bonus counts.
]=]
function Formulas.CollectTraits(skillIds: { string }, skillDefs: { [string]: any }): Traits
	local traits: Traits = { proficiency = nil, rhythm = nil, critEffects = {}, upgrades = {} }
	for _, id in skillIds do
		local skill = skillDefs[id]
		if not skill or skill.kind ~= "Passive" then
			continue
		end
		local proficiency = skill.proficiency
		if proficiency and (not traits.proficiency or proficiency.damage > traits.proficiency.damage) then
			traits.proficiency = proficiency
		end
		if skill.rhythm then
			traits.rhythm = skill.rhythm
		end
		for _, effect in skill.critEffects or {} do
			table.insert(traits.critEffects, effect)
		end
		local upgrade = skill.upgrade
		if upgrade then
			local previous = traits.upgrades[upgrade.skill]
			traits.upgrades[upgrade.skill] = {
				charges = upgrade.charges or (previous and previous.charges),
				selfEffects = upgrade.selfEffects or (previous and previous.selfEffects),
			}
		end
	end
	return traits
end

--[=[ Battle Rhythm stacks after a hit at `now`: +1 (capped) within `window` of the last hit, else 0. ]=]
function Formulas.RhythmStacks(stacks: number, lastAt: number, now: number, window: number, maxStacks: number): number
	if now - lastAt <= window then
		return math.min(maxStacks, stacks + 1)
	end
	return 0
end

export type HitBonusInput = {
	--[=[ The attacker's DamageDone extra plus any skill bonus (Overcharge, Gather Strength). ]=]
	base: number,
	proficiency: number,
	rhythmStacks: number,
	perStack: number,
	execute: number,
	targetHpFraction: number,
	executeBelow: number,
	exposure: number,
}

--[=[ Outgoing damage bonus of one hit. Every source is additive into the single `bonus` term. ]=]
function Formulas.HitBonus(input: HitBonusInput): number
	local bonus = input.base + input.proficiency + input.rhythmStacks * input.perStack + input.exposure
	if input.targetHpFraction < input.executeBelow then
		bonus += input.execute
	end
	return bonus
end

--[=[ Seconds until a skill with `charges` has one ready; `readyAt` is when every charge is back. ]=]
function Formulas.ChargeReadyIn(readyAt: number, now: number, cooldown: number, charges: number): number
	return math.max(0, readyAt - now - (math.max(charges, 1) - 1) * cooldown)
end

--[=[ New `readyAt` after spending one charge at `now`. ]=]
function Formulas.ChargeSpend(readyAt: number, now: number, cooldown: number): number
	return math.max(readyAt, now) + cooldown
end

--[=[ Weapon type (Content/Weapons) of the equipped weapon item, or nil when unarmed. ]=]
function Formulas.EquippedWeapon(
	equipment: { [string]: number },
	inventory: { { uid: number, id: string } },
	itemDefs: { [string]: any }
): string?
	local uid = equipment.weapon
	if not uid then
		return nil
	end
	for _, stack in inventory do
		if stack.uid == uid then
			local item = itemDefs[stack.id]
			return item and item.weapon
		end
	end
	return nil
end

--[=[ The Weapon Proficiency weapon type: the stored choice, else the equipped type, else `default`. ]=]
function Formulas.ProficiencyFamily(chosen: string?, equipped: string?, default: string): string
	if chosen and chosen ~= "" then
		return chosen
	end
	return equipped or default
end

--[=[ Harmful status durations shrink with Resistance; helpful ones do not. ]=]
function Formulas.StatusDuration(duration: number, resistance: number, harmful: boolean, constant: number): number
	if not harmful then
		return duration
	end
	return duration * constant / (constant + math.max(resistance, 0))
end

--[=[ Discipline capacity (game-design.md 3.3). ]=]
function Formulas.DisciplineCapacity(level: number, base: number, perLevels: number): number
	return base + math.floor(level / perLevels)
end

--[=[ True when `point` lies within `radius` of `origin` and inside `angle` degrees of `facing` (flat XZ). ]=]
function Formulas.InArc(
	originX: number,
	originZ: number,
	facingX: number,
	facingZ: number,
	pointX: number,
	pointZ: number,
	radius: number,
	angle: number
): boolean
	local dx, dz = pointX - originX, pointZ - originZ
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance > radius then
		return false
	end
	if distance < 0.5 or angle >= 360 then
		return true
	end
	local facingLength = math.sqrt(facingX * facingX + facingZ * facingZ)
	if facingLength < 1e-6 then
		return true
	end
	local cosine = (dx * facingX + dz * facingZ) / (distance * facingLength)
	return cosine >= math.cos(math.rad(angle / 2))
end

return Formulas
