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
		--[=[ Double-tapping W within DoubleTapWindow seconds runs at SpeedMultiplier until W is released or the player stops. ]=]
		Run = table.freeze({ DoubleTapWindow = 0.3, SpeedMultiplier = 1.5 }),
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
		--[=[ Light attack chain: max seconds between hits for the next press to continue it. ]=]
		Chain = table.freeze({ Window = 0.8 }),
		--[=[
			Melee commitment (docs/systems/combat.md, Timing): from a swing's press until its recovery
			ends the player moves at `MoveMultiplier` of normal speed and cannot act; the client steps
			`lunge` studs over `LungeSeconds` at the start; a dodge cancels the swing and its recovery.
		]=]
		Commit = table.freeze({ MoveMultiplier = 0.3, LungeSeconds = 0.12 }),
		--[=[ Guard without a shield; a shield brings its own values (Content/Items `shield`). ]=]
		Guard = table.freeze({ DamageMultiplier = 0.4, ParryWindow = 0.25, StaminaPerHit = 10, Arc = 120 }),
		--[=[
			Bow draw (docs/systems/weapons.md, Bow; Shared/Archery). Seconds of drawing: below MinDraw
			the release shoots nothing; damage grows from MinScale to full at FullDraw; a release within
			PerfectWindow after that adds PerfectBonus. The archer moves at DrawMoveMultiplier while
			drawing. Hits within RearArc degrees of the target's back get the skill's `rearBonus`.
		]=]
		Bow = table.freeze({
			MinDraw = 0.25,
			FullDraw = 0.85,
			PerfectWindow = 0.2,
			MinScale = 0.35,
			PerfectBonus = 0.5,
			DrawMoveMultiplier = 0.45,
			RearArc = 120,
		}),
		Dodge = table.freeze({ Invulnerable = 0.3, Cooldown = 1, StaminaCost = 20, Distance = 14 }),
		--[=[ Max seconds a player's hit check may rewind target positions (lag compensation). ]=]
		MaxRewind = 0.25,
		--[=[ Extra studs allowed on range checks for latency. ]=]
		RangeTolerance = 4,
		InCombatSeconds = 6,
		--[=[ HP fraction below which the `ExecuteDamage` bonus (Finishing Instinct) applies. ]=]
		ExecuteBelow = 0.3,
		--[=[
			Weapon types (Content/Weapons) Weapon Proficiency may choose; the first is the fallback
			when none is chosen or equipped (docs/systems/classes.md, Fighter).
		]=]
		ProficiencyWeapons = table.freeze({ "sword", "bow" }),
	}),

	--[=[ Soft target, lock and aim assist (docs/systems/combat.md, Targeting). Studs and degrees. ]=]
	Targeting = table.freeze({
		--[=[ Max distance for the soft target and for keeping a lock. ]=]
		Range = 60,
		--[=[ Seconds a locked target may stay out of line of sight before the lock breaks. ]=]
		LockSightGrace = 1,
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
	}),

	--[=[
		Open-world groups (docs/systems/open-world.md). A group far from every player exists as data
		only and moves along its route at `AbstractSpeed` of its slowest member; it gets bodies when a
		player comes within `MaterializeRadius` and loses them again beyond `DematerializeRadius`
		(never mid-fight). `MaxBodies` caps living NPC bodies on the server.
	]=]
	Population = table.freeze({
		TickInterval = 0.5,
		MaterializeRadius = 340,
		DematerializeRadius = 460,
		--[=[ A nest sends no squad while a player is this close, so nobody sees one appear. ]=]
		HiddenRadius = 160,
		MaxBodies = 80,
		AbstractSpeed = 0.7,
		--[=[ The leader walks this far ahead along its route. ]=]
		Lookahead = 12,
		--[=[ The leader waits while a follower is farther than this from its slot. ]=]
		FollowLag = 14,
		--[=[ Seconds between garrison respawn checks and schedule passes. ]=]
		ScheduleInterval = 5,
	}),

	--[=[
		Group combat (docs/systems/ai-and-spawning.md, Group combat). Every player target carries its
		own attack budget, shared by all teams attacking that player, so the total grows with the
		number of players in a fight.
	]=]
	Swarm = table.freeze({
		--[=[ Token budget per player target, by kind. Ally skills use Support, never the attack budget. ]=]
		Budget = table.freeze({ Melee = 2, Ranged = 1, Support = 1 }),
		--[=[ Default `combat.tokenCost`; large enemies set 2. ]=]
		TokenCost = 1,
		--[=[ Seconds a token stays taken after the attack's windup or cast ends. ]=]
		RecoveryHold = 0.6,
		--[=[ Seconds a granted token may go unused (walking into reach) before it is taken back. ]=]
		TokenTimeout = 4,
		--[=[ A waiter that has not asked again for this long loses its place in the queue. ]=]
		WaitStale = 0.75,
		--[=[ Studs beyond its reach where an enemy without a token waits. ]=]
		WaitDistance = 6,
		--[=[ Seconds between tactical updates (slot assignment) per target, staggered. ]=]
		TacticInterval = 0.5,
		--[=[ Engagement slots around each target, per ring (radius comes from each enemy's reach). ]=]
		Slots = table.freeze({ Melee = 6, Ranged = 8 }),
		--[=[ Slot cost added for leaving the current slot, and per taken neighbouring slot. ]=]
		SlotSwitchCost = 4,
		SlotCongestion = 3,
		--[=[ Allies closer than Radius studs push each other apart, up to Strength studs. ]=]
		Separation = table.freeze({ Radius = 4, Strength = 3 }),
		--[=[ Most squad members (per target and team) that may hold a role at once; others unlimited. ]=]
		RoleCaps = table.freeze({ Disruptor = 1, Flanker = 2 }),
		--[=[ Weight added to a member's current role so roles do not flip every update. ]=]
		RoleStickiness = 0.5,
		--[=[ Slot cost a Flanker pays for standing in front of the target, and Pressure for behind. ]=]
		FlankWeight = 12,
		PressureFrontWeight = 4,
		--[=[ Reads the player: windows (cast, lock, long GCD) open extra tokens; low HP closes one. ]=]
		Director = table.freeze({ WindowBonus = 1, WindowGcd = 1, MercyBelow = 0.25, MercyPenalty = 1 }),
		--[=[ Seconds between interrupt attempts on one player, across all disruptors. ]=]
		DisruptCooldown = 8,
		--[=[ Seconds of slack an interrupt must have before the player's cast would end. ]=]
		DisruptMargin = 0.2,
		--[=[ Morale (0-100 scale). Deaths count within Radius studs, a leader's within LeaderRadius. ]=]
		Morale = table.freeze({
			Default = table.freeze({ base = 100, fleeBelow = 30 }),
			DamageWeight = 60,
			AllyDeath = 15,
			LeaderDeath = 40,
			Regen = 3,
			RegenDelay = 6,
			LeaderBonus = 20,
			RallyBonus = 20,
			Hysteresis = 25,
			Radius = 30,
			LeaderRadius = 60,
			--[=[ A fleeing enemy whose home is closer than this to the attacker runs this far from it instead. ]=]
			FleeDistance = 30,
		}),
		--[=[
			Stagger: damage of `combat.poise` x max HP (default DefaultPoise) within Window seconds
			cancels the enemy's windup, gives back its token and pauses its decisions for Seconds;
			it cannot be staggered again for Cooldown seconds.
		]=]
		Stagger = table.freeze({ DefaultPoise = 0.2, Window = 3, Seconds = 0.6, Cooldown = 3 }),
	}),
})
