--!strict

--[=[
	Global tuning for M0.5 (progression, magic, combat, disciplines, death). Logic reads these;
	no magic numbers in services.
]=]
return table.freeze({
	Progression = table.freeze({
		LevelCap = 5,
		--[=[ XP needed to go from level n to n + 1. ]=]
		XpToNext = table.freeze({ 100, 250, 450, 700 }),
		--[=[ Kill XP = enemy xp * enemy level * clamp(1 + LevelGapStep * (enemy - player), Min, Max). ]=]
		KillXpLevelGapStep = 0.1,
		KillXpMin = 0.2,
		KillXpMax = 1.5,
	}),

	Magic = table.freeze({
		SpellPicksPerLevel = 1,
		--[=[ Circle n >= 2 unlocks at line level CircleStep * (n - 1); Circles 0 and 1 at line level 1. ]=]
		CircleStep = 6,
		MaxCircle = 10,
		--[=[ Circles lost when a character also has levels in an incompatible line; never below 1. ]=]
		MixedLinePenalty = 1,
		Compatible = table.freeze({
			arcane = table.freeze({ arcane = true }),
			divine = table.freeze({ divine = true }),
		}),
	}),

	Base = table.freeze({
		Stats = table.freeze({
			MaxHp = 100,
			MaxMp = 50,
			PhysAtk = 10,
			PhysDef = 10,
			Agility = 10,
			MagAtk = 10,
			MagDef = 10,
			Resistance = 10,
			Special = 0,
		}),
		MaxStamina = 100,
		StaminaRegen = 18,
		MpRegen = 1.5,
		MoveSpeed = 16,
		--[=[ Out-of-combat HP regen per second after OutOfCombatDelay seconds without damage. ]=]
		HpRegenOutOfCombat = 4,
		OutOfCombatDelay = 6,
	}),

	Combat = table.freeze({
		BaseCrit = 0.05,
		CritPerAgility = 0.002,
		CritMultiplier = 1.5,
		--[=[ Mitigation = 100 / (100 + defense). ]=]
		DefenseConstant = 100,
		TypeMultiplier = table.freeze({ resist = 0.5, vulnerable = 1.5, immune = 0 }),
		--[=[ Damage vs a higher-level target scales by 1 / (1 + (gap / Softness)^2). ]=]
		LevelGapSoftness = 8,
		--[=[ Harmful status duration scales by 100 / (100 + Resistance). ]=]
		ResistanceConstant = 100,
		MoveSpeedPerAgility = 0.005,
		CastSpeedPerAgility = 0.002,
		Guard = table.freeze({ DamageMultiplier = 0.4, ParryWindow = 0.25, StaminaPerHit = 10, Arc = 120 }),
		Dodge = table.freeze({ Invulnerable = 0.3, Cooldown = 1, StaminaCost = 20, Distance = 14 }),
		--[=[ Max seconds a player's hit check may rewind target positions (lag compensation). ]=]
		MaxRewind = 0.25,
		--[=[ Extra studs allowed on range checks for latency. ]=]
		RangeTolerance = 4,
		InCombatSeconds = 6,
	}),

	Disciplines = table.freeze({
		--[=[ Capacity = CapacityBase + floor(level / CapacityPerLevels). ]=]
		CapacityBase = 2,
		CapacityPerLevels = 7,
	}),

	Death = table.freeze({
		--[=[ XP debt added on death, as a fraction of XP needed for the current level. ]=]
		DebtFraction = 0.1,
		WeakenedDuration = 60,
		RespawnSeconds = 5,
	}),

	Npc = table.freeze({
		ThinkInterval = 0.25,
		PatrolRadius = 14,
		PathRecompute = 1,
		ReturnRegenPerSecond = 0.25,
		ActivePerZone = 20,
	}),
})
