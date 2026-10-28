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

export type Role = "Pressure" | "Flanker" | "Opportunist" | "Disruptor" | "Support" | "Reserve"

--[=[ Fixed role order, used to break weight ties. ]=]
Swarm.Roles = table.freeze({ "Pressure", "Flanker", "Opportunist", "Disruptor", "Support", "Reserve" })

export type Profile = {
	slot: SlotKind,
	tokenCost: number,
	roles: { [string]: number },
	--[=[ Skills that can interrupt a player's cast: a Stun-kind effect behind a telegraphed windup. ]=]
	interrupts: { string },
	--[=[ Nil for enemies that never flee. ]=]
	morale: { base: number, fleeBelow: number }?,
	leader: boolean,
	--[=[ Share of max HP that staggers the enemy when taken within Tuning.Swarm.Stagger.Window. ]=]
	poise: number,
}

--[=[ True when a skill can interrupt a player's cast and is telegraphed: an enemy-targeted skill
	with a windup and an effect whose status is of kind Stun. ]=]
function Swarm.Interrupts(skill: any, statuses: { [string]: any }): boolean
	if skill.targets ~= "Enemy" or not skill.windup or skill.windup <= 0 then
		return false
	end
	for _, effect in skill.effects or {} do
		local status = statuses[effect.status]
		if status and status.kind == "Stun" then
			return true
		end
	end
	return false
end

--[=[
	Combat profile of an enemy with defaults filled in. `def` is a Content EnemyDef; `skills` and
	`statuses` are the Content ById tables; defaults come from Tuning.Swarm. `combat.morale = false` means the enemy never flees.
]=]
function Swarm.Profile(
	def: any,
	defaultCost: number,
	defaultMorale: { base: number, fleeBelow: number },
	defaultPoise: number,
	skills: { [string]: any },
	statuses: { [string]: any }
): Profile
	local combat = def.combat or {}
	local interrupts = {}
	for _, skillId in def.skills do
		local skill = skills[skillId]
		if skill and Swarm.Interrupts(skill, statuses) then
			table.insert(interrupts, skillId)
		end
	end
	return {
		slot = combat.slot or "Melee",
		tokenCost = combat.tokenCost or defaultCost,
		roles = combat.roles or { Pressure = 1 },
		interrupts = interrupts,
		morale = if combat.morale == false then nil else combat.morale or defaultMorale,
		leader = combat.leader == true,
		poise = combat.poise or defaultPoise,
	}
end

export type MoraleSettings = {
	--[=[ Morale lost when taking damage equal to max HP. ]=]
	DamageWeight: number,
	--[=[ Morale regained per second, up to the enemy's base, once RegenDelay passes without a loss. ]=]
	Regen: number,
	RegenDelay: number,
	--[=[ Added while a living leader of the team is near, and while rallied. ]=]
	LeaderBonus: number,
	RallyBonus: number,
	--[=[ A fleeing enemy returns only above fleeBelow + Hysteresis. ]=]
	Hysteresis: number,
}

--[=[
	Adds a hit to the poise damage taken within `window` seconds (older damage is dropped first).
	Returns the new total and true when it reaches `poise` x `maxHp`, which also resets it.
]=]
function Swarm.PoiseHit(
	total: number,
	lastAt: number,
	amount: number,
	maxHp: number,
	poise: number,
	window: number,
	now: number
): (number, boolean)
	if now - lastAt > window then
		total = 0
	end
	total += amount
	if total >= poise * maxHp then
		return 0, true
	end
	return total, false
end

--[=[
	Seconds of morale regeneration between `from` and `now` when the last loss was at `lostAt`:
	only time after `lostAt + RegenDelay` counts.
]=]
function Swarm.RegenSeconds(from: number, now: number, lostAt: number, settings: MoraleSettings): number
	return math.max(0, now - math.max(from, lostAt + settings.RegenDelay))
end

--[=[ Morale after taking `amount` damage out of `maxHp`. ]=]
function Swarm.DamageMorale(morale: number, amount: number, maxHp: number, settings: MoraleSettings): number
	return morale - amount / math.max(maxHp, 1) * settings.DamageWeight
end

--[=[
	Advances morale by `dt` seconds of regeneration (time past RegenDelay since the last loss;
	see Swarm.RegenSeconds) and decides whether the enemy flees. Leader and
	rally bonuses count toward the decision but are not stored. Returns morale and fleeing.
]=]
function Swarm.MoraleStep(
	morale: number,
	fleeing: boolean,
	dt: number,
	config: { base: number, fleeBelow: number },
	leaderNear: boolean,
	rallied: boolean,
	settings: MoraleSettings
): (number, boolean)
	morale = math.min(config.base, morale + settings.Regen * dt)
	local effective = morale
		+ (if leaderNear then settings.LeaderBonus else 0)
		+ (if rallied then settings.RallyBonus else 0)
	local threshold = if fleeing then config.fleeBelow + settings.Hysteresis else config.fleeBelow
	return morale, effective < threshold
end

export type RoleCandidate = {
	key: any,
	seq: number,
	roles: { [string]: number },
	canDisrupt: boolean,
	current: Role?,
}

--[=[
	Gives each squad member one role: its highest-weighted role that is still under `caps`
	(missing cap = unlimited), Disruptor only for members that can interrupt. The current role gets
	`stickiness` added to its weight so roles do not flip every update. Falls back to Pressure.
]=]
function Swarm.AssignRoles(
	candidates: { RoleCandidate },
	caps: { [string]: number },
	stickiness: number
): { [any]: Role }
	local ordered = table.clone(candidates)
	table.sort(ordered, function(a, b)
		return a.seq < b.seq
	end)
	local counts: { [string]: number } = {}
	local result: { [any]: Role } = {}
	for _, candidate in ordered do
		local best: Role, bestWeight = "Pressure", -math.huge
		for _, role in Swarm.Roles do
			local weight = candidate.roles[role]
			if not weight or (role == "Disruptor" and not candidate.canDisrupt) then
				continue
			end
			local cap = caps[role]
			if cap and (counts[role] or 0) >= cap then
				continue
			end
			if role == candidate.current then
				weight += stickiness
			end
			if weight > bestWeight then
				best, bestWeight = role :: Role, weight
			end
		end
		counts[best] = (counts[best] or 0) + 1
		result[candidate.key] = best
	end
	return result
end

--[=[ Where a bearing from the target sits against its facing: Front, Side or Rear (45° cones). ]=]
function Swarm.Flank(direction: Vector3, facing: Vector3): "Front" | "Side" | "Rear"
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude < 1e-3 then
		return "Side"
	end
	local dot = direction:Dot(flatFacing.Unit)
	if dot > math.cos(math.rad(45)) then
		return "Front"
	elseif dot < -math.cos(math.rad(45)) then
		return "Rear"
	end
	return "Side"
end

export type PlayerState = {
	casting: boolean,
	locked: boolean,
	--[=[ Seconds until the player's global cooldown is ready. ]=]
	gcdRemaining: number,
	hpRatio: number,
}

export type DirectorSettings = {
	--[=[ Extra attack tokens while the player is casting, locked or deep in a GCD. ]=]
	WindowBonus: number,
	--[=[ A GCD with more than this many seconds left counts as a window. ]=]
	WindowGcd: number,
	--[=[ Below this HP ratio the budget shrinks by MercyPenalty (never below 1). ]=]
	MercyBelow: number,
	MercyPenalty: number,
}

--[=[
	Combat director: reads the player's state and returns the change to the attack budget and
	whether a vulnerability window is open (casting, animation lock or a long GCD).
]=]
function Swarm.Director(state: PlayerState, settings: DirectorSettings): (number, boolean)
	local window = state.casting or state.locked or state.gcdRemaining > settings.WindowGcd
	local bonus = if window then settings.WindowBonus else 0
	if state.hpRatio < settings.MercyBelow then
		bonus -= settings.MercyPenalty
	end
	return bonus, window
end

--[=[ Attack budget for one kind after the director's change; Support is never changed. ]=]
function Swarm.Capacity(base: number, kind: TokenKind, bonus: number): number
	if kind == "Support" then
		return base
	end
	return math.max(1, base + bonus)
end

--[=[
	True when an interrupt started now would land before the player's cast ends: the cast has
	more time left than walking into reach, the windup and `margin`.
]=]
function Swarm.CanInterruptInTime(
	castRemaining: number,
	distance: number,
	reach: number,
	moveSpeed: number,
	windup: number,
	margin: number
): boolean
	local walk = math.max(0, distance - reach) / math.max(moveSpeed, 1)
	return castRemaining > walk + windup + margin
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
	--[=[
		Facing preference: positive weights push toward the target's sides and back (Flanker),
		negative toward its front (Pressure). Cost added is |flank| times the share of the way
		toward the unwanted side.
	]=]
	flank: number?,
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
	--[=[ Flat direction the target faces, for seekers with a `flank` weight. ]=]
	facing: Vector3?,
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
	current slot plus `congestion` for each taken neighbour within one slot width in any ring, plus
	the seeker's facing preference against `facing`. Never gives two seekers the same slot; seekers left over get none. Returns key to index.
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
	local facing = options.facing
	if facing then
		local flatFacing = Vector3.new(facing.X, 0, facing.Z)
		facing = if flatFacing.Magnitude > 1e-3 then flatFacing.Unit else nil
	end

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
				local direction = Swarm.SlotDirection(index, count)
				local offset = center + direction * seeker.radius - seeker.position
				local cost = Vector3.new(offset.X, 0, offset.Z).Magnitude
				local flank = seeker.flank
				if flank and facing then
					-- front is 1 straight ahead of the target and 0 straight behind it.
					local front = (direction:Dot(facing) + 1) / 2
					cost += if flank > 0 then flank * front else -flank * (1 - front)
				end
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
