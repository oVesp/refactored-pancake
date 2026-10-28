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

--[=[ The holder's token, if any. ]=]
function Swarm.Held(ledger: Ledger, holder: any): Token?
	return ledger.tokens[holder]
end

return Swarm
