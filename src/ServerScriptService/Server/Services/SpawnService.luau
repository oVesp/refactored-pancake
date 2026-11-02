--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Appearance = require(ReplicatedStorage.Content.Appearance)
local Avatar = require(ReplicatedStorage.Shared.Avatar)
local Factions = require(ReplicatedStorage.Content.Factions)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Names = require(ReplicatedStorage.Content.Names)
local NpcDefs = require(ReplicatedStorage.Shared.NpcDefs)
local Relations = require(ReplicatedStorage.Shared.Relations)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local CORPSE_SECONDS = 3
local DUMMY_RESET_SECONDS = 4
local GROUND_PROBE = 40 -- studs above and below a spawn point searched for the ground

local log = Logger.new("SpawnService")

local AIService: any
local CombatService: any
local EntityService: any
local StatService: any
local StatusService: any

local npcFolder: Folder
local devSpawned: { Entity } = {}
local random = Random.new()

--[=[
	Builds NPC bodies and registers them (game-design.md 5.6): monsters from ServerStorage.Templates,
	people from a random `Appearance` look. Who spawns where is GroupService and PopulationService
	(docs/systems/open-world.md); this service also registers training dummies, keeps dev spawns
	and summons, and clears corpses.
]=]
local SpawnService = {}

export type Options = {
	--[=[ Leash and idle patrol centre; defaults to the spawn point. ]=]
	home: Vector3?,
	--[=[ Idle patrol radius (AIService.Attach); 0 holds the spot. ]=]
	wander: number?,
	--[=[ Share of max HP to start with (a group coming back into view keeps its wounds). ]=]
	hp: number?,
	--[=[ Faction instead of the definition's (a summon takes its caster's). ]=]
	team: Factions.FactionId?,
	--[=[ The player entity a summon serves. ]=]
	owner: Entity?,
	--[=[ Leash radius instead of the definition's. ]=]
	leash: number?,
}

-- The ground under a spawn point: terrain or generated world geometry (terraced plots, the camp
-- dais), so NPCs never start inside raised ground. Falls back to the point itself.
function SpawnService.GroundAt(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local world = workspace:FindFirstChild("World")
	params.FilterDescendantsInstances = if world then { workspace.Terrain, world } else { workspace.Terrain }
	local hit =
		workspace:Raycast(position + Vector3.new(0, GROUND_PROBE, 0), Vector3.new(0, -GROUND_PROBE * 2, 0), params)
	return if hit then Vector3.new(position.X, hit.Position.Y, position.Z) else position
end

-- Tints a template's `Body` part; the Goblin template has none, its textures carry the colour.
local function tint(model: Model, color: Color3)
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		body.Color = color
	end
end

local function pick<T>(list: { T }): T
	return list[random:NextInteger(1, #list)]
end

-- A random look dressed in one of the definition's outfits; only men get beards.
local function randomLook(outfits: { string }): Avatar.Look
	local gender = pick(Appearance.Genders.Order)
	return {
		gender = gender,
		skinTone = pick(Appearance.SkinTones.Order),
		hair = pick(Appearance.Hair.Order),
		hairColor = pick(Appearance.HairColors.Order),
		facialHair = if gender == "male" and random:NextNumber() < 0.5
			then pick(Appearance.FacialHair.Order)
			else "none",
		outfit = pick(outfits),
	}
end

-- An R15 body for a human NPC. Its stock Animate script is removed: EnemyAnimationController
-- plays the `Human` clip set from the client.
local function humanModel(def: any): (Model?, string)
	local look = randomLook(def.outfits or { Appearance.Default.outfit })
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Avatar.Build(look), Enum.HumanoidRigType.R15)
	end)
	if not ok then
		log:Throttled("human", 30, "warn", "Cannot build a human body: %s", tostring(model))
		return nil, def.name
	end
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	model:SetAttribute("AnimSet", "Human")
	-- Clients load clips through the Animator; it must exist on the server to replicate.
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end
	local names = (Names :: any)[look.gender] or Names.male
	return model, `{pick(names)}, {def.name}`
end

local function bodyFor(def: any): (Model?, string)
	if def.template == "Human" then
		return humanModel(def)
	end
	local template = ServerStorage.Templates:FindFirstChild(def.template or "Goblin")
	if not template or not template:IsA("Model") then
		return nil, def.name
	end
	local model = template:Clone()
	-- Rojo does not keep PrimaryPart on a model file's root instance, so resolve it by name.
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local baseScale = model:GetAttribute("BaseScale")
	model:ScaleTo(def.scale * (if type(baseScale) == "number" then baseScale else 1))
	tint(model, def.color)
	return model, def.name
end

--[=[
	Spawns one NPC (Content/Enemies or Content/Npcs) at a position and hands it to AIService.
	Monsters are tagged `Enemy`, people `Npc`. Returns the entity. May yield (human bodies load
	their clothing).
]=]
function SpawnService.Spawn(npcId: string, level: number, position: Vector3, options: Options?): Entity?
	local def = NpcDefs.Get(npcId)
	if not def then
		log:Warn("Cannot spawn %s", npcId)
		return nil
	end
	local model, name = bodyFor(def)
	if not model then
		log:Warn("Cannot spawn %s", npcId)
		return nil
	end
	local opts: Options = options or {}
	model.Name = name
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local height = root.Size.Y / 2 + humanoid.HipHeight
	position = SpawnService.GroundAt(position)
	model:PivotTo(
		CFrame.new(position + Vector3.new(0, height, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	)
	local team = opts.team or def.team or "Goblins"
	model:AddTag(if Relations.IsMonster(team) then "Enemy" else "Npc")
	model.Parent = npcFolder
	root:SetNetworkOwner(nil)

	local entity = EntityService.Register({
		model = model,
		root = root,
		humanoid = humanoid,
		kind = "Npc",
		team = team,
		defId = npcId,
		name = name,
		level = level,
		tags = def.tags,
		owner = opts.owner,
	})
	model:SetAttribute("Elite", def.elite == true)
	StatService.Recompute(entity)
	StatService.Refill(entity)
	if opts.hp and opts.hp < 1 then
		StatService.SetHp(entity, math.max(1, entity.stats.MaxHp * opts.hp))
	end
	AIService.Attach(entity, opts.home or position, opts.leash or def.leashRadius, opts.wander)
	return entity
end

--[=[ Removes a living NPC without a death (a group walking out of sight). ]=]
function SpawnService.Despawn(entity: Entity)
	if not entity.alive or entity.kind ~= "Npc" then
		return
	end
	entity.alive = false
	EntityService.Unregister(entity.model)
	entity.model:Destroy()
end

local function onDied(victim: Entity)
	if victim.kind == "Dummy" then
		task.delay(1, function()
			victim.alive = true
			StatService.Refill(victim)
		end)
		return
	end
	if victim.kind ~= "Npc" then
		return
	end
	local devIndex = table.find(devSpawned, victim)
	if devIndex then
		table.remove(devSpawned, devIndex)
	end
	task.delay(CORPSE_SECONDS, function()
		EntityService.Unregister(victim.model)
		victim.model:Destroy()
	end)
end

local function registerDummy(instance: Instance)
	if not instance:IsA("Model") or not instance.PrimaryPart then
		return
	end
	local function list(name: string): { string }?
		local value = instance:GetAttribute(name)
		return if type(value) == "string" then { value } else nil
	end
	local level = instance:GetAttribute("Level")
	local entity = EntityService.Register({
		model = instance,
		root = instance.PrimaryPart,
		humanoid = nil,
		kind = "Dummy",
		team = "Neutral",
		defId = "training_dummy",
		name = instance.Name,
		level = if type(level) == "number" then level else 1,
		tags = { resist = list("Resist"), vulnerable = list("Vulnerable"), immune = list("Immune") },
	})
	StatService.Recompute(entity)
	StatService.Refill(entity)

	local laneLength = instance:GetAttribute("LaneLength")
	local laneSpeed = instance:GetAttribute("LaneSpeed")
	if type(laneLength) == "number" and type(laneSpeed) == "number" then
		local start = instance:GetPivot()
		local elapsed = 0
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			local period = laneLength * 2 / laneSpeed
			local phase = (elapsed % period) / period
			local offset = (if phase < 0.5 then phase * 2 else 2 - phase * 2) - 0.5
			instance:PivotTo(start * CFrame.new(0, 0, offset * laneLength))
		end)
	end
end

local function resetDummies()
	local now = os.clock()
	for _, entity in EntityService.All() do
		if entity.kind == "Dummy" and entity.alive and now - entity.lastCombatAt > DUMMY_RESET_SECONDS then
			if entity.hp < entity.stats.MaxHp or next(entity.statuses) then
				StatusService.Clear(entity)
				StatService.Refill(entity)
			end
		end
	end
end

--[=[ Dev: spawns an NPC near a position, outside any group. It ignores safe zones, for testing in the Dev Yard. ]=]
function SpawnService.DevSpawn(npcId: string, level: number, position: Vector3): Entity?
	local entity = SpawnService.Spawn(npcId, level, position)
	if entity then
		entity.ignoreSafeZone = true
		table.insert(devSpawned, entity)
	end
	return entity
end

--[=[ Dev: removes every dev-spawned NPC. Returns how many were removed. ]=]
function SpawnService.ClearDevSpawned(): number
	local count = #devSpawned
	for _, entity in table.clone(devSpawned) do
		CombatService.Kill(entity, nil)
	end
	return count
end

--[=[ Registers extra NPCs (e.g. a boss's summons) so they are cleaned up like dev spawns. ]=]
function SpawnService.TrackSummon(entity: Entity)
	table.insert(devSpawned, entity)
end

function SpawnService.Init(deps: { [string]: any })
	AIService = deps.AIService
	CombatService = deps.CombatService
	EntityService = deps.EntityService
	StatService = deps.StatService
	StatusService = deps.StatusService
end

function SpawnService.Start()
	AIService.SetSpawnService(SpawnService)
	npcFolder = Instance.new("Folder")
	npcFolder.Name = "Npcs"
	npcFolder.Parent = workspace

	for _, dummy in CollectionService:GetTagged("TrainingDummy") do
		registerDummy(dummy)
	end
	CombatService.Died:Connect(onDied)

	task.spawn(function()
		while true do
			task.wait(1)
			resetDummies()
		end
	end)
end

return SpawnService
