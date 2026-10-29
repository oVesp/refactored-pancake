--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Enemies = require(ReplicatedStorage.Content.Enemies)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Tuning = require(ReplicatedStorage.Content.Tuning)
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
local ZoneService: any

type Spawner = {
	part: BasePart,
	enemyId: string,
	count: number,
	levelMin: number,
	levelMax: number,
	respawnSeconds: number,
	radius: number,
	zone: string?,
	alive: { Entity },
	pending: number,
}

local spawners: { Spawner } = {}
local npcFolder: Folder
local devSpawned: { Entity } = {}
local random = Random.new()

--[=[
	Spawns enemies from `Spawner` parts with leash and respawn timers, keeps a per-zone active cap
	(game-design.md 5.6), and registers training dummies.
]=]
local SpawnService = {}

local function activeInZone(zone: string?): number
	local count = 0
	for _, spawner in spawners do
		if spawner.zone == zone then
			count += #spawner.alive
		end
	end
	return count
end

-- The ground under a spawn point: terrain or generated world geometry (terraced plots, the camp
-- dais), so enemies never start inside raised ground. Falls back to the point itself.
local function groundAt(position: Vector3): Vector3
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

--[=[
	Spawns one enemy at a position and hands it to AIService. `home`/`leash` default to the spawn
	point and the enemy's leash radius. Returns the entity.
]=]
function SpawnService.Spawn(enemyId: string, level: number, position: Vector3, home: Vector3?): Entity?
	local def = Enemies.ById[enemyId]
	local template = def and ServerStorage.Templates:FindFirstChild(def.template or "Goblin")
	if not def or not template or not template:IsA("Model") then
		log:Warn("Cannot spawn %s", enemyId)
		return nil
	end

	local model = template:Clone()
	model.Name = def.name
	-- Rojo does not keep PrimaryPart on a model file's root instance, so resolve it by name.
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root
	local baseScale = model:GetAttribute("BaseScale")
	model:ScaleTo(def.scale * (if type(baseScale) == "number" then baseScale else 1))
	tint(model, def.color)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local height = root.Size.Y / 2 + humanoid.HipHeight
	position = groundAt(position)
	model:PivotTo(
		CFrame.new(position + Vector3.new(0, height, 0)) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
	)
	model:AddTag("Enemy")
	model.Parent = npcFolder
	root:SetNetworkOwner(nil)

	local entity = EntityService.Register({
		model = model,
		root = root,
		humanoid = humanoid,
		kind = "Npc",
		team = def.team or "Goblins",
		defId = enemyId,
		name = def.name,
		level = level,
		tags = def.tags,
	})
	model:SetAttribute("Elite", def.elite == true)
	StatService.Recompute(entity)
	StatService.Refill(entity)
	AIService.Attach(entity, home or position, def.leashRadius)
	return entity
end

local function fill(spawner: Spawner)
	local missing = spawner.count - #spawner.alive - spawner.pending
	for _ = 1, missing do
		if activeInZone(spawner.zone) >= Tuning.Npc.ActivePerZone then
			return
		end
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(0, spawner.radius)
		local position = spawner.part.Position + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
		local level = random:NextInteger(spawner.levelMin, spawner.levelMax)
		local entity = SpawnService.Spawn(spawner.enemyId, level, position, spawner.part.Position)
		if entity then
			table.insert(spawner.alive, entity)
		end
	end
end

local function readSpawner(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local enemyId = part:GetAttribute("EnemyId")
	if type(enemyId) ~= "string" or not Enemies.ById[enemyId] then
		log:Warn("Spawner %s has unknown EnemyId", part:GetFullName())
		return
	end
	local spawner: Spawner = {
		part = part,
		enemyId = enemyId,
		count = part:GetAttribute("Count") :: number? or 1,
		levelMin = part:GetAttribute("LevelMin") :: number? or 1,
		levelMax = part:GetAttribute("LevelMax") :: number? or 1,
		respawnSeconds = part:GetAttribute("RespawnSeconds") :: number? or 30,
		radius = part:GetAttribute("Radius") :: number? or 8,
		zone = ZoneService.ZoneAt(part.Position),
		alive = {},
		pending = 0,
	}
	table.insert(spawners, spawner)
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

	for _, spawner in spawners do
		local index = table.find(spawner.alive, victim)
		if index then
			table.remove(spawner.alive, index)
			spawner.pending += 1
			task.delay(spawner.respawnSeconds, function()
				spawner.pending -= 1
				fill(spawner)
			end)
			break
		end
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

--[=[ Dev: spawns an enemy near a position, outside spawner bookkeeping. ]=]
function SpawnService.DevSpawn(enemyId: string, level: number, position: Vector3): Entity?
	local entity = SpawnService.Spawn(enemyId, level, position, position)
	if entity then
		table.insert(devSpawned, entity)
	end
	return entity
end

--[=[ Dev: removes every dev-spawned enemy. Returns how many were removed. ]=]
function SpawnService.ClearDevSpawned(): number
	local count = #devSpawned
	for _, entity in table.clone(devSpawned) do
		CombatService.Kill(entity, nil)
	end
	return count
end

--[=[ Registers extra enemies (e.g. a boss's summons) so they are cleaned up like dev spawns. ]=]
function SpawnService.TrackSummon(entity: Entity)
	table.insert(devSpawned, entity)
end

function SpawnService.Init(deps: { [string]: any })
	AIService = deps.AIService
	CombatService = deps.CombatService
	EntityService = deps.EntityService
	StatService = deps.StatService
	StatusService = deps.StatusService
	ZoneService = deps.ZoneService
end

function SpawnService.Start()
	AIService.SetSpawnService(SpawnService)
	npcFolder = Instance.new("Folder")
	npcFolder.Name = "Enemies"
	npcFolder.Parent = workspace

	for _, part in CollectionService:GetTagged("Spawner") do
		readSpawner(part)
	end
	for _, dummy in CollectionService:GetTagged("TrainingDummy") do
		registerDummy(dummy)
	end
	CombatService.Died:Connect(onDied)

	for _, spawner in spawners do
		fill(spawner)
	end
	log:Info("%d spawners active", #spawners)

	task.spawn(function()
		while true do
			task.wait(1)
			resetDummies()
		end
	end)
end

return SpawnService
