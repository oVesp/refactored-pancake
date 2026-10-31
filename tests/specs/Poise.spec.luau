--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Poise = Loader.load("src/ReplicatedStorage/Shared/Poise")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")

local PARRY = Tuning.Parry
local POOL = Tuning.Swarm.Poise

return {
	["the pool grows with max HP"] = function()
		Expect.equal(Poise.Pool(9, 45, 45), 9, "base level")
		Expect.equal(Poise.Pool(9, 45, 90), 18, "double the HP")
	end,
	["poise damage follows the skill factor"] = function()
		Expect.equal(Poise.Damage(10, nil, POOL.DamageFactor), 10 * POOL.DamageFactor, "default")
		Expect.equal(Poise.Damage(10, 1.5, POOL.DamageFactor), 15, "heavy")
	end,
	["the pool breaks, comes back full and refills after the delay"] = function()
		local poise, broken = Poise.Hit(0, -math.huge, 6, 10, POOL.RefillDelay, 1)
		Expect.equal(poise, 4, "first hit starts from a full pool")
		Expect.equal(broken, false, "not yet")
		poise, broken = Poise.Hit(poise, 1, 6, 10, POOL.RefillDelay, 2)
		Expect.truthy(broken, "second hit breaks")
		Expect.equal(poise, 10, "full after a break")
		poise, broken = Poise.Hit(4, 0, 6, 10, POOL.RefillDelay, POOL.RefillDelay + 1)
		Expect.equal(broken, false, "refilled before the hit")
		Expect.equal(poise, 4, "only the new hit counts")
	end,
	["parry classes default by delivery"] = function()
		Expect.equal(Poise.ParryClass({ delivery = "Melee" }), "Normal", "melee")
		Expect.equal(Poise.ParryClass({ delivery = "Projectile" }), "None", "projectile")
		Expect.equal(Poise.ParryClass({ delivery = "SelfArea" }), "None", "area")
		Expect.equal(Poise.ParryClass({ delivery = "Melee", parry = "Heavy" }), "Heavy", "data wins")
	end,
	["heavy attacks parry early or against a lower-level attacker"] = function()
		local window = 0.25
		Expect.truthy(Poise.Parries("Normal", 0.2, window, 3, 3, PARRY), "normal late in the window")
		Expect.equal(Poise.Parries("Normal", 0.3, window, 3, 3, PARRY), false, "outside the window")
		Expect.equal(Poise.Parries("None", 0, window, 9, 1, PARRY), false, "never")
		Expect.truthy(Poise.Parries("Heavy", window * PARRY.HeavyWindowShare, window, 3, 3, PARRY), "early")
		Expect.equal(Poise.Parries("Heavy", 0.2, window, 3, 3, PARRY), false, "late at the same level")
		Expect.truthy(Poise.Parries("Heavy", 0.2, window, 4, 3, PARRY), "late against a lower level")
	end,
	["parry poise scales with the level gap"] = function()
		Expect.equal(Poise.LevelScale(3, 3, PARRY), 1, "same level")
		Expect.near(Poise.LevelScale(4, 3, PARRY), 1 + PARRY.LevelStep, "one level up")
		Expect.equal(Poise.LevelScale(1, 30, PARRY), PARRY.MinScale, "floor")
		Expect.equal(Poise.LevelScale(30, 1, PARRY), PARRY.MaxScale, "ceiling")
		Expect.equal(Poise.ParryDamage(20, 0.5, 3, 3, PARRY), 10, "share of the pool")
		Expect.equal(Poise.ParryDamage(20, 0, 30, 1, PARRY), 0, "a zero share never breaks")
	end,
	["light hits push a cast back, heavy hits interrupt it"] = function()
		local settings = Tuning.Combat.Poise
		local action, seconds = Poise.CastHit(5, 100, 0, settings)
		Expect.equal(action, "Pushback", "light hit")
		Expect.equal(seconds, settings.Pushback, "pushback length")
		action = Poise.CastHit(settings.CastPoise * 100, 100, 0, settings)
		Expect.equal(action, "Interrupt", "heavy hit")
		action, seconds = Poise.CastHit(5, 100, settings.PushbackMax - 0.1, settings)
		Expect.near(seconds, 0.1, "the last bit of pushback")
		action = Poise.CastHit(5, 100, settings.PushbackMax, settings)
		Expect.equal(action, "None", "pushback is capped per cast")
	end,
}
