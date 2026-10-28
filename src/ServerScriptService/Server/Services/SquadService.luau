--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)
local Swarm = require(ReplicatedStorage.Shared.Swarm)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type Member = Types.SquadMember

type TargetState = {
	ledger: Swarm.Ledger,
	members: { [Member]: true },
	nextTactic: number,
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
	local member: Member = {
		entity = entity,
		profile = Swarm.Profile(def, Tuning.Swarm.TokenCost),
		target = nil,
		seq = memberSeq,
		reach = 6,
		slot = nil,
	}
	members[entity] = member
	return member
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
	local ledger = ledgerOf(member)
	if not ledger then
		return false
	end
	local swarm = Tuning.Swarm
	Swarm.Sweep(ledger, now, swarm.TokenTimeout, swarm.WaitStale)
	local cost = member.profile.tokenCost
	return Swarm.Request(ledger, member, kind, cost, math.max(swarm.Budget[kind], cost), 1, now)
end

--[=[ True while the member holds a granted token it has not spent yet. ]=]
function SquadService.HasToken(member: Member): boolean
	local ledger = ledgerOf(member)
	local token = ledger and Swarm.Held(ledger, member)
	return token ~= nil and token.releaseAt == nil
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

-- Re-assigns engagement slots around one target.
local function tactic(target: Entity, state: TargetState)
	local swarm = Tuning.Swarm
	local center = target.root.Position
	local seekers: { Swarm.Seeker } = {}
	local radii: { [Swarm.Ring]: number } = {}
	for member in state.members do
		local ring: Swarm.Ring? = Swarm.RingOf(member.profile.slot)
		if ring and member.entity.alive then
			local outer = member.reach + (if ring == "Melee" then swarm.WaitDistance else 0)
			radii[ring] = math.max(radii[ring] or 0, outer)
			table.insert(seekers, {
				key = member,
				seq = member.seq,
				position = member.entity.root.Position,
				ring = ring,
				radius = member.reach,
				current = member.slot,
			})
		end
	end
	local assigned = Swarm.AssignSlots(seekers, center, {
		counts = swarm.Slots,
		blocked = blockedSlots(center, radii),
		switchCost = swarm.SlotSwitchCost,
		congestion = swarm.SlotCongestion,
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
	CombatService.Died:Connect(forget)
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
