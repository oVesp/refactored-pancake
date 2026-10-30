--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Formulas = Loader.load("src/ReplicatedStorage/Shared/Formulas")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")
local Classes = Loader.load("src/ReplicatedStorage/Content/Classes").ById
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById

local function regenInput(overrides: { [string]: any }): any
	local input: { [string]: any } = {
		hp = 50,
		maxHp = 100,
		mp = 50,
		maxMp = 100,
		stamina = 50,
		maxStamina = 100,
		regenScale = 1,
		mpRegenBonus = 0,
		staminaRegenPct = 0,
		guarding = false,
		secondsSinceCombat = math.huge,
	}
	for key, value in overrides do
		input[key] = value
	end
	return input
end

return {
	["regen fills every pool and clamps at max"] = function()
		local base = Tuning.Base
		local hp, mp, stamina, changed = Formulas.Regen(regenInput({}), base, 1)
		Expect.near(hp, 50 + base.HpRegenOutOfCombat, "HP")
		Expect.near(mp, 50 + base.MpRegen, "MP")
		Expect.near(stamina, 50 + base.StaminaRegen, "Stamina")
		Expect.equal(changed, true, "changed")

		hp, mp, stamina = Formulas.Regen(regenInput({ hp = 99.9, mp = 99.9, stamina = 99.9 }), base, 100)
		Expect.equal(hp, 100, "HP cap")
		Expect.equal(mp, 100, "MP cap")
		Expect.equal(stamina, 100, "Stamina cap")
	end,
	["regen leaves full pools alone and reports no change"] = function()
		local hp, mp, stamina, changed =
			Formulas.Regen(regenInput({ hp = 100, mp = 100, stamina = 100 }), Tuning.Base, 1)
		Expect.equal(hp, 100, "HP")
		Expect.equal(mp, 100, "MP")
		Expect.equal(stamina, 100, "Stamina")
		Expect.equal(changed, false, "changed")
	end,
	["HP regen waits for the out of combat delay, MP and Stamina do not"] = function()
		local delay = Tuning.Base.OutOfCombatDelay
		local hp, mp, stamina = Formulas.Regen(regenInput({ secondsSinceCombat = delay }), Tuning.Base, 1)
		Expect.equal(hp, 50, "HP on the delay")
		Expect.truthy(mp > 50, "MP in combat")
		Expect.truthy(stamina > 50, "Stamina in combat")
		hp = Formulas.Regen(regenInput({ secondsSinceCombat = delay + 0.01 }), Tuning.Base, 1)
		Expect.truthy(hp > 50, "HP after the delay")
	end,
	["guarding stops Stamina regen only"] = function()
		local hp, mp, stamina = Formulas.Regen(regenInput({ guarding = true }), Tuning.Base, 1)
		Expect.truthy(hp > 50, "HP")
		Expect.truthy(mp > 50, "MP")
		Expect.equal(stamina, 50, "Stamina")
	end,
	["regen bonuses apply, and the need scale covers the MP bonus"] = function()
		local base = Tuning.Base
		local _, mp, stamina = Formulas.Regen(regenInput({ mpRegenBonus = 1, staminaRegenPct = 0.5 }), base, 1)
		Expect.near(mp, 50 + base.MpRegen + 1, "MP bonus")
		Expect.near(stamina, 50 + base.StaminaRegen * 1.5, "Stamina bonus")
		_, mp = Formulas.Regen(regenInput({ mpRegenBonus = 1, regenScale = 0.5 }), base, 1)
		Expect.near(mp, 50 + (base.MpRegen + 1) * 0.5, "scaled MP bonus")
	end,
	["regen keeps fractional HP"] = function()
		local hp = Formulas.Regen(regenInput({}), Tuning.Base, 0.1)
		Expect.near(hp, 50 + Tuning.Base.HpRegenOutOfCombat * 0.1, "fraction")
	end,
	["Second Wind restores 10% max HP and 40% Stamina"] = function()
		local skill = Skills.second_wind
		Expect.equal(skill.delivery, "Self", "delivery")
		local hp, stamina = Formulas.SelfRestore(skill.restore, 200, 150)
		Expect.near(hp, 20, "HP")
		Expect.near(stamina, 60, "Stamina")
	end,
	["self restore is 0 for a pool the skill does not name"] = function()
		local hp, stamina = Formulas.SelfRestore({ Stamina = 0.5 }, 200, 100)
		Expect.equal(hp, 0, "HP")
		Expect.near(stamina, 50, "Stamina")
		hp, stamina = Formulas.SelfRestore({ Hp = 0.5 }, 200, 100)
		Expect.near(hp, 100, "HP")
		Expect.equal(stamina, 0, "Stamina")
	end,
	["level gap is 1 at or below and falls smoothly above"] = function()
		Expect.near(Formulas.LevelGapMultiplier(5, 5, 8), 1, "equal")
		Expect.near(Formulas.LevelGapMultiplier(5, 1, 8), 1, "lower")
		Expect.near(Formulas.LevelGapMultiplier(1, 9, 8), 0.5, "gap 8")
		Expect.truthy(Formulas.LevelGapMultiplier(1, 31, 8) < 0.07, "gap 30 near zero")
	end,
	["type multiplier honors immune, resist, vulnerable"] = function()
		local m = Tuning.Combat.TypeMultiplier
		Expect.equal(Formulas.TypeMultiplier("fear", { immune = { "fear" } }, m), 0)
		Expect.equal(Formulas.TypeMultiplier("physical", { resist = { "physical" } }, m), 0.5)
		Expect.equal(Formulas.TypeMultiplier("holy", { vulnerable = { "holy" } }, m), 1.5)
		Expect.equal(Formulas.TypeMultiplier("fire", {}, m), 1)
	end,
	["damage resolves base, stat, mitigation and crit"] = function()
		local input = {
			base = 10,
			attackStat = 20,
			ratio = 1,
			damageType = "physical",
			attackerLevel = 1,
			targetLevel = 1,
			defense = 100,
			tags = {},
			critChance = 0.1,
			roll = 0.5,
			bonus = 0,
		}
		local amount, crit = Formulas.ResolveDamage(input, Tuning.Combat)
		Expect.equal(amount, 15)
		Expect.equal(crit, false)
		input.roll = 0
		amount, crit = Formulas.ResolveDamage(input, Tuning.Combat)
		Expect.equal(crit, true)
		Expect.equal(amount, 23)
		input.tags = { immune = { "physical" } }
		Expect.equal((Formulas.ResolveDamage(input, Tuning.Combat)), 0)
	end,
	["character level follows XP curve and caps at 5"] = function()
		local curve, cap = Tuning.Progression.XpToNext, Tuning.Progression.LevelCap
		Expect.equal((Formulas.CharacterLevel(0, curve, cap)), 1)
		Expect.equal((Formulas.CharacterLevel(99, curve, cap)), 1)
		Expect.equal((Formulas.CharacterLevel(100, curve, cap)), 2)
		local level, into, need = Formulas.CharacterLevel(100 + 250 + 10, curve, cap)
		Expect.equal(level, 3)
		Expect.equal(into, 10)
		Expect.equal(need, 450)
		local capped, _, none = Formulas.CharacterLevel(99999, curve, cap)
		Expect.equal(capped, 5)
		Expect.equal(none, nil)
	end,
	["xp repays debt first"] = function()
		local xp, debt = Formulas.GainXp(50, 30, 20)
		Expect.equal(xp, 50)
		Expect.equal(debt, 10)
		xp, debt = Formulas.GainXp(50, 10, 25)
		Expect.equal(xp, 65)
		Expect.equal(debt, 0)
	end,
	["tier n unlocks at line level 7 * (n - 1) + 1, levels 1-7 cap at tier 1"] = function()
		local magic = Tuning.Magic
		Expect.equal(Formulas.TierUnlockLevel(0, magic.TierStep), 1)
		Expect.equal(Formulas.TierUnlockLevel(1, magic.TierStep), 1)
		Expect.equal(Formulas.TierUnlockLevel(2, magic.TierStep), 8)
		Expect.equal(Formulas.TierUnlockLevel(3, magic.TierStep), 15)
		Expect.equal(Formulas.TierUnlockLevel(4, magic.TierStep), 22)
		Expect.equal(Formulas.TierUnlockLevel(5, magic.TierStep), 29)
		Expect.equal(magic.MaxTier, 5)
		local ceilings = Formulas.TierCeilings({ { id = "mage", level = 7 } }, Classes, magic)
		Expect.equal(ceilings.arcane, 1)
		ceilings = Formulas.TierCeilings({ { id = "mage", level = 8 } }, Classes, magic)
		Expect.equal(ceilings.arcane, 2)
		ceilings = Formulas.TierCeilings({ { id = "mage", level = 30 } }, Classes, magic)
		Expect.equal(ceilings.arcane, 5)
	end,
	["lines never sum and mixed incompatible lines lose a tier but keep tier 1"] = function()
		local mixed = { { id = "mage", level = 15 }, { id = "healer", level = 7 } }
		local ceilings = Formulas.TierCeilings(mixed, Classes, Tuning.Magic)
		Expect.equal(ceilings.arcane, 2)
		Expect.equal(ceilings.divine, 1)
	end,
	["tier 2 spell refused at line level 7, allowed at 8"] = function()
		local fakeSkills = table.clone(Skills)
		fakeSkills.test_t2 = { id = "test_t2", source = "Spell", tier = 2, line = "arcane" }
		local fakeClasses = table.clone(Classes)
		local mage = table.clone(Classes.mage)
		mage.spellList = table.clone(mage.spellList)
		table.insert(mage.spellList, "test_t2")
		fakeClasses.mage = mage
		local ok, reason = Formulas.CanLearnSpell(
			{ { id = "mage", level = 7 } },
			{},
			"test_t2",
			fakeClasses,
			fakeSkills,
			Tuning.Magic
		)
		Expect.equal(ok, false)
		Expect.equal(reason, "TierLocked")
		local okAt8 = Formulas.CanLearnSpell(
			{ { id = "mage", level = 8 } },
			{},
			"test_t2",
			fakeClasses,
			fakeSkills,
			Tuning.Magic
		)
		Expect.truthy(okAt8)
	end,
	["spell picks: one per level, only from own list"] = function()
		local classes = { { id = "mage", level = 2 }, { id = "fighter", level = 1 } }
		local ok, _, payer = Formulas.CanLearnSpell(classes, {}, "magic_arrow", Classes, Skills, Tuning.Magic)
		Expect.truthy(ok)
		Expect.equal(payer, "mage")
		local okFull, reasonFull = Formulas.CanLearnSpell(
			classes,
			{ "magic_arrow", "destruction_water" },
			"sleep",
			Classes,
			Skills,
			Tuning.Magic
		)
		Expect.equal(okFull, false)
		Expect.equal(reasonFull, "NoPick")
		local okOther, reasonOther = Formulas.CanLearnSpell(classes, {}, "mend", Classes, Skills, Tuning.Magic)
		Expect.equal(okOther, false)
		Expect.equal(reasonOther, "NotOnClassList")
	end,
	["training needs an unspent level and respects the class cap"] = function()
		Expect.truthy(Formulas.CanTrain({}, "fighter", Classes, 1))
		local ok, reason = Formulas.CanTrain({ { id = "fighter", level = 1 } }, "mage", Classes, 1)
		Expect.equal(ok, false)
		Expect.equal(reason, "NoUnspentLevel")
		local okCap, reasonCap = Formulas.CanTrain({ { id = "fighter", level = 15 } }, "fighter", Classes, 20)
		Expect.equal(okCap, false)
		Expect.equal(reasonCap, "ClassCapped")
	end,
	["each M0.5 template reaches 5 levels"] = function()
		local templates = {
			{ fighter = 5 },
			{ fighter = 3, mage = 2 },
			{ mage = 2, healer = 2, fighter = 1 },
			{ healer = 3, mage = 1, fighter = 1 },
		}
		for _, template in templates do
			local classes = {}
			for classId, target in template do
				for _ = 1, target do
					Expect.truthy(Formulas.CanTrain(classes, classId, Classes, 5))
					local found = false
					for _, entry in classes do
						if entry.id == classId then
							entry.level += 1
							found = true
						end
					end
					if not found then
						table.insert(classes, { id = classId, level = 1 })
					end
				end
			end
			Expect.equal(Formulas.TotalClassLevels(classes), 5)
		end
	end,
	["granted skills follow class levels"] = function()
		local granted = Formulas.GrantedSkills({ { id = "fighter", level = 2 }, { id = "mage", level = 1 } }, Classes)
		Expect.equal(table.concat(granted, ","), "weapon_proficiency_1,precise_attack,arcane_line")
	end,
	["stats combine growth, modifiers and percentages"] = function()
		local stats, extras = Formulas.ComputeStats({
			base = Tuning.Base.Stats,
			classes = { { id = "fighter", level = 2 } },
			classDefs = Classes,
			modifiers = { { MaxHpPct = 0.1, PhysDef = 5 }, { MoveSpeedPct = 0.4 }, { AgilityPct = 0.4 } },
		})
		Expect.equal(stats.MaxHp, 150)
		Expect.equal(stats.PhysDef, 19)
		Expect.equal(stats.Agility, 22)
		Expect.near(extras.MoveSpeedPct, 0.4, "move")
		local weakened = Formulas.ComputeStats({
			base = Tuning.Base.Stats,
			classes = {},
			classDefs = Classes,
			modifiers = { { AllStatsPct = -0.1 } },
		})
		Expect.equal(weakened.MaxHp, 90)
	end,
	["fighter grants all 15 levels, tiers of a passive override"] = function()
		local fighter = Classes.fighter
		Expect.equal(fighter.cap, 15)
		Expect.equal(#fighter.grants, 15)
		local function traitsAt(level: number)
			return Formulas.CollectTraits(
				Formulas.GrantedSkills({ { id = "fighter", level = level } }, Classes),
				Skills
			)
		end
		Expect.near(traitsAt(1).proficiency.damage, 0.1, "WP I")
		Expect.near(traitsAt(6).proficiency.damage, 0.2, "WP II")
		local top = traitsAt(15)
		Expect.near(top.proficiency.damage, 0.3, "WP III")
		Expect.near(top.proficiency.critDamage, 0.15, "WP III crit damage")
		Expect.equal(top.upgrades.gather_strength.charges, 2)
		Expect.near(top.upgrades.gather_strength.selfEffects[1].magnitude, 0.75, "GS II bonus")
		Expect.near(top.upgrades.heightened_senses.selfEffects[1].magnitude, 0.6, "Keen Reflexes agility")
		Expect.equal(top.upgrades.heightened_senses.selfEffects[1].duration, 12)
		Expect.equal(top.critEffects[1].status, "exposed")
		Expect.equal(traitsAt(11).upgrades.gather_strength, nil)
	end,
	["gather strength adds 50% to the next hit, additively"] = function()
		local gather = Skills.gather_strength.selfEffects[1]
		Expect.near(gather.magnitude, 0.5, "magnitude")
		Expect.equal(gather.duration, 8)
		local input = {
			base = 6,
			attackStat = 10,
			ratio = 0.6,
			damageType = "physical",
			attackerLevel = 1,
			targetLevel = 1,
			defense = 0,
			tags = {},
			critChance = 0,
			roll = 0.5,
			bonus = 0,
		}
		local plain = Formulas.ResolveDamage(input, Tuning.Combat)
		input.bonus = Formulas.HitBonus({
			base = gather.magnitude,
			proficiency = 0.1,
			rhythmStacks = 0,
			perStack = 0.02,
			execute = 0,
			targetHpFraction = 1,
			executeBelow = 0.3,
			exposure = 0,
		})
		Expect.equal(plain, 12)
		Expect.equal(Formulas.ResolveDamage(input, Tuning.Combat), 19)
	end,
	["battle rhythm stacks within the window, caps and resets"] = function()
		local rhythm = Skills.battle_rhythm.rhythm
		local stacks, at = 0, -math.huge
		for i = 1, 7 do
			stacks = Formulas.RhythmStacks(stacks, at, i, rhythm.window, rhythm.maxStacks)
			at = i
		end
		Expect.equal(stacks, rhythm.maxStacks)
		Expect.equal(Formulas.RhythmStacks(stacks, at, at + rhythm.window + 0.1, rhythm.window, rhythm.maxStacks), 0)
		Expect.equal(Formulas.RhythmStacks(0, -math.huge, 0, rhythm.window, rhythm.maxStacks), 0)
	end,
	["exposed, finishing instinct and rhythm add into one bonus"] = function()
		local function bonus(hp: number): number
			return Formulas.HitBonus({
				base = 0,
				proficiency = 0,
				rhythmStacks = 5,
				perStack = 0.02,
				execute = 0.25,
				targetHpFraction = hp,
				executeBelow = 0.3,
				exposure = 0.1,
			})
		end
		Expect.near(bonus(0.5), 0.2, "healthy target")
		Expect.near(bonus(0.29), 0.45, "below 30%")
	end,
	["crit damage adds to the crit multiplier"] = function()
		local input = {
			base = 100,
			attackStat = 0,
			ratio = 0,
			damageType = "physical",
			attackerLevel = 1,
			targetLevel = 1,
			defense = 0,
			tags = {},
			critChance = 1,
			roll = 0.5,
			bonus = 0,
			critDamage = 0.15,
		}
		local amount, crit = Formulas.ResolveDamage(input, Tuning.Combat)
		Expect.truthy(crit)
		Expect.equal(amount, 165)
	end,
	["charges: a second use waits only once both are spent"] = function()
		local readyAt = Formulas.ChargeSpend(0, 100, 20)
		Expect.near(Formulas.ChargeReadyIn(readyAt, 100, 20, 2), 0, "second charge ready")
		Expect.near(Formulas.ChargeReadyIn(readyAt, 100, 20, 1), 20, "single charge waits")
		readyAt = Formulas.ChargeSpend(readyAt, 100, 20)
		Expect.near(Formulas.ChargeReadyIn(readyAt, 100, 20, 2), 20, "both spent")
		Expect.near(Formulas.ChargeReadyIn(readyAt, 125, 20, 2), 0, "one recharged")
	end,
	["proficiency weapon: choice, else equipped, else default"] = function()
		local items = { rusty = { weapon = "sword" }, potion = {} }
		local inventory = { { uid = 1, id = "rusty" }, { uid = 2, id = "potion" } }
		Expect.equal(Formulas.EquippedWeapon({ weapon = 1 }, inventory, items), "sword")
		Expect.equal(Formulas.EquippedWeapon({}, inventory, items), nil)
		Expect.equal(Formulas.ProficiencyFamily("bow", "sword", "sword"), "bow")
		Expect.equal(Formulas.ProficiencyFamily("", nil, "sword"), "sword")
		Expect.equal(Formulas.ProficiencyFamily("", "bow", "sword"), "bow")
	end,
	["harmful status duration shrinks with resistance"] = function()
		Expect.near(Formulas.StatusDuration(4, 100, true, 100), 2, "harmful")
		Expect.near(Formulas.StatusDuration(4, 100, false, 100), 4, "helpful")
	end,
	["discipline capacity formula"] = function()
		Expect.equal(Formulas.DisciplineCapacity(5, 2, 7), 2)
		Expect.equal(Formulas.DisciplineCapacity(29, 2, 7), 6)
	end,
	["arc check"] = function()
		Expect.truthy(Formulas.InArc(0, 0, 0, -1, 0, -5, 8, 90))
		Expect.equal(Formulas.InArc(0, 0, 0, -1, 0, 5, 8, 90), false)
		Expect.equal(Formulas.InArc(0, 0, 0, -1, 0, -9, 8, 90), false)
	end,
	["haste shortens the GCD and casts up to its cap"] = function()
		local gcd = Tuning.Combat.Gcd
		Expect.near(Formulas.Hasted(gcd.Base, 0, gcd.MaxHaste), 2.5, "no haste")
		Expect.near(Formulas.Hasted(gcd.Base, 0.1, gcd.MaxHaste), 2.25, "10%")
		Expect.near(Formulas.Hasted(gcd.Base, 5, gcd.MaxHaste), 2.5 * (1 - gcd.MaxHaste), "capped")
		Expect.near(Formulas.Hasted(1.5, -1, gcd.MaxHaste), 1.5, "never slower")
	end,
}
