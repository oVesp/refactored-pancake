--!strict

local Vector3 = require("@lune/roblox").Vector3

local Expect = require("../Expect")
local Loader = require("../Loader")

local Swarm = Loader.load("src/ReplicatedStorage/Shared/Swarm")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")
local Enemies = Loader.load("src/ReplicatedStorage/Content/Enemies").ById
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById

local TIMEOUT = 4
local STALE = 0.75

local function request(
	ledger: any,
	holder: string,
	kind: string,
	now: number,
	cost: number?,
	priority: number?
): boolean
	Swarm.Sweep(ledger, now, TIMEOUT, STALE)
	return Swarm.Request(ledger, holder, kind, cost or 1, 2, priority or 1, now)
end

local OPTIONS = { counts = { Melee = 6, Ranged = 8 }, switchCost = 4, congestion = 3 }
local CENTER = Vector3.new(0, 0, 0)

local function seeker(key: string, seq: number, x: number, z: number, ring: string?, current: number?): any
	return {
		key = key,
		seq = seq,
		position = Vector3.new(x, 0, z),
		ring = ring or "Melee",
		radius = if ring == "Ranged" then 20 else 5,
		current = current,
	}
end

local function crowd(): { any }
	return {
		seeker("a", 1, 10, 0),
		seeker("b", 2, 9, 2),
		seeker("c", 3, -8, 1),
		seeker("d", 4, 0, 10),
		seeker("e", 5, 0, -12),
		seeker("archer", 6, 25, 3, "Ranged"),
	}
end

