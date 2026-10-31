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
		--[=[ Seconds a player cannot act after drawing or sheathing the weapon (combat mode toggle). ]=]
		DrawLock = 0.3,
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
		--[=[
			Dodge roll (docs/systems/combat.md, Dodge): a committed roll of `Duration` seconds, as in the
			Souls games. The player cannot act or steer until it ends, is invulnerable for the first
			`Invulnerable` seconds, and travels `Distance` studs on a slowing curve whose peak stays near
			walking speed (1.5 x Distance / Duration). `Cooldown` is the wait after the roll ends.
		]=]
		Dodge = table.freeze({
			Duration = 0.8,
			Invulnerable = 0.4,
			Cooldown = 0.15,
			StaminaCost = 20,
			Distance = 11.25,
		}),
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
		--[=[
			Player poise (docs/systems/combat.md, Poise and parry; Shared/Poise). A hit of less than
			`CastPoise` x max HP poise damage pushes a cast back by `Pushback` seconds, at most
			`PushbackMax` per cast; a heavier hit interrupts it. After a stun ends the player cannot be
			stunned again for `StunGuard` seconds.
		]=]
		Poise = table.freeze({ CastPoise = 0.15, Pushback = 0.25, PushbackMax = 0.75, StunGuard = 1.5 }),
	}),

	--[=[
		Threat (docs/systems/combat.md, Threat; Shared/Threat). Every NPC keeps threat per enemy and
		fights the top one, within the rules below.
	]=]
	Threat = table.freeze({
		--[=[ Threat per point of healing or shielding, split across the enemies fighting the healed ally. ]=]
		HealThreat = 0.5,
		--[=[ Opening threat for whoever engages an NPC first: the first hit, or the nearest in aggro radius. ]=]
		PullThreat = 10,
		--[=[ A challenger must exceed the current target's threat by this ratio, by the NPC's slot. ]=]
		SwitchRatio = table.freeze({ Melee = 1.1, Ranged = 1.3 }),
		--[=[ Share of threat lost per second on targets beyond the NPC's reach plus ReachSlack studs. ]=]
		DecayPerSecond = 0.05,
		ReachSlack = 6,
	}),

	--[=[
		Parry (docs/systems/combat.md, Poise and parry; Shared/Poise). A parry takes `combat.parryPoise`
		(default Poise) of the attacker's pool, scaled by clamp(1 + LevelStep x (defender level -
		attacker level), MinScale, MaxScale). Heavy attacks parry only in the first HeavyWindowShare
		of the parry window, unless the defender is the higher level. A break staggers the attacker
		for BreakSeconds and its next melee hit taken deals RiposteMultiplier damage; a parry that
		does not break makes it flinch for FlinchSeconds. Hitstops are the client's reaction.
	]=]
	Parry = table.freeze({
		Poise = 1,
		LevelStep = 0.1,
		MinScale = 0.25,
		MaxScale = 2,
		HeavyWindowShare = 0.5,
		BreakSeconds = 1.5,
		RiposteMultiplier = 1.5,
		FlinchSeconds = 0.2,
		BreakHitstop = 0.2,
		FlinchHitstop = 0.1,
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

	--[=[
		Hunger and thirst (docs/systems/stats-and-hud.md, Hunger and thirst). Each runs from Max to 0
		in SecondsToEmpty. Below LowThreshold of Max, HP and MP regen scale by LowRegenScale per need;
		an empty need stops that regen and drains StarvingHpPerSecond HP, never below FloorHp.
	]=]
	Needs = table.freeze({
		Max = 100,
		SecondsToEmpty = table.freeze({ Hunger = 40 * 60, Thirst = 25 * 60 }),
		LowThreshold = 0.25,
		LowRegenScale = 0.5,
		StarvingHpPerSecond = 0.5,
		FloorHp = 1,
		TickInterval = 1,
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
		--[=[ Walk speed multiplier while patrolling or travelling out of combat. ]=]
		PatrolSpeedMultiplier = 0.45,
		PathRecompute = 1,
		ReturnRegenPerSecond = 0.25,
		--[=[ Scales every definition's leashRadius: how far from home an NPC chases before it gives up. ]=]
		LeashMultiplier = 2,
		--[=[ Studs past the leash a target may stand and still be a valid target. ]=]
		TargetSlack = 30,
		--[=[ Seconds an NPC hunts a target's last known spot after losing it, before it walks home. ]=]
		LoseTargetGrace = 5,
	}),

	--[=[ Quest board and shops (docs/systems/economy.md). Studs. ]=]
	Quests = table.freeze({
		--[=[ A quest party spawns this far from the board. ]=]
		SpawnMin = 150,
		SpawnMax = 300,
		--[=[ Players use the board and shop vendors within this distance. ]=]
		Reach = 16,
		--[=[ Idle patrol radius of a quest party around its spot. ]=]
		PartyWander = 14,
	}),

	--[=[ Cascading tasks and leader following (docs/systems/ai-and-spawning.md, Tasks). Studs. ]=]
	--[=[ Summon skills (docs/systems/ai-and-spawning.md, Summons). Studs and seconds. ]=]
	Summons = table.freeze({
		--[=[ Most summons of any family one caster keeps at once. ]=]
		MaxPerCaster = 3,
		--[=[ Leash around the owner: a summon past it drops its fight and walks back. ]=]
		Leash = 45,
		--[=[ A summon this far from its owner is brought back to them. ]=]
		TeleportDistance = 90,
		--[=[ Studs behind the caster where a summon appears. ]=]
		SpawnBack = 5,
		SweepInterval = 0.5,
		--[=[ Seconds the picker stays open without a choice. ]=]
		PickerSeconds = 4,
	}),

	Tasks = table.freeze({
		--[=[ Shared/Tasks.FollowSettings: the loose clump behind a leader. Pace comes from the leader. ]=]
		Follow = table.freeze({
			Back = 6,
			Spacing = 6,
			RowWidth = 3,
			Jitter = 1.5,
			ArriveRadius = 2,
			ResumeRadius = 5,
			CatchUpDistance = 8,
			CatchUpFactor = 1.6,
			SettleFactor = 1.1,
		}),
		--[=[ FollowLeader only holds while the leader is this close; beyond it the follower falls through. ]=]
		LeaderRange = 120,
		--[=[ Guard looks for its tag within this distance of home and stands within GuardRadius of it. ]=]
		GuardRange = 120,
		GuardRadius = 8,
		--[=[ Idle patrol radius of a squad that lost its leader and has nobody to promote. ]=]
		LeaderlessWander = 10,
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
		AbstractSpeed = 0.4,
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
		--[=[
			Token budget per player target, by kind. Ally skills use Support, never the attack budget.
			A holder (guarding, or taunting a squad member) gets TankBonus extra Melee tokens.
		]=]
		Budget = table.freeze({ Melee = 2, Ranged = 1, Support = 1, TankBonus = 1 }),
		--[=[ Damage taken grows by PerEnemy for each attacker beyond the target's token budget, up to Max. ]=]
		Overwhelm = table.freeze({ PerEnemy = 0.03, Max = 0.15 }),
		--[=[
			Ranged enemies (`keepDistance`): after each attack they stand planted for `combat.plant`
			seconds (default Plant). Against a melee target they move away only with no attack ready,
			once per RetreatCooldown seconds and at most RetreatDistance studs.
		]=]
		Ranged = table.freeze({ Plant = 0.8, RetreatCooldown = 3, RetreatDistance = 6 }),
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
			Enemy poise pool (Shared/Poise). `combat.poiseMax` is the pool at the enemy's base stats
			(default DefaultShare x base max HP) and grows with max HP by level. Hits take poise damage of
			damage x the skill's `poiseDamage` (default DamageFactor); damage over time takes none. The
			pool refills after RefillDelay seconds without poise damage. A break cancels the windup, gives
			back the token and pauses decisions for Seconds; no new break for Cooldown seconds. The
			client's hitstop scales with the hit's poise factor, up to HitstopMaxScale.
		]=]
		Poise = table.freeze({
			DefaultShare = 0.2,
			DamageFactor = 1,
			RefillDelay = 3,
			Seconds = 0.6,
			Cooldown = 3,
			HitstopMaxScale = 2,
		}),
	}),
})
