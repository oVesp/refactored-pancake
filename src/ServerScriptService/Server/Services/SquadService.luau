--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)
local Skills = require(ReplicatedStorage.Content.Skills)
local Statuses = require(ReplicatedStorage.Content.Statuses)
local Swarm = require(ReplicatedStorage.Shared.Swarm)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type Member = Types.SquadMember

type TargetState = {
	ledger: Swarm.Ledger,
	members: { [Member]: true },
	nextTactic: number,
	--[=[ Director's change to the attack budget and whether a window is open, per update. ]=]
	bonus: number,
	window: boolean,
	--[=[ os.clock() when any enemy may try to interrupt this player again. ]=]
	nextDisruptAt: number,
}

local log = Logger.new("SquadService")

local CombatService: any
local EntityService: any
local StatusService: any

local members: { [Entity]: Member } = {}
local targets: { [Entity]: TargetState } = {}
local memberSeq = 0
local random = Random.new()
local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Exclude

--[=[
	Group combat coordinator (docs/systems/ai-and-spawning.md, Group combat). Enemies attacking
	the same player share that player's attack budget across teams; AIService asks for a token
	before every attack and waits in position without one. A staggered tactical update spreads
	each target's attackers over engagement slots.
]=]
local SquadService = {}

--[=[ Creates the squad record for an enemy; AIService keeps it on the brain. ]=]
function SquadService.NewMember(entity: Entity, def: any): Member
	memberSeq += 1
	local profile = Swarm.Profile(
		def,
		Tuning.Swarm.TokenCost,
		Tuning.Swarm.Morale.Default,
		Tuning.Swarm.Stagger.DefaultPoise,
		Skills.ById,
		Statuses.ById
	)
	local member: Member = {
		entity = entity,
		profile = profile,
		target = nil,
		seq = memberSeq,
		reach = 6,
		slot = nil,
		role = "Pressure",
		morale = if profile.morale then profile.morale.base else 0,
		fleeing = false,
		moraleAt = os.clock(),
	}
	members[entity] = member
	return member
end

--[=[ Nearest living leader of the member's team within Morale.LeaderRadius, other than itself. ]=]
function SquadService.LeaderOf(member: Member): Entity?
	local position = member.entity.root.Position
	local best, bestDistance = nil, Tuning.Swarm.Morale.LeaderRadius
	for entity, other in members do
		if other ~= member and other.profile.leader and entity.alive and entity.team == member.entity.team then
			local distance = (entity.root.Position - position).Magnitude
			if distance <= bestDistance then
				best, bestDistance = entity, distance
			end
		end
	end
	return best
end

--[=[
	Updates the member's morale and returns true while it flees. Starting to flee gives back its
	token and slot. Enemies without morale never flee.
]=]
function SquadService.UpdateMorale(member: Member, now: number): boolean
	local config = member.profile.morale
	if not config then
		return false
	end
	local dt = now - member.moraleAt
	member.moraleAt = now
	local wasFleeing = member.fleeing
	member.morale, member.fleeing = Swarm.MoraleStep(
		member.morale,
		member.fleeing,
		dt,
		config,
		SquadService.LeaderOf(member) ~= nil,
		member.entity.statuses.rally ~= nil,
		Tuning.Swarm.Morale
	)
	if member.fleeing and not wasFleeing then
		SquadService.DropToken(member)
		member.slot = nil
	end
	return member.fleeing
end

--[=[ Restores full morale (back home after a reset). ]=]
function SquadService.ResetMorale(member: Member)
	local config = member.profile.morale
	member.morale = if config then config.base else 0
	member.fleeing = false
end

-- Morale lost by everyone of `victim`'s team near it when it dies.
local function moraleOnDeath(victim: Member)
	local settings = Tuning.Swarm.Morale
	local position = victim.entity.root.Position
	for entity, other in members do
		if other ~= victim and other.profile.morale and entity.alive and entity.team == victim.entity.team then
			local distance = (entity.root.Position - position).Magnitude
			if distance <= settings.Radius then
				other.morale -= settings.AllyDeath
			end
			if victim.profile.leader and distance <= settings.LeaderRadius then
				other.morale -= settings.LeaderDeath
			end
		end
	end
end

--[=[ Leaves the current target's squad, giving back any token. ]=]
function SquadService.Leave(member: Member)
	local target = member.target
	if not target then
		return
	end
	member.target = nil
	member.slot = nil
	local state = targets[target]
	if state then
		Swarm.Drop(state.ledger, member)
		state.members[member] = nil
		if next(state.members) == nil then
			targets[target] = nil
		end
	end
end

--[=[ Joins the squad attacking `target`, leaving any other first. ]=]
function SquadService.Join(member: Member, target: Entity)
	if member.target == target then
		return
	end
	SquadService.Leave(member)
	local state = targets[target]
	if not state then
		state = {
			ledger = Swarm.NewLedger(),
			members = {},
			nextTactic = os.clock() + random:NextNumber(0, Tuning.Swarm.TacticInterval / 2),
			bonus = 0,
			window = false,
			nextDisruptAt = 0,
		}
		targets[target] = state
	end
	assert(state, "state")
	state.members[member] = true
	member.target = target
end

local function ledgerOf(member: Member): Swarm.Ledger?
	local target = member.target
	local state = target and targets[target]
	return if state then state.ledger else nil
end

--[=[
	Asks for a token of `kind` against the member's target. Enemies with slot "None" never wait.
	Returns true when the member may attack (or advance to attack) now.
]=]
function SquadService.RequestToken(member: Member, kind: Swarm.TokenKind, now: number): boolean
	if member.profile.slot == "None" then
		return true
	end
	if member.fleeing then
		return false
	end
	local ledger = ledgerOf(member)
	if not ledger then
		return false
	end
	local state = targets[member.target :: Entity]
	local swarm = Tuning.Swarm
	Swarm.Sweep(ledger, now, swarm.TokenTimeout, swarm.WaitStale)
	local cost = member.profile.tokenCost
	local capacity = math.max(Swarm.Capacity(swarm.Budget[kind], kind, state.bonus), cost)
	-- Reserve waits behind everyone; Opportunists jump the queue while a window is open.
	local priority = if member.role == "Reserve"
		then 0
		elseif member.role == "Opportunist" and state.window then 2
		else 1
	return Swarm.Request(ledger, member, kind, cost, capacity, priority, now)
end

--[=[
	True when the member is its squad's Disruptor, its target is casting and nobody has tried to
	interrupt that player within Tuning.Swarm.DisruptCooldown.
]=]
function SquadService.MayDisrupt(member: Member, now: number): boolean
	local target = member.target
	local state = target and targets[target]
	return member.role == "Disruptor"
		and state ~= nil
		and target ~= nil
		and target.casting ~= nil
		and now >= state.nextDisruptAt
end

--[=[ Starts the target's interrupt cooldown; call when the interrupt skill is cast. ]=]
function SquadService.MarkDisrupt(member: Member, now: number)
	local target = member.target
	local state = target and targets[target]
	if state then
		state.nextDisruptAt = now + Tuning.Swarm.DisruptCooldown
	end
end

--[=[ True while the member holds a granted token it has not spent yet. ]=]
function SquadService.HasToken(member: Member): boolean
	local ledger = ledgerOf(member)
	local token = ledger and Swarm.Held(ledger, member)
	return token ~= nil and token.releaseAt == nil
end

--[=[ "Held" (granted, unused), "Spent" (in its recovery hold) or nil, for debugging. ]=]
function SquadService.TokenState(member: Member): string?
	local ledger = ledgerOf(member)
	local token = ledger and Swarm.Held(ledger, member)
	if not token then
		return nil
	end
	return if token.releaseAt then "Spent" else "Held"
end

--[=[ Spends the member's token on an attack; it frees itself at `releaseAt`. ]=]
function SquadService.Commit(member: Member, releaseAt: number)
	local ledger = ledgerOf(member)
	if ledger then
		Swarm.Commit(ledger, member, releaseAt)
	end
end

--[=[ Gives the token back at once (interrupted, staggered, fleeing). ]=]
function SquadService.DropToken(member: Member)
	local ledger = ledgerOf(member)
	if ledger then
		Swarm.Drop(ledger, member)
	end
end

--[=[ Flat direction from the target to the member's engagement slot, if it has one. ]=]
function SquadService.SlotDirection(member: Member): Vector3?
	local ring = Swarm.RingOf(member.profile.slot)
	local slot = member.slot
	if not ring or not slot then
		return nil
	end
	return Swarm.SlotDirection(slot, Tuning.Swarm.Slots[ring])
end

-- Slots whose line from the target runs into a wall within the ring's widest radius.
local function blockedSlots(center: Vector3, radii: { [Swarm.Ring]: number }): { [string]: { [number]: boolean } }
	local blocked: { [string]: { [number]: boolean } } = {}
	for key, radius in radii do
		local ring = key :: Swarm.Ring
		local count = Tuning.Swarm.Slots[ring]
		local set: { [number]: boolean } = {}
		for index = 1, count do
			if workspace:Raycast(center, Swarm.SlotDirection(index, count) * radius, wallParams) then
				set[index] = true
			end
		end
		blocked[ring] = set
	end
	return blocked
end

-- Roles per team: each team on a target is its own squad.
local function assignRoles(state: TargetState)
	local byTeam: { [string]: { Swarm.RoleCandidate } } = {}
	for member in state.members do
		if member.fleeing then
			continue
		end
		local team = member.entity.team
		byTeam[team] = byTeam[team] or {}
		table.insert(byTeam[team], {
			key = member,
			seq = member.seq,
			roles = member.profile.roles,
			canDisrupt = #member.profile.interrupts > 0,
			current = member.role,
		})
	end
	for _, candidates in byTeam do
		local roles = Swarm.AssignRoles(candidates, Tuning.Swarm.RoleCaps, Tuning.Swarm.RoleStickiness)
		for _, candidate in candidates do
			local member = candidate.key :: Member
			member.role = roles[member]
		end
	end
end

-- Director, roles and engagement slots for one target.
local function tactic(target: Entity, state: TargetState)
	local swarm = Tuning.Swarm
	local now = os.clock()
	state.bonus, state.window = Swarm.Director({
		casting = target.casting ~= nil,
		locked = target.lockedUntil > now,
		gcdRemaining = target.gcdReadyAt - now,
		hpRatio = target.hp / math.max(target.stats.MaxHp, 1),
	}, swarm.Director)
	assignRoles(state)

	local center = target.root.Position
	local seekers: { Swarm.Seeker } = {}
	local radii: { [Swarm.Ring]: number } = {}
	for member in state.members do
		local ring: Swarm.Ring? = Swarm.RingOf(member.profile.slot)
		if ring and member.entity.alive and not member.fleeing then
			local outer = member.reach + (if ring == "Melee" then swarm.WaitDistance else 0)
			radii[ring] = math.max(radii[ring] or 0, outer)
			table.insert(seekers, {
				key = member,
				seq = member.seq,
				position = member.entity.root.Position,
				ring = ring,
				radius = member.reach,
				current = member.slot,
				flank = if member.role == "Flanker"
					then swarm.FlankWeight
					elseif member.role == "Pressure" then -swarm.PressureFrontWeight
					else nil,
			})
		end
	end
	local assigned = Swarm.AssignSlots(seekers, center, {
		counts = swarm.Slots,
		blocked = blockedSlots(center, radii),
		switchCost = swarm.SlotSwitchCost,
		congestion = swarm.SlotCongestion,
		facing = target.root.CFrame.LookVector,
	})
	for member in state.members do
		member.slot = assigned[member]
	end
end

local function refreshFilter()
	local exclude: { Instance } = {}
	for model in EntityService.All() do
		table.insert(exclude, model)
	end
	wallParams.FilterDescendantsInstances = exclude
end

local function forget(entity: Entity)
	local member = members[entity]
	if member then
		SquadService.Leave(member)
		members[entity] = nil
	end
	local state = targets[entity]
	if state then
		for other in state.members do
			other.target = nil
			other.slot = nil
		end
		targets[entity] = nil
	end
end

function SquadService.Init(deps: { [string]: any })
	CombatService = deps.CombatService
	EntityService = deps.EntityService
	StatusService = deps.StatusService
end

function SquadService.Start()
	CombatService.Died:Connect(function(victim: Entity)
		local member = members[victim]
		if member then
			moraleOnDeath(member)
		end
		forget(victim)
	end)
	CombatService.Damaged:Connect(function(target: Entity, amount: number)
		local member = members[target]
		if member and member.profile.morale and amount > 0 then
			member.morale = Swarm.DamageMorale(member.morale, amount, target.stats.MaxHp, Tuning.Swarm.Morale)
		end
	end)
	EntityService.Removing:Connect(function(entity: Entity)
		forget(entity)
		task.defer(refreshFilter)
	end)
	EntityService.Added:Connect(refreshFilter)
	StatusService.Interrupted:Connect(function(entity: Entity)
		local member = members[entity]
		if member then
			SquadService.DropToken(member)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Tuning.Swarm.TacticInterval / 4)
			local now = os.clock()
			for target, state in targets do
				if now >= state.nextTactic then
					state.nextTactic = now + Tuning.Swarm.TacticInterval
					local ok, err = pcall(function()
						tactic(target, state)
					end)
					if not ok then
						log:Throttled("tactic", 5, "error", "Tactic error for %s: %s", target.name, tostring(err))
					end
				end
			end
		end
	end)
end

return SquadService
