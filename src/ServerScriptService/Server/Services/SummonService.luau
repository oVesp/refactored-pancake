--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)
local Relations = require(ReplicatedStorage.Shared.Relations)
local SummonFamilies = require(ReplicatedStorage.Content.Summons)
local Summons = require(ReplicatedStorage.Shared.Summons)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

type Active = {
	entity: Entity,
	expiresAt: number,
}

local log = Logger.new("SummonService")

local AIService: any
local CombatService: any
local EntityService: any
local SpawnService: any

local active: { [Player]: { Active } } = {}
-- Last valid choice per player and family, for casts that name none. Session only.
local chosen: { [Player]: { [string]: string } } = {}

--[=[
	Summoned allies (docs/systems/ai-and-spawning.md, Summons): validates a caster's choice, spawns
	NPCs on the caster's faction that follow them through the FollowLeader task and join their fights,
	and removes them at the end of their duration, or when the caster dies or leaves.
]=]
local SummonService = {}

--[=[
	Validates the id a cast asks for (`requested`, nil for the remembered one) against the player's
	discoveries and remembers it. Returns false when the player may not raise it.
]=]
function SummonService.Choose(player: Player, profile: any, familyId: string, requested: string?): boolean
	local family = SummonFamilies.ById[familyId]
	if not family then
		return false
	end
	local choices = chosen[player] or {}
	local id = Summons.Choose(family, profile.discoveries, requested, choices[familyId])
	if not id then
		return false
	end
	choices[familyId] = id
	chosen[player] = choices
	return true
end

local function reindex(player: Player)
	local owner = EntityService.ForPlayer(player)
	local list: { Active } = active[player] or {}
	for index, summon in list do
		AIService.SetLeader(summon.entity, owner, index)
	end
end

local function dismiss(player: Player)
	local list: { Active } = active[player] or {}
	for _, summon in table.clone(list) do
		SpawnService.Despawn(summon.entity)
	end
	active[player] = nil
end

--[=[ Spawns the caster's remembered choice of a family, replacing their oldest summon at the cap. ]=]
function SummonService.Cast(caster: Entity, familyId: string)
	local player = caster.player
	local family = SummonFamilies.ById[familyId]
	local choices = player and chosen[player]
	local id = choices and choices[familyId]
	if not player or not family or not id then
		return
	end
	local settings = Tuning.Summons
	local list = active[player] or {}
	active[player] = list
	while #list >= math.min(family.cap, settings.MaxPerCaster) do
		local oldest = table.remove(list, 1) :: Active
		SpawnService.Despawn(oldest.entity)
	end
	local spot = caster.root.CFrame * CFrame.new(0, 0, settings.SpawnBack)
	local entity = SpawnService.Spawn(id, Summons.Level(family, caster.level), spot.Position, {
		team = caster.team,
		owner = caster,
		leash = settings.Leash,
		wander = 0,
	})
	if not entity then
		return
	end
	entity.model:SetAttribute("OwnerUserId", player.UserId)
	table.insert(list, { entity = entity, expiresAt = os.clock() + family.duration })
	reindex(player)
	log:Debug("%s raises a %s", caster.name, id)
end

-- The owner's fight is the summons' fight, even against someone their factions tolerate.
local function assist(owner: Entity, victim: Entity, amount: number)
	local player = owner.player
	local list = player and active[player]
	if not list then
		return
	end
	for _, summon in list do
		local entity = summon.entity
		if not Relations.Hostile(entity.team, victim.team) then
			EntityService.Provoke(entity, victim)
		end
		CombatService.AddThreat(entity, victim, amount)
	end
end

local function remove(entity: Entity)
	local owner = entity.owner
	local player = owner and owner.player
	local list = player and active[player]
	if not player or not list then
		return
	end
	for index, summon in list do
		if summon.entity == entity then
			table.remove(list, index)
			reindex(player)
			return
		end
	end
end

-- Ends expired summons and brings back any the caster left far behind (Gate, Blink).
local function sweep()
	local now = os.clock()
	local settings = Tuning.Summons
	for player, list in active do
		local owner = EntityService.ForPlayer(player)
		for _, summon in table.clone(list) do
			local entity = summon.entity
			if now >= summon.expiresAt then
				SpawnService.Despawn(entity)
			elseif owner and entity.alive then
				if (entity.root.Position - owner.root.Position).Magnitude > settings.TeleportDistance then
					entity.model:PivotTo(owner.root.CFrame * CFrame.new(0, 0, settings.SpawnBack))
				end
			end
		end
	end
end

function SummonService.Init(deps: { [string]: any })
	AIService = deps.AIService
	CombatService = deps.CombatService
	EntityService = deps.EntityService
	SpawnService = deps.SpawnService
end

function SummonService.Start()
	CombatService.Damaged:Connect(function(target: Entity, amount: number, _type: string, source: Entity?)
		if source and source.player and amount > 0 and target.kind == "Npc" then
			assist(source, target, amount)
		end
	end)
	CombatService.Died:Connect(function(victim: Entity)
		if victim.player then
			dismiss(victim.player)
		elseif victim.owner then
			remove(victim)
		end
	end)
	EntityService.Removing:Connect(function(entity: Entity)
		if entity.player then
			dismiss(entity.player)
		elseif entity.owner then
			remove(entity)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		dismiss(player)
		chosen[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Tuning.Summons.SweepInterval)
			sweep()
		end
	end)
end

return SummonService
