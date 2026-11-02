--!strict

-- Balance simulation (docs/systems/combat-ai-balance.md, Tuning and tests): one Fighter against N
-- same-level goblin raiders, using the real content, tuning and the pure rules in Shared/Swarm,
-- Shared/Poise and Shared/Formulas. It abstracts space: every raider holding a token is in
-- reach, the player's swings hit one raider (the one it focuses), and nobody walks. Fixed seeds
-- make every run repeatable. tools/sim/balance.luau prints the tables; Balance.spec asserts on them.
local Loader = require("./Loader")

local Formulas = Loader.load("src/ReplicatedStorage/Shared/Formulas")
local Poise = Loader.load("src/ReplicatedStorage/Shared/Poise")
local Swarm = Loader.load("src/ReplicatedStorage/Shared/Swarm")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")
local Enemies = Loader.load("src/ReplicatedStorage/Content/Enemies").ById
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById
local Statuses = Loader.load("src/ReplicatedStorage/Content/Statuses").ById
local Classes = Loader.load("src/ReplicatedStorage/Content/Classes").ById
local Items = Loader.load("src/ReplicatedStorage/Content/Items").ById

local DT = 0.05
local TIME_LIMIT = 240

local Balance = {}

--[=[
	Who plays. `parryRate` is the share of incoming parriable attacks the player parries when it
	could (not mid-swing for the DPS; while guarding for the tank). The tank guards between single
	opening slashes (`guardSeconds`) with a shield, which makes it a holder (+TankBonus tokens).
]=]
export type Persona = {
	name: string,
	level: number,
	shield: boolean,
	parryRate: number,
	--[=[ Tank only: seconds guarding between slashes; nil attacks nonstop. ]=]
	guardSeconds: number?,
}

Balance.Personas = {
	{ name = "DPS, no parries", level = 3, shield = false, parryRate = 0 },
	{ name = "DPS, parries 1 in 4", level = 3, shield = false, parryRate = 0.25 },
	{ name = "DPS, parries 1 in 2", level = 3, shield = false, parryRate = 0.5 },
	{ name = "Tank, shield, parries 1 in 4", level = 3, shield = true, parryRate = 0.25, guardSeconds = 1.5 },
} :: { Persona }

-- Park-Miller generator: deterministic in every runtime.
local function rng(seed: number): () -> number
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function()
		state = state * 16807 % 2147483647
		return (state - 1) / 2147483646
	end
end

local function playerStats(persona: Persona): { [string]: number }
	local modifiers = { Items.rusty_sword.modifiers, Items.padded_vest.modifiers }
	local stats = Formulas.ComputeStats({
		base = Tuning.Base.Stats,
		classes = { { id = "fighter", level = persona.level } },
		classDefs = Classes,
		modifiers = modifiers,
	})
	return stats
end

local function enemyStats(id: string, level: number): { [string]: number }
	local def = Enemies[id]
	local base = table.clone(def.base)
	for name, value in def.growth do
		base[name] = (base[name] or 0) + value * (level - 1)
	end
	return Formulas.ComputeStats({ base = base, classes = {}, classDefs = {}, modifiers = {} })
end

local function hit(skill: any, attacker: any, defender: any, roll: () -> number, bonus: number): number
	local spec = skill.damage
	local amount = Formulas.ResolveDamage({
		base = spec.base,
		attackStat = attacker.stats[spec.stat] or 0,
		ratio = spec.ratio,
		damageType = spec.type,
		attackerLevel = attacker.level,
		targetLevel = defender.level,
		defense = defender.stats.PhysDef or 0,
		tags = defender.tags or {},
		critChance = Formulas.CritChance(
			attacker.stats.Agility or 0,
			Tuning.Combat.BaseCrit,
			Tuning.Combat.CritPerAgility
		),
		roll = roll(),
		bonus = bonus,
	}, Tuning.Combat)
	return amount
end

