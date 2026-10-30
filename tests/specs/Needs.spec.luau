--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Needs = Loader.load("src/ReplicatedStorage/Shared/Needs")
local Formulas = Loader.load("src/ReplicatedStorage/Shared/Formulas")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")
local Config = Tuning.Needs

-- Regen step of a player with every pool at 10 of 100, out of combat, under `regenScale`.
local function regen(regenScale: number): (number, number, number)
	local hp, mp, stamina = Formulas.Regen({
		hp = 10,
		maxHp = 100,
		mp = 10,
		maxMp = 100,
		stamina = 10,
		maxStamina = 100,
		regenScale = regenScale,
		mpRegenBonus = 0,
		staminaRegenPct = 0,
		guarding = false,
		secondsSinceCombat = math.huge,
	}, Tuning.Base, 1)
	return hp, mp, stamina
end

return {
	["needs empty in 40 and 25 minutes and never go below 0"] = function()
		Expect.near(Needs.Decay(Config.Max, "Hunger", 40 * 60, Config), 0, "hunger")
		Expect.near(Needs.Decay(Config.Max, "Thirst", 25 * 60, Config), 0, "thirst")
		Expect.near(Needs.Decay(Config.Max, "Hunger", 20 * 60, Config), 50, "hunger half")
		Expect.near(Needs.Decay(1, "Thirst", 9999, Config), 0, "floor")
	end,
	["restore clamps to the range"] = function()
		Expect.near(Needs.Restore(90, 35, Config), Config.Max, "cap")
		Expect.near(Needs.Restore(10, -50, Config), 0, "floor")
	end,
	["regen scale drops below the threshold and stops when empty"] = function()
		Expect.near(Needs.RegenScale(30, Config), 1, "fed")
		Expect.near(Needs.RegenScale(20, Config), Config.LowRegenScale, "low")
		Expect.near(Needs.RegenScale(0, Config), 0, "empty")
		Expect.near(
			Needs.CombinedRegenScale({ Hunger = 20, Thirst = 20 }, Config),
			Config.LowRegenScale ^ 2,
			"both low"
		)
	end,
	["drain counts empty needs and never takes HP below the floor"] = function()
		Expect.near(Needs.DrainRate({ Hunger = 50, Thirst = 50 }, Config), 0, "fed")
		Expect.near(Needs.DrainRate({ Hunger = 0, Thirst = 0 }, Config), 2 * Config.StarvingHpPerSecond, "both empty")
		Expect.near(Needs.DrainHp(10, 3, Config), 7, "drain")
		Expect.near(Needs.DrainHp(2, 5, Config), Config.FloorHp, "floor")
		Expect.near(Needs.DrainHp(Config.FloorHp, 5, Config), Config.FloorHp, "at floor")
	end,
	["low needs slow HP and MP regen but never Stamina"] = function()
		local fedHp, fedMp, fedStamina = regen(Needs.CombinedRegenScale({ Hunger = 100, Thirst = 100 }, Config))
		local base = Tuning.Base
		Expect.near(fedHp, 10 + base.HpRegenOutOfCombat, "fed HP")
		Expect.near(fedMp, 10 + base.MpRegen, "fed MP")
		Expect.near(fedStamina, 10 + base.StaminaRegen, "fed Stamina")

		local low = Config.LowRegenScale
		local hp, mp, stamina = regen(Needs.CombinedRegenScale({ Hunger = 20, Thirst = 100 }, Config))
		Expect.near(hp, 10 + base.HpRegenOutOfCombat * low, "one low HP")
		Expect.near(mp, 10 + base.MpRegen * low, "one low MP")
		Expect.near(stamina, fedStamina, "one low Stamina")

		hp, mp, stamina = regen(Needs.CombinedRegenScale({ Hunger = 20, Thirst = 20 }, Config))
		Expect.near(hp, 10 + base.HpRegenOutOfCombat * low * low, "both low HP")
		Expect.near(mp, 10 + base.MpRegen * low * low, "both low MP")
		Expect.near(stamina, fedStamina, "both low Stamina")
	end,
	["an empty need stops HP and MP regen but never Stamina"] = function()
		for _, values in { { Hunger = 0, Thirst = 100 }, { Hunger = 100, Thirst = 0 }, { Hunger = 0, Thirst = 20 } } do
			local hp, mp, stamina = regen(Needs.CombinedRegenScale(values, Config))
			Expect.near(hp, 10, "HP")
			Expect.near(mp, 10, "MP")
			Expect.near(stamina, 10 + Tuning.Base.StaminaRegen, "Stamina")
		end
	end,
	["starvation carries fractions and applies whole HP"] = function()
		local rate = Config.StarvingHpPerSecond
		Expect.near(rate, 0.5, "this test assumes 0.5 HP per second")
		local owed, hp = Needs.Starve(0, 50, rate, 1, false, Config)
		Expect.near(owed, 0.5, "half owed")
		Expect.equal(hp, nil, "no HP yet")
		owed, hp = Needs.Starve(owed, 50, rate, 1, false, Config)
		Expect.near(owed, 0, "paid")
		Expect.equal(hp, 49, "one HP")
		owed, hp = Needs.Starve(0.25, 50, 2 * rate, 2.5, false, Config)
		Expect.near(owed, 0.75, "two empty needs keep the fraction")
		Expect.equal(hp, 48, "two whole HP")
	end,
	["starvation owes nothing when fed, in god mode or at the floor"] = function()
		local rate = Config.StarvingHpPerSecond
		for label, case in
			{
				fed = { 0, 50, false },
				god = { rate, 50, true },
				floor = { rate, Config.FloorHp, false },
				belowFloor = { rate, 0.5, false },
			}
		do
			local owed, hp = Needs.Starve(0.9, case[2], case[1], 10, case[3], Config)
			Expect.equal(owed, 0, `{label} owed`)
			Expect.equal(hp, nil, `{label} HP`)
		end
	end,
	["a starving player settles on 1 HP and stays there, without regen"] = function()
		Expect.equal(Config.FloorHp, 1, "floor")
		local values = { Hunger = 0, Thirst = 0 }
		local rate = Needs.DrainRate(values, Config)
		local scale = Needs.CombinedRegenScale(values, Config)
		local hp, owed = 30.0, 0.0
		local dt = Config.TickInterval
		for _ = 1, math.ceil(120 / dt) do
			hp = Formulas.Regen({
				hp = hp,
				maxHp = 100,
				mp = 0,
				maxMp = 100,
				stamina = 100,
				maxStamina = 100,
				regenScale = scale,
				mpRegenBonus = 0,
				staminaRegenPct = 0,
				guarding = false,
				secondsSinceCombat = math.huge,
			}, Tuning.Base, dt)
			local drained
			owed, drained = Needs.Starve(owed, hp, rate, dt, false, Config)
			hp = drained or hp
			Expect.truthy(hp >= Config.FloorHp, "never under the floor")
		end
		Expect.equal(hp, Config.FloorHp, "at the floor")
		Expect.equal(owed, 0, "nothing owed at the floor")
	end,
}
