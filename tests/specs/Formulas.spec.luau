--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Formulas = Loader.load("src/ReplicatedStorage/Shared/Formulas")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")
local Classes = Loader.load("src/ReplicatedStorage/Content/Classes").ById
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById

local function near(actual: number, expected: number, label: string)
	Expect.truthy(math.abs(actual - expected) < 1e-6, `{label}: {actual} ~= {expected}`)
end

return {
	["level gap is 1 at or below and falls smoothly above"] = function()
		near(Formulas.LevelGapMultiplier(5, 5, 8), 1, "equal")
		near(Formulas.LevelGapMultiplier(5, 1, 8), 1, "lower")
		near(Formulas.LevelGapMultiplier(1, 9, 8), 0.5, "gap 8")
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
	["circle 2 unlocks at line level 6, levels 1-5 cap at circle 1"] = function()
		local magic = Tuning.Magic
		Expect.equal(Formulas.CircleUnlockLevel(2, magic.CircleStep), 6)
		Expect.equal(Formulas.CircleUnlockLevel(3, magic.CircleStep), 12)
		Expect.equal(Formulas.CircleUnlockLevel(10, magic.CircleStep), 54)
		local ceilings = Formulas.CircleCeilings({ { id = "mage", level = 5 } }, Classes, magic)
		Expect.equal(ceilings.arcane, 1)
		ceilings = Formulas.CircleCeilings({ { id = "mage", level = 6 } }, Classes, magic)
		Expect.equal(ceilings.arcane, 2)
	end,
	["mixed incompatible lines lose a circle but keep circle 1"] = function()
		local mixed = { { id = "mage", level = 12 }, { id = "healer", level = 1 } }
		local ceilings = Formulas.CircleCeilings(mixed, Classes, Tuning.Magic)
		Expect.equal(ceilings.arcane, 2)
		Expect.equal(ceilings.divine, 1)
	end,
	["circle 2 spell refused at line level 5"] = function()
		local fakeSkills = table.clone(Skills)
		fakeSkills.test_c2 = { id = "test_c2", source = "Spell", circle = 2, line = "arcane" }
		local fakeClasses = table.clone(Classes)
		local mage = table.clone(Classes.mage)
		mage.spellList = table.clone(mage.spellList)
		table.insert(mage.spellList, "test_c2")
		fakeClasses.mage = mage
		local ok, reason = Formulas.CanLearnSpell(
			{ { id = "mage", level = 5 } },
			{},
			"test_c2",
			fakeClasses,
			fakeSkills,
			Tuning.Magic
		)
		Expect.equal(ok, false)
		Expect.equal(reason, "CircleLocked")
	end,
	["spell picks: one per level, only from own list"] = function()
		local classes = { { id = "mage", level = 2 }, { id = "warrior", level = 1 } }
		local ok, _, payer = Formulas.CanLearnSpell(classes, {}, "spark", Classes, Skills, Tuning.Magic)
		Expect.truthy(ok)
		Expect.equal(payer, "mage")
		local okFull, reasonFull =
			Formulas.CanLearnSpell(classes, { "spark", "firebolt" }, "frost_shard", Classes, Skills, Tuning.Magic)
		Expect.equal(okFull, false)
		Expect.equal(reasonFull, "NoPick")
		local okOther, reasonOther = Formulas.CanLearnSpell(classes, {}, "mend", Classes, Skills, Tuning.Magic)
		Expect.equal(okOther, false)
		Expect.equal(reasonOther, "NotOnClassList")
	end,
	["training needs an unspent level and respects the class cap"] = function()
		Expect.truthy(Formulas.CanTrain({}, "warrior", Classes, 1))
		local ok, reason = Formulas.CanTrain({ { id = "warrior", level = 1 } }, "mage", Classes, 1)
		Expect.equal(ok, false)
		Expect.equal(reason, "NoUnspentLevel")
		local okCap, reasonCap = Formulas.CanTrain({ { id = "warrior", level = 15 } }, "warrior", Classes, 20)
		Expect.equal(okCap, false)
		Expect.equal(reasonCap, "ClassCapped")
	end,
	["each M0.5 template reaches 5 levels"] = function()
		local templates = {
			{ warrior = 5 },
			{ warrior = 3, mage = 2 },
			{ mage = 2, healer = 2, warrior = 1 },
			{ healer = 3, mage = 1, warrior = 1 },
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
		local granted = Formulas.GrantedSkills({ { id = "warrior", level = 2 }, { id = "mage", level = 1 } }, Classes)
		Expect.equal(table.concat(granted, ","), "cleave,hardy,arcane_line")
	end,
	["stats combine growth, modifiers and percentages"] = function()
		local stats, extras = Formulas.ComputeStats({
			base = Tuning.Base.Stats,
			classes = { { id = "warrior", level = 2 } },
			classDefs = Classes,
			modifiers = { { MaxHpPct = 0.1, PhysDef = 5 }, { MoveSpeedPct = 0.4 } },
		})
		Expect.equal(stats.MaxHp, 154)
		Expect.equal(stats.PhysDef, 21)
		near(extras.MoveSpeedPct, 0.4, "move")
		local weakened = Formulas.ComputeStats({
			base = Tuning.Base.Stats,
			classes = {},
			classDefs = Classes,
			modifiers = { { AllStatsPct = -0.1 } },
		})
		Expect.equal(weakened.MaxHp, 90)
	end,
	["harmful status duration shrinks with resistance"] = function()
		near(Formulas.StatusDuration(4, 100, true, 100), 2, "harmful")
		near(Formulas.StatusDuration(4, 100, false, 100), 4, "helpful")
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
		near(Formulas.Hasted(gcd.Base, 0, gcd.MaxHaste), 2.5, "no haste")
		near(Formulas.Hasted(gcd.Base, 0.1, gcd.MaxHaste), 2.25, "10%")
		near(Formulas.Hasted(gcd.Base, 5, gcd.MaxHaste), 2.5 * (1 - gcd.MaxHaste), "capped")
		near(Formulas.Hasted(1.5, -1, gcd.MaxHaste), 1.5, "never slower")
	end,
}