export type Result = {
	won: boolean,
	seconds: number,
	hpLeft: number,
	parries: number,
	--[=[ Parries that broke the raider's pool; the rest flinched (full pool or stagger cooldown). ]=]
	parryBreaks: number,
	--[=[ Breaks by hits. ]=]
	hitBreaks: number,
}

--[=[ Fights `count` raiders at the persona's level with `seed`. ]=]
function Balance.Fight(persona: Persona, count: number, seed: number, enemyId: string?): Result
	local roll = rng(seed)
	local swarm = Tuning.Swarm
	local stats = playerStats(persona)
	local player = {
		level = persona.level,
		stats = stats,
		hp = stats.MaxHp,
		stamina = Tuning.Base.MaxStamina,
		tags = {},
	}
	local guard = Items.wooden_shield.shield
	local id = enemyId or "goblin_raider"
	local def = Enemies[id]
	local profile = Swarm.Profile(def, {
		tokenCost = swarm.TokenCost,
		morale = swarm.Morale.Default,
		poiseShare = swarm.Poise.DefaultShare,
		parryPoise = Tuning.Parry.Poise,
		plant = swarm.Ranged.Plant,
	}, Skills, Statuses)
	local attack = Skills[def.skills[1]]
	local enemies = {}
	for index = 1, count do
		local level = persona.level
		local enemyStatsBlock = enemyStats(id, level)
		table.insert(enemies, {
			key = index,
			level = level,
			stats = enemyStatsBlock,
			tags = def.tags,
			hp = enemyStatsBlock.MaxHp,
			pool = Poise.Pool(profile.poiseMax, profile.baseMaxHp, enemyStatsBlock.MaxHp),
			poise = 0,
			poiseAt = -math.huge,
			readyAt = roll() * attack.cooldown,
			windupEnds = nil :: number?,
			staggerUntil = 0,
			staggerReadyAt = 0,
			riposteUntil = 0,
			tempoOffset = roll() * 10,
		})
	end
	local ledger = Swarm.NewLedger()

	local chain = { "sword_slash", "sword_slash_2", "sword_slash_3" }
	local chainIndex = 1
	local swingEnds: number? = nil
	local swingHitAt = 0
	local guarding = false
	local guardUntil = 0
	local parries, parryBreaks, hitBreaks = 0, 0, 0

	local function drain(enemy: any, amount: number, now: number): boolean
		if now < enemy.staggerReadyAt or amount <= 0 then
			return false
		end
		local broken
		enemy.poise, broken = Poise.Hit(enemy.poise, enemy.poiseAt, amount, enemy.pool, swarm.Poise.RefillDelay, now)
		enemy.poiseAt = now
		return broken
	end

	local function stagger(enemy: any, seconds: number, now: number)
		enemy.staggerUntil = math.max(enemy.staggerUntil, now + seconds)
		enemy.staggerReadyAt = now + swarm.Poise.Cooldown
		enemy.windupEnds = nil
		Swarm.Drop(ledger, enemy.key)
	end

	local function result(won: boolean, seconds: number): Result
		return {
			won = won,
			seconds = seconds,
			hpLeft = math.max(0, player.hp),
			parries = parries,
			parryBreaks = parryBreaks,
			hitBreaks = hitBreaks,
		}
	end

	local now = 0
	while now < TIME_LIMIT do
		now += DT
		local alive = {}
		for _, enemy in enemies do
			if enemy.hp > 0 then
				table.insert(alive, enemy)
			end
		end
		if #alive == 0 then
			return result(true, now)
		end
		player.stamina = math.min(Tuning.Base.MaxStamina, player.stamina + Tuning.Base.StaminaRegen * DT)

		-- Player: the tank guards, then throws one slash, then guards again; the DPS chains nonstop.
		if not swingEnds then
			if persona.guardSeconds and not guarding then
				guarding = true
				guardUntil = now + persona.guardSeconds
			elseif guarding and (now >= guardUntil or player.stamina < guard.staminaPerHit) then
				guarding = false
			end
			if not guarding then
				local skill = Skills[chain[chainIndex]]
				swingEnds = now + skill.cooldown
				swingHitAt = now + skill.windup
			end
		end
		if swingEnds and now >= swingHitAt and swingHitAt > 0 then
			local skill = Skills[chain[chainIndex]]
			local target = alive[1]
			local bonus = 0
			if now < target.riposteUntil then
				bonus = Tuning.Parry.RiposteMultiplier - 1
				target.riposteUntil = 0
			end
			local amount = hit(skill, player, target, roll, bonus)
			target.hp -= amount
			local poise = Poise.Damage(amount, skill.poiseDamage, swarm.Poise.DamageFactor)
			if target.hp > 0 and drain(target, poise, now) then
				stagger(target, swarm.Poise.Seconds, now)
				hitBreaks += 1
			end
			if target.hp <= 0 then
				Swarm.Drop(ledger, target.key)
			end
			swingHitAt = 0
		end
		if swingEnds and now >= swingEnds then
			swingEnds = nil
			chainIndex = if chainIndex >= #chain or persona.guardSeconds then 1 else chainIndex + 1
		end

		-- Enemies: the director, tokens, tempo, windups, poise (as SquadService.tactic).
		local bonus = Swarm.Director({
			casting = false,
			locked = false,
			gcdRemaining = 0,
			hpRatio = player.hp / math.max(stats.MaxHp, 1),
		}, swarm.Director)
		local holder = Swarm.HolderBonus(guarding, false, swarm.Budget.TankBonus)
		local meleeCap = Swarm.Capacity(swarm.Budget.Melee, "Melee", bonus + holder)
		local budget = meleeCap + Swarm.Capacity(swarm.Budget.Ranged, "Ranged", bonus)
		local overwhelm = Swarm.Overwhelm(#alive, budget, swarm.Overwhelm.PerEnemy, swarm.Overwhelm.Max)
		Swarm.Sweep(ledger, now, swarm.TokenTimeout, swarm.WaitStale)
		for _, enemy in alive do
			if now < enemy.staggerUntil then
				continue
			end
			local windupEnds = enemy.windupEnds
			if windupEnds then
				if now >= windupEnds then
					enemy.windupEnds = nil
					-- The DPS parries by dropping its swing; the tank parries out of its guard.
					local canParry = if persona.guardSeconds then guarding else true
					local parried = canParry
						and Poise.Parries(Poise.ParryClass(attack), 0, 1, player.level, enemy.level, Tuning.Parry)
						and roll() < persona.parryRate
					if parried then
						parries += 1
						if not persona.guardSeconds then
							swingEnds, swingHitAt, chainIndex = nil, 0, 1
						end
						local damage =
							Poise.ParryDamage(enemy.pool, profile.parryPoise, player.level, enemy.level, Tuning.Parry)
						if drain(enemy, damage, now) then
							stagger(enemy, Tuning.Parry.BreakSeconds, now)
							enemy.riposteUntil = now + Tuning.Parry.BreakSeconds
							parryBreaks += 1
						else
							enemy.staggerUntil = now + Tuning.Parry.FlinchSeconds
						end
					else
						local amount = math.floor(hit(attack, enemy, player, roll, 0) * overwhelm + 0.5)
						if guarding and player.stamina >= guard.staminaPerHit then
							player.stamina -= guard.staminaPerHit
							amount = math.floor(amount * guard.damageMultiplier + 0.5)
						end
						player.hp -= amount
						if player.hp <= 0 then
							return result(false, now)
						end
					end
				end
				continue
			end
			local pressing = Swarm.TempoPhase(profile.tempo, enemy.tempoOffset, now) == "Pressure"
			if pressing and now >= enemy.readyAt then
				local granted = Swarm.Request(ledger, enemy.key, "Melee", profile.tokenCost, meleeCap, 1, now)
				if granted then
					enemy.readyAt = now + attack.cooldown
					enemy.windupEnds = now + attack.windup
					Swarm.Commit(ledger, enemy.key, now + attack.windup + swarm.RecoveryHold)
				end
			end
		end
	end
	return result(true, TIME_LIMIT)
end

--[=[ Share of `seeds` fights the persona survives against `count` raiders. ]=]
function Balance.WinRate(persona: Persona, count: number, seeds: number, enemyId: string?): number
	local wins = 0
	for seed = 1, seeds do
		if Balance.Fight(persona, count, seed * 7919, enemyId).won then
			wins += 1
		end
	end
	return wins / seeds
end

--[=[ The largest pack (up to `maxCount`) the persona survives in at least half of `seeds` fights. ]=]
function Balance.Capacity(persona: Persona, seeds: number, maxCount: number, enemyId: string?): number
	local capacity = 0
	for count = 1, maxCount do
		if Balance.WinRate(persona, count, seeds, enemyId) >= 0.5 then
			capacity = count
		else
			break
		end
	end
	return capacity
end

return Balance
