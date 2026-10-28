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
		--[=[ Spells learned per caster class level, from that class's list. ]=]
		SpellPicksPerLevel = 1,
		--[=[ Tiers 0 and 1 unlock at line level 1; Tier n >= 2 at line level TierStep * (n - 1) + 1. ]=]
		TierStep = 7,
		MaxTier = 5,
		--[=[ Tiers lost when a character also has levels in an incompatible line; never below 1. ]=]
		MixedLinePenalty = 1,
		--[=[ Casting lines (magic systems). Each counts only its own levels; lines never sum. ]=]
		Compatible = table.freeze({
			arcane = table.freeze({ arcane = true }),
			divine = table.freeze({ divine = true }),
			spiritual = table.freeze({ spiritual = true }),
			alternative = table.freeze({ alternative = true }),
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
		--[=[
			Global cooldown and casting (docs/systems/combat.md, Timing). Only the `Haste` item affix
			shortens the GCD and cast times, never stats; it is capped at MaxHaste.
		]=]
		Gcd = table.freeze({
			Base = 2.5,
			MaxHaste = 0.3,
			--[=[ Every non-basic action locks further actions for this long (two weaves per GCD). ]=]
			AnimationLock = 0.6,
			--[=[ A press this close to an action becoming ready is queued and fires when it is. ]=]
			QueueWindow = 0.5,
			--[=[ Moving during the last seconds of a cast no longer cancels it. ]=]
			SlidecastWindow = 0.5,
			--[=[ Flat studs a caster may drift before the slidecast window without cancelling. ]=]
			MoveTolerance = 1.5,
		}),
		Guard = table.freeze({ DamageMultiplier = 0.4, ParryWindow = 0.25, StaminaPerHit = 10, Arc = 120 }),
		Dodge = table.freeze({ Invulnerable = 0.3, Cooldown = 1, StaminaCost = 20, Distance = 14 }),
		--[=[ Max seconds a player's hit check may rewind target positions (lag compensation). ]=]
		MaxRewind = 0.25,
		--[=[ Extra studs allowed on range checks for latency. ]=]
		RangeTolerance = 4,
		InCombatSeconds = 6,
	}),

	--[=[ Soft target, lock and aim assist (docs/systems/combat.md, Targeting). Studs and degrees. ]=]
	Targeting = table.freeze({
		--[=[ Max distance for the soft target and for keeping a lock. ]=]
		Range = 60,
		--[=[ Half-angle around the camera centre where enemies can become the soft target. ]=]
		ConeDegrees = 40,
		--[=[ Score bonus that keeps the current target until another is clearly more central. ]=]
		Stickiness = 0.25,
		--[=[ Weight of screen-centre angle vs distance in the score (1 = angle only). ]=]
		AngleWeight = 0.7,
		--[=[ Melee swings turn toward a target within skill range + this and MeleeAssistDegrees of the aim. ]=]
		MeleeAssistRange = 10,
		MeleeAssistDegrees = 60,
		--[=[ Touch and gamepad skillshots bend toward the target when it is within this angle. ]=]
		AimAssistDegrees = 8,
		--[=[ Homing spells give up after travelling this multiple of their range. ]=]
		HomingRangeFactor = 1.5,
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
