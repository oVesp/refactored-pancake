--!strict

local Vector3 = require("@lune/roblox").Vector3

local Expect = require("../Expect")
local Loader = require("../Loader")

local Targeting = Loader.load("src/ReplicatedStorage/Shared/Targeting")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")

local function options(current: string?): any
	local t = Tuning.Targeting
	return {
		eye = Vector3.new(0, 5, 10),
		forward = Vector3.new(0, 0, -1),
		from = Vector3.new(0, 0, 0),
		range = t.Range,
		coneDegrees = t.ConeDegrees,
		angleWeight = t.AngleWeight,
		stickiness = t.Stickiness,
		current = current,
	}
end

local function at(key: string, x: number, z: number): any
	return { key = key, position = Vector3.new(x, 0, z) }
end

return {
	["picks the enemy nearest the screen centre"] = function()
		local pick = Targeting.Pick({ at("side", 12, -10), at("centre", 0, -20) }, options())
		Expect.equal(pick, "centre", "pick")
	end,
	["ignores enemies behind, outside the cone or out of range"] = function()
		local pick = Targeting.Pick({ at("behind", 0, 30), at("wide", 40, 0), at("far", 0, -200) }, options())
		Expect.equal(pick, nil, "pick")
	end,
	["keeps the current target in a crowd unless another is clearly better"] = function()
		local crowd = { at("a", 0, -20), at("b", 2, -20) }
		Expect.equal(Targeting.Pick(crowd, options("b")), "b", "sticky")
		local clearlyBetter = { at("a", 0, -20), at("b", 18, -20) }
		Expect.equal(Targeting.Pick(clearlyBetter, options("b")), "a", "switch")
	end,
	["cycling walks the ranking and releases after the last"] = function()
		local list = { at("a", 0, -20), at("b", 6, -20) }
		local first = Targeting.Next(list, options(), nil)
		Expect.equal(first, "a", "first")
		Expect.equal(Targeting.Next(list, options(), first), "b", "second")
		Expect.equal(Targeting.Next(list, options(), "b"), nil, "release")
	end,
	["flat angle ignores height"] = function()
		local angle = Targeting.FlatAngle(Vector3.new(0, -5, -1), Vector3.new(1, 0, 0))
		Expect.truthy(math.abs(angle - 90) < 1e-6, `angle {angle}`)
	end,
}
