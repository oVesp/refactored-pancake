--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Needs = Loader.load("src/ReplicatedStorage/Shared/Needs")
local Config = Loader.load("src/ReplicatedStorage/Content/Tuning").Needs

local function near(actual: number, expected: number, label: string)
	Expect.truthy(math.abs(actual - expected) < 1e-6, `{label}: {actual} ~= {expected}`)
end

return {
	["needs empty in 40 and 25 minutes and never go below 0"] = function()
		near(Needs.Decay(Config.Max, "Hunger", 40 * 60, Config), 0, "hunger")
		near(Needs.Decay(Config.Max, "Thirst", 25 * 60, Config), 0, "thirst")
		near(Needs.Decay(Config.Max, "Hunger", 20 * 60, Config), 50, "hunger half")
		near(Needs.Decay(1, "Thirst", 9999, Config), 0, "floor")
	end,
	["restore clamps to the range"] = function()
		near(Needs.Restore(90, 35, Config), Config.Max, "cap")
		near(Needs.Restore(10, -50, Config), 0, "floor")
	end,
	["regen scale drops below the threshold and stops when empty"] = function()
		near(Needs.RegenScale(30, Config), 1, "fed")
		near(Needs.RegenScale(20, Config), Config.LowRegenScale, "low")
		near(Needs.RegenScale(0, Config), 0, "empty")
		near(Needs.CombinedRegenScale({ Hunger = 20, Thirst = 20 }, Config), Config.LowRegenScale ^ 2, "both low")
	end,
	["drain counts empty needs and never takes HP below the floor"] = function()
		near(Needs.DrainRate({ Hunger = 50, Thirst = 50 }, Config), 0, "fed")
		near(Needs.DrainRate({ Hunger = 0, Thirst = 0 }, Config), 2 * Config.StarvingHpPerSecond, "both empty")
		near(Needs.DrainHp(10, 3, Config), 7, "drain")
		near(Needs.DrainHp(2, 5, Config), Config.FloorHp, "floor")
		near(Needs.DrainHp(Config.FloorHp, 5, Config), Config.FloorHp, "at floor")
	end,
}
