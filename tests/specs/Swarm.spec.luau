--!strict

local Vector3 = require("@lune/roblox").Vector3

local Expect = require("../Expect")
local Loader = require("../Loader")

local Swarm = Loader.load("src/ReplicatedStorage/Shared/Swarm")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")
local Enemies = Loader.load("src/ReplicatedStorage/Content/Enemies").ById
local Skills = Loader.load("src/ReplicatedStorage/Content/Skills").ById
local Statuses = Loader.load("src/ReplicatedStorage/Content/Statuses").ById

local function profile(id: string): any
	return Swarm.Profile(
		Enemies[id],
		Tuning.Swarm.TokenCost,
		Tuning.Swarm.Morale.Default,
		Tuning.Swarm.Stagger.DefaultPoise,
		Skills,
		Statuses
	)
end

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
		for id in Enemies do
			local resolved = profile(id)
			Expect.truthy(resolved.tokenCost >= 1, `{id} token cost`)
			Expect.truthy(Tuning.Swarm.Budget[resolved.slot] or resolved.slot == "None", `{id} slot`)
			for role in resolved.roles do
				Expect.truthy(table.find(Swarm.Roles, role), `{id}: unknown role {role}`)
			end
			if resolved.roles.Disruptor then
				Expect.truthy(#resolved.interrupts > 0, `{id}: Disruptor needs a telegraphed stun skill`)
			end
		end
		Expect.equal(profile("goblin_chieftain").tokenCost, 2, "chieftain is large")
		Expect.equal(profile("training_dummy").slot, "None", "dummy")
	end,
	["only telegraphed stuns interrupt"] = function()
		Expect.truthy(Swarm.Interrupts(Skills.brute_slam, Statuses), "brute slam")
		Expect.truthy(Swarm.Interrupts(Skills.wolf_charge, Statuses), "wolf charge")
		Expect.equal(Swarm.Interrupts(Skills.sling_shot, Statuses), false, "sling")
		Expect.equal(Swarm.Interrupts(Skills.poison_snare, Statuses), false, "root is not a stun")
	end,
	["roles respect caps, eligibility and stickiness"] = function()
		local caps = { Disruptor = 1, Flanker = 1 }
		local roles = Swarm.AssignRoles({
			{ key = "a", seq = 1, roles = { Disruptor = 2, Pressure = 1 }, canDisrupt = true },
			{ key = "b", seq = 2, roles = { Disruptor = 2, Pressure = 1 }, canDisrupt = true },
			{ key = "c", seq = 3, roles = { Disruptor = 3 }, canDisrupt = false },
			{ key = "d", seq = 4, roles = { Flanker = 2, Pressure = 1 }, canDisrupt = false },
			{ key = "e", seq = 5, roles = { Flanker = 2, Pressure = 1 }, canDisrupt = false },
		}, caps, 0.5)
		Expect.equal(roles.a, "Disruptor", "a")
		Expect.equal(roles.b, "Pressure", "b: disruptor cap")
		Expect.equal(roles.c, "Pressure", "c cannot interrupt")
		Expect.equal(roles.d, "Flanker", "d")
		Expect.equal(roles.e, "Pressure", "e: flanker cap")
		local sticky = Swarm.AssignRoles({
			{
				key = "x",
				seq = 1,
				roles = { Pressure = 1, Opportunist = 1.2 },
				canDisrupt = false,
				current = "Pressure",
			},
		}, {}, 0.5)
		Expect.equal(sticky.x, "Pressure", "keeps its role within the stickiness")
	end,
	["flank classifies bearings against facing"] = function()
		local facing = Vector3.new(0, 0, -1)
		Expect.equal(Swarm.Flank(Vector3.new(0, 0, -1), facing), "Front", "front")
		Expect.equal(Swarm.Flank(Vector3.new(1, 0, 0), facing), "Side", "side")
		Expect.equal(Swarm.Flank(Vector3.new(0, 0, 1), facing), "Rear", "rear")
	end,
	["flankers take the back, pressure the front"] = function()
		local options = table.clone(OPTIONS)
		options.facing = Vector3.new(1, 0, 0)
		local flanker = seeker("flanker", 1, 0, 6)
		flanker.flank = 20
		local pressure = seeker("pressure", 2, 0, -6)
		pressure.flank = -20
		local result = Swarm.AssignSlots({ flanker, pressure }, CENTER, options)
		local facing = options.facing
		Expect.equal(Swarm.Flank(Swarm.SlotDirection(result.flanker, 6), facing), "Rear", "flanker")
		Expect.equal(Swarm.Flank(Swarm.SlotDirection(result.pressure, 6), facing), "Front", "pressure")
	end,
	["director opens windows and shows mercy"] = function()
		local settings = Tuning.Swarm.Director
		local calm = { casting = false, locked = false, gcdRemaining = 0, hpRatio = 1 }
		local bonus, window = Swarm.Director(calm, settings)
		Expect.equal(bonus, 0, "calm bonus")
		Expect.equal(window, false, "calm window")
		local casting = table.clone(calm)
		casting.casting = true
		bonus, window = Swarm.Director(casting, settings)
		Expect.equal(bonus, settings.WindowBonus, "window bonus")
		Expect.truthy(window, "window")
		local low = table.clone(calm)
		low.hpRatio = 0.1
		bonus = Swarm.Director(low, settings)
		Expect.equal(Swarm.Capacity(2, "Melee", bonus), 1, "mercy")
		Expect.equal(Swarm.Capacity(1, "Ranged", bonus), 1, "never below one")
		Expect.equal(Swarm.Capacity(1, "Support", 5), 1, "support unchanged")
	end,
	["interrupts only start when they can land"] = function()
		Expect.truthy(Swarm.CanInterruptInTime(2.5, 6, 10, 11, 1.2, 0.2), "in reach")
		Expect.equal(Swarm.CanInterruptInTime(1.2, 6, 10, 11, 1.2, 0.2), false, "cast ends first")
		Expect.equal(Swarm.CanInterruptInTime(2.5, 40, 10, 11, 1.2, 0.2), false, "too far")
	end,
	["morale is optional and leaders are marked"] = function()
		Expect.equal(profile("skeleton").morale, nil, "undead never flee")
		Expect.equal(profile("goblin_chieftain").morale, nil, "bosses never flee")
		Expect.truthy(profile("goblin_raider").morale, "goblins have morale")
		Expect.truthy(profile("warband_captain").leader, "captain leads")
		Expect.equal(profile("goblin_raider").leader, false, "raider does not lead")
	end,
	["enemies flee below their threshold and come back with margin"] = function()
		local settings = Tuning.Swarm.Morale
		local config = { base = 100, fleeBelow = 30 }
		local morale = Swarm.DamageMorale(100, 100, 100, settings)
		Expect.equal(morale, 100 - settings.DamageWeight, "full-HP hit")
		local fleeing
		morale, fleeing = Swarm.MoraleStep(20, false, 0, config, false, false, settings)
		Expect.truthy(fleeing, "flees below threshold")
		morale, fleeing = Swarm.MoraleStep(40, true, 0, config, false, false, settings)
		Expect.truthy(fleeing, "keeps fleeing inside the hysteresis band")
		morale, fleeing = Swarm.MoraleStep(60, true, 0, config, false, false, settings)
		Expect.equal(fleeing, false, "returns above the band")
		morale, fleeing = Swarm.MoraleStep(20, false, 0, config, true, false, settings)
		Expect.equal(fleeing, false, "a leader nearby holds the line")
		morale = Swarm.MoraleStep(99, false, 10, config, false, false, settings)
		Expect.equal(morale, 100, "regen caps at base")
	end,
	["poise breaks on enough damage inside the window"] = function()
		local total, staggered = Swarm.PoiseHit(0, 0, 10, 100, 0.2, 3, 1)
		Expect.equal(staggered, false, "one light hit")
		total, staggered = Swarm.PoiseHit(total, 1, 10, 100, 0.2, 3, 2)
		Expect.truthy(staggered, "two hits inside the window")
		Expect.equal(total, 0, "reset after a stagger")
		total, staggered = Swarm.PoiseHit(15, 0, 10, 100, 0.2, 3, 5)
		Expect.equal(staggered, false, "old damage dropped")
		Expect.equal(total, 10, "only the new hit counts")
		Expect.truthy(profile("goblin_chieftain").poise > profile("goblin_raider").poise, "boss is sturdier")
	end,
}