return {
	["slots are never shared"] = function()
		local result = Swarm.AssignSlots(crowd(), CENTER, OPTIONS)
		local seen: { [string]: string } = {}
		for _, s in crowd() do
			local index = result[s.key]
			Expect.truthy(index, `{s.key} has a slot`)
			local id = `{s.ring}{index}`
			Expect.equal(seen[id], nil, `{s.key} shares {id}`)
			seen[id] = s.key
		end
	end,
	["nearby enemies spread instead of stacking"] = function()
		local result = Swarm.AssignSlots({ seeker("a", 1, 10, 0), seeker("b", 2, 10, 0.5) }, CENTER, OPTIONS)
		Expect.equal(result.a, 1, "a takes the slot facing it")
		Expect.truthy(result.b == 2 or result.b == 6, `b takes a neighbour, got {result.b}`)
	end,
	["assignment is stable when nobody moves far"] = function()
		local first = Swarm.AssignSlots(crowd(), CENTER, OPTIONS)
		local again = crowd()
		for _, s in again do
			s.current = first[s.key]
			-- Drift a little toward the next slot.
			s.position += Vector3.new(0.5, 0, 0.8)
		end
		local second = Swarm.AssignSlots(again, CENTER, OPTIONS)
		for _, s in again do
			Expect.equal(second[s.key], first[s.key], `{s.key} kept its slot`)
		end
	end,
	["blocked slots are skipped and extra seekers get none"] = function()
		local seekers = {}
		for i = 1, 8 do
			table.insert(seekers, seeker(`m{i}`, i, 10, i))
		end
		local options = table.clone(OPTIONS)
		options.blocked = { Melee = { [1] = true, [2] = true } }
		local result = Swarm.AssignSlots(seekers, CENTER, options)
		local count = 0
		for _, index in result do
			Expect.truthy(index ~= 1 and index ~= 2, "blocked slot used")
			count += 1
		end
		Expect.equal(count, 4, "four open melee slots")
	end,
	["separation pushes away from close allies only"] = function()
		local push = Swarm.Separation(Vector3.new(0, 0, 0), { Vector3.new(2, 0, 0), Vector3.new(0, 0, 10) }, 4)
		Expect.truthy(push.X < -0.4 and math.abs(push.Z) < 1e-6, "pushed away on X only")
		local none = Swarm.Separation(Vector3.new(0, 0, 0), { Vector3.new(5, 0, 0) }, 4)
		Expect.equal(none.Magnitude, 0, "far ally")
	end,
	["grants melee tokens up to the budget"] = function()
		local ledger = Swarm.NewLedger()
		Expect.truthy(request(ledger, "a", "Melee", 0), "a")
		Expect.truthy(request(ledger, "b", "Melee", 0), "b")
		Expect.equal(request(ledger, "c", "Melee", 0), false, "c over budget")
		Expect.truthy(request(ledger, "d", "Ranged", 0), "ranged has its own budget")
		Expect.equal(Swarm.Used(ledger, "Melee"), 2, "used")
	end,
	["a token returns after its recovery hold and goes to the longest waiter"] = function()
		local ledger = Swarm.NewLedger()
		request(ledger, "a", "Melee", 0)
		request(ledger, "b", "Melee", 0)
		Expect.equal(request(ledger, "c", "Melee", 0.1), false, "c waits")
		Swarm.Commit(ledger, "a", 1.5)
		Expect.equal(request(ledger, "a", "Melee", 1), false, "holder in recovery is refused")
		Expect.equal(request(ledger, "c", "Melee", 1.2), false, "still held during the hold")
		-- After the hold the old holder asks first, but c has waited longer.
		Expect.equal(request(ledger, "a", "Melee", 1.6), false, "a goes to the back")
		Expect.truthy(request(ledger, "c", "Melee", 1.6), "c is next")
	end,
	["an unused grant times out"] = function()
		local ledger = Swarm.NewLedger()
		request(ledger, "a", "Melee", 0)
		request(ledger, "b", "Melee", 0)
		Expect.truthy(request(ledger, "a", "Melee", 1), "keeps an unused grant")
		Expect.equal(request(ledger, "c", "Melee", 3.9), false, "before timeout")
		Expect.truthy(request(ledger, "c", "Melee", 4.1), "after timeout")
	end,
	["dropping a holder frees its token at once"] = function()
		local ledger = Swarm.NewLedger()
		request(ledger, "a", "Melee", 0)
		request(ledger, "b", "Melee", 0)
		Swarm.Commit(ledger, "a", 10)
		Swarm.Drop(ledger, "a")
		Expect.equal(Swarm.Held(ledger, "a"), nil, "dropped")
		Expect.truthy(request(ledger, "c", "Melee", 0.5), "c takes the freed token")
	end,
	["stale waiters lose their place"] = function()
		local ledger = Swarm.NewLedger()
		request(ledger, "a", "Melee", 0)
		request(ledger, "b", "Melee", 0)
		request(ledger, "c", "Melee", 0)
		Swarm.Drop(ledger, "a")
		-- c stopped asking; d may take the token once c is stale.
		Expect.equal(request(ledger, "d", "Melee", 0.5), false, "c still queued")
		Expect.truthy(request(ledger, "d", "Melee", 1), "c went stale")
	end,
	["a large enemy uses more of the budget"] = function()
		local ledger = Swarm.NewLedger()
		Expect.truthy(request(ledger, "boss", "Melee", 0, 2), "boss")
		Expect.equal(request(ledger, "a", "Melee", 0), false, "boss fills the melee budget")
	end,
	["lower priority waits behind everyone"] = function()
		local ledger = Swarm.NewLedger()
		request(ledger, "a", "Melee", 0)
		request(ledger, "b", "Melee", 0)
		request(ledger, "reserve", "Melee", 0, 1, 0)
		request(ledger, "late", "Melee", 0.5)
		Swarm.Drop(ledger, "a")
		Expect.equal(request(ledger, "reserve", "Melee", 0.6, 1, 0), false, "reserve yields")
		Expect.truthy(request(ledger, "late", "Melee", 0.6), "late goes first")
	end,
	["two teams on one target share its budget"] = function()
		local ledger = Swarm.NewLedger()
		local goblin, skeleton, other = { team = "Goblins" }, { team = "Undead" }, { team = "Undead" }
		Swarm.Request(ledger, goblin, "Melee", 1, 2, 1, 0)
		Swarm.Request(ledger, skeleton, "Melee", 1, 2, 1, 0)
		Expect.equal(Swarm.Request(ledger, other, "Melee", 1, 2, 1, 0), false, "shared budget")
	end,
	["skills map to budgets"] = function()
		Expect.equal(Swarm.TokenKind(Skills.goblin_stab), "Melee", "melee")
		Expect.equal(Swarm.TokenKind(Skills.wolf_charge), "Melee", "dash")
		Expect.equal(Swarm.TokenKind(Skills.brute_slam), "Melee", "self area")
		Expect.equal(Swarm.TokenKind(Skills.sling_shot), "Ranged", "projectile")
		Expect.equal(Swarm.TokenKind(Skills.shaman_heal), "Support", "heal")
		Expect.equal(Swarm.TokenKind(Skills.captain_rally), "Support", "rally")
	end,
	["every enemy resolves a combat profile"] = function()
		for id, def in Enemies do
			local profile = Swarm.Profile(def, Tuning.Swarm.TokenCost)
			Expect.truthy(profile.tokenCost >= 1, `{id} token cost`)
			Expect.truthy(Tuning.Swarm.Budget[profile.slot] or profile.slot == "None", `{id} slot`)
		end
		Expect.equal(Swarm.Profile(Enemies.goblin_chieftain, 1).tokenCost, 2, "chieftain is large")
		Expect.equal(Swarm.Profile(Enemies.training_dummy, 1).slot, "None", "dummy")
	end,
}
