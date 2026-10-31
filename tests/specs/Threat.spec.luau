--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Threat = Loader.load("src/ReplicatedStorage/Shared/Threat")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")

local function candidate(key: string, threat: number, inReach: boolean?, healing: boolean?): any
	return { key = key, threat = threat, inReach = inReach ~= false, healing = healing == true }
end

return {
	["damage threat follows the skill and source multipliers"] = function()
		Expect.equal(Threat.FromDamage(10, nil, 1), 10, "plain damage")
		Expect.equal(Threat.FromDamage(10, { multiplier = 2 }, 1.5), 30, "skill and source")
		Expect.equal(Threat.Flat({ flat = 40 }, 1.5), 60, "flat threat scales with the source")
		Expect.equal(Threat.Flat(nil, 2), 0, "no flat threat")
	end,
	["statuses multiply the source's threat"] = function()
		local statuses = { stance = { threatMultiplier = 2 }, plain = {} }
		Expect.equal(Threat.SourceMultiplier(1, { stance = true, plain = true }, statuses), 2, "stance")
		Expect.equal(Threat.SourceMultiplier(1.5, {}, statuses), 1.5, "entity multiplier alone")
	end,
	["healing threat splits across the enemies fighting the ally"] = function()
		local heal = Tuning.Threat.HealThreat
		Expect.equal(Threat.HealShare(40, heal, 2), 40 * heal / 2, "split")
		Expect.equal(Threat.HealShare(40, heal, 0), 0, "nobody fights the ally")
	end,
	["the first to engage gets the pull threat"] = function()
		local threat = {}
		Threat.Add(threat, "tank", 5, Tuning.Threat.PullThreat)
		Threat.Add(threat, "dps", 5, Tuning.Threat.PullThreat)
		Expect.equal(threat.tank, 5 + Tuning.Threat.PullThreat, "opening lead")
		Expect.equal(threat.dps, 5, "no lead for later attackers")
	end,
	["threat decays and never goes negative"] = function()
		Expect.near(Threat.Decay(100, 1, 0.05), 95, "one second")
		Expect.equal(Threat.Decay(100, 100, 0.05), 0, "floored")
	end,
	["the holder keeps aggro until the switch ratio"] = function()
		local ratio = Tuning.Threat.SwitchRatio.Melee
		local list = { candidate("tank", 100), candidate("dps", 100 * ratio - 1) }
		Expect.equal(Threat.Choose(list, "tank", ratio), "tank", "below the ratio")
		list[2].threat = 100 * ratio + 1
		Expect.equal(Threat.Choose(list, "tank", ratio), "dps", "above the ratio")
		Expect.equal(Threat.Choose({ candidate("a", 1), candidate("b", 2) }, nil, ratio), "b", "no holder")
		Expect.equal(Threat.Choose({}, nil, ratio), nil, "nobody")
	end,
	["targets in reach beat higher threat out of reach, except healers"] = function()
		local ratio = Tuning.Threat.SwitchRatio.Ranged
		local list = { candidate("archer", 500, false), candidate("tank", 50) }
		Expect.equal(Threat.Choose(list, "archer", ratio), "tank", "proximity")
		list[1].healing = true
		Expect.equal(Threat.Choose(list, "tank", ratio), "archer", "a healer is chased")
		Expect.equal(
			Threat.Choose({ candidate("a", 10, false), candidate("b", 20, false) }, "a", ratio),
			"b",
			"nobody in reach: threat decides"
		)
	end,
}
