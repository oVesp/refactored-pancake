--!strict

--[=[
	Pure group-combat logic (docs/systems/ai-and-spawning.md, Group combat). No requires and no
	Roblox services: callers pass time, content and tuning in, so every function is unit-testable
	under Lune. SquadService owns the live state and calls into this module.
]=]
local Swarm = {}

export type TokenKind = "Melee" | "Ranged" | "Support"
export type SlotKind = "Melee" | "Ranged" | "Support" | "None"

export type Token = {
	kind: TokenKind,
	cost: number,
	grantedAt: number,
	--[=[ Set when the holder starts its attack; the token frees itself at this time. ]=]
	releaseAt: number?,
}

export type Waiter = {
	since: number,
	seen: number,
	priority: number,
	seq: number,
}

--[=[ Attack tokens for one target. Keys are opaque holders (SquadService members). ]=]
export type Ledger = {
	tokens: { [any]: Token },
	--[=[ Queue per kind; a holder may wait in several kinds at once. ]=]
	waiting: { [TokenKind]: { [any]: Waiter } },
	seq: number,
}

export type Profile = {
	slot: SlotKind,
	tokenCost: number,
}

--[=[ Combat profile of an enemy with defaults filled in. `def` is a Content EnemyDef. ]=]
function Swarm.Profile(def: any, defaultCost: number): Profile
	local combat = def.combat or {}
	return {
		slot = combat.slot or "Melee",
		tokenCost = combat.tokenCost or defaultCost,
	}
end

--[=[ Budget a skill draws from: ally skills use Support, close-range deliveries Melee, the rest Ranged. ]=]
function Swarm.TokenKind(skill: any): TokenKind
	if skill.targets == "Ally" then
		return "Support"
	end
	local delivery = skill.delivery
	if delivery == "Melee" or delivery == "Dash" or delivery == "SelfArea" then
		return "Melee"
	end
	return "Ranged"
end

function Swarm.NewLedger(): Ledger
	return { tokens = {}, waiting = { Melee = {}, Ranged = {}, Support = {} }, seq = 0 }
end

--[=[ Budget in use for one kind, counting tokens still in their recovery hold. ]=]
function Swarm.Used(ledger: Ledger, kind: TokenKind): number
	local used = 0
	for _, token in ledger.tokens do
		if token.kind == kind then
			used += token.cost
		end
	end
	return used
end

--[=[
	Frees tokens whose hold ended, grants that were never used within `timeout` seconds, and
	waiters that stopped asking more than `waitStale` seconds ago.
]=]
function Swarm.Sweep(ledger: Ledger, now: number, timeout: number, waitStale: number)
	for holder, token in ledger.tokens do
		local releaseAt = token.releaseAt
		if (releaseAt and releaseAt <= now) or (not releaseAt and token.grantedAt + timeout <= now) then
			ledger.tokens[holder] = nil
		end
	end
	for _, queue in ledger.waiting do
		for holder, waiter in queue do
			if waiter.seen + waitStale < now then
				queue[holder] = nil
			end
		end
	end
end

local function before(a: Waiter, b: Waiter): boolean
	if a.priority ~= b.priority then
		return a.priority > b.priority
	end
	if a.since ~= b.since then
		return a.since < b.since
	end
	return a.seq < b.seq
end

--[=[
	Asks for a token. Holders queue per kind by priority, then by when they started waiting, so
	an enemy that just attacked goes to the back. Only the head of the queue is granted, and only
	while `cost` fits in `capacity`. A holder with an unused grant keeps it; one in its recovery
	hold is refused. Call Sweep first.
]=]
function Swarm.Request(
	ledger: Ledger,
	holder: any,
	kind: TokenKind,
	cost: number,
	capacity: number,
	priority: number,
	now: number
): boolean
	local held = ledger.tokens[holder]
	if held then
		if held.releaseAt then
			return false
		end
		if held.kind == kind then
			return true
		end
		ledger.tokens[holder] = nil
	end

	local queue = ledger.waiting[kind]
	local waiter = queue[holder]
	if not waiter then
		ledger.seq += 1
		waiter = { since = now, seen = now, priority = priority, seq = ledger.seq }
		queue[holder] = waiter
	end
	assert(waiter, "waiter")
	waiter.seen = now
	waiter.priority = priority

	for other, entry in queue do
		if other ~= holder and before(entry, waiter) then
			return false
		end
	end
	if Swarm.Used(ledger, kind) + cost > capacity then
		return false
	end
	for _, other in ledger.waiting do
		other[holder] = nil
	end
	ledger.tokens[holder] = { kind = kind, cost = cost, grantedAt = now }
	return true
end

--[=[ Marks a granted token as spent: it stays taken until `releaseAt`, then frees itself. ]=]
function Swarm.Commit(ledger: Ledger, holder: any, releaseAt: number)
	local token = ledger.tokens[holder]
	if token then
		token.releaseAt = releaseAt
	end
end

