--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Swarm = require(ReplicatedStorage.Shared.Swarm)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type Member = Types.SquadMember

type TargetState = {
	ledger: Swarm.Ledger,
	members: { [Member]: true },
}

local CombatService: any
local EntityService: any
local StatusService: any

local members: { [Entity]: Member } = {}
local targets: { [Entity]: TargetState } = {}

--[=[
	Group combat coordinator (docs/systems/ai-and-spawning.md, Group combat). Enemies attacking
	the same player share that player's attack budget across teams; AIService asks for a token
	before every attack and waits in position without one.
]=]
local SquadService = {}

--[=[ Creates the squad record for an enemy; AIService keeps it on the brain. ]=]
function SquadService.NewMember(entity: Entity, def: any): Member
	local member: Member = {
		entity = entity,
		profile = Swarm.Profile(def, Tuning.Swarm.TokenCost),
		target = nil,
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
		state = { ledger = Swarm.NewLedger(), members = {} }
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
	EntityService.Removing:Connect(forget)
	StatusService.Interrupted:Connect(function(entity: Entity)
		local member = members[entity]
		if member then
			SquadService.DropToken(member)
		end
	end)
end

return SquadService