--[=[ Removes a holder's token and queue place at once (death, interrupt, leaving the fight). ]=]
function Swarm.Drop(ledger: Ledger, holder: any)
	ledger.tokens[holder] = nil
	for _, queue in ledger.waiting do
		queue[holder] = nil
	end
end

export type Ring = "Melee" | "Ranged"

--[=[ An enemy asking for an engagement slot around its target. ]=]
export type Seeker = {
	key: any,
	--[=[ Stable order for ties (spawn sequence). ]=]
	seq: number,
	position: Vector3,
	ring: Ring,
	--[=[ Distance from the target where this enemy stands. ]=]
	radius: number,
	--[=[ Slot index held since the last assignment, if any. ]=]
	current: number?,
}

export type SlotOptions = {
	--[=[ Slots per ring. ]=]
	counts: { [Ring]: number },
	--[=[ Slot indices per ring that are inside walls. ]=]
	blocked: { [string]: { [number]: boolean } }?,
	--[=[ Extra cost for leaving the current slot, so assignments stay stable. ]=]
	switchCost: number,
	--[=[ Cost per already-taken slot next to this one, in any ring. ]=]
	congestion: number,
}

--[=[ Ring an enemy stands in: melee in close, everyone else out at range. ]=]
function Swarm.RingOf(slot: SlotKind): Ring?
	if slot == "None" then
		return nil
	elseif slot == "Melee" then
		return "Melee"
	end
	return "Ranged"
end

--[=[ Flat unit direction of slot `index` (1-based) out of `count` around the target. ]=]
function Swarm.SlotDirection(index: number, count: number): Vector3
	local angle = (index - 1) / count * math.pi * 2
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function slotAngle(index: number, count: number): number
	return (index - 1) / count * math.pi * 2
end

local function angleBetween(a: number, b: number): number
	local d = math.abs(a - b) % (math.pi * 2)
	return math.min(d, math.pi * 2 - d)
end

--[=[
	Greedy slot assignment around one target at `center`. Repeatedly takes the cheapest
	(seeker, free slot) pair, where cost is the walk to the slot plus `switchCost` for leaving the
	current slot plus `congestion` for each taken neighbour within one slot width in any ring.
	Never gives two seekers the same slot; seekers left over get none. Returns key to index.
]=]
function Swarm.AssignSlots(seekers: { Seeker }, center: Vector3, options: SlotOptions): { [any]: number }
	local ordered = table.clone(seekers)
	table.sort(ordered, function(a, b)
		return a.seq < b.seq
	end)
	local taken: { [Ring]: { [number]: boolean } } = { Melee = {}, Ranged = {} }
	local takenAngles: { { angle: number, width: number } } = {}
	local result: { [any]: number } = {}
	local blocked = options.blocked or {}

	local remaining = #ordered
	while remaining > 0 do
		local bestSeeker: Seeker?, bestIndex, bestCost = nil, 0, math.huge
		for _, seeker in ordered do
			if result[seeker.key] then
				continue
			end
			local count = options.counts[seeker.ring]
			local ringBlocked = blocked[seeker.ring] or {}
			for index = 1, count do
				if taken[seeker.ring][index] or ringBlocked[index] then
					continue
				end
				local point = center + Swarm.SlotDirection(index, count) * seeker.radius
				local offset = point - seeker.position
				local cost = Vector3.new(offset.X, 0, offset.Z).Magnitude
				if seeker.current ~= index then
					cost += options.switchCost
				end
				local angle = slotAngle(index, count)
				for _, other in takenAngles do
					if angleBetween(angle, other.angle) < math.max(other.width, math.pi * 2 / count) - 1e-6 then
						cost += options.congestion
					end
				end
				if cost < bestCost then
					bestSeeker, bestIndex, bestCost = seeker, index, cost
				end
			end
		end
		if not bestSeeker then
			break
		end
		result[bestSeeker.key] = bestIndex
		local count = options.counts[bestSeeker.ring]
		taken[bestSeeker.ring][bestIndex] = true
		table.insert(takenAngles, { angle = slotAngle(bestIndex, count), width = math.pi * 2 / count })
		remaining -= 1
	end
	return result
end

--[=[
	Flat push away from neighbours closer than `radius`, growing as they get closer: the sum of
	unit directions scaled by (radius - distance) / radius. Zero when nobody is that close.
]=]
function Swarm.Separation(position: Vector3, neighbours: { Vector3 }, radius: number): Vector3
	local push = Vector3.new(0, 0, 0)
	for _, other in neighbours do
		local offset = Vector3.new(position.X - other.X, 0, position.Z - other.Z)
		local distance = offset.Magnitude
		if distance < radius then
			local direction = if distance > 1e-3 then offset.Unit else Vector3.new(1, 0, 0)
			push += direction * ((radius - distance) / radius)
		end
	end
	return push
end

--[=[ The holder's token, if any. ]=]
function Swarm.Held(ledger: Ledger, holder: any): Token?
	return ledger.tokens[holder]
end

return Swarm
