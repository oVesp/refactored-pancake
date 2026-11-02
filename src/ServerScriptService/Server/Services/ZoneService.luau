--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)
local Zones = require(ReplicatedStorage.Content.Zones)

local UPDATE_INTERVAL = 0.25

local log = Logger.new("ZoneService")

type Volume = {
	id: string,
	cframe: CFrame,
	half: Vector3,
}

local volumes: { Volume } = {}

--[=[
	Zone lookup behind one abstraction (game-design.md 3.7). Volumes are parts tagged `Zone`
	with a `ZoneId` attribute; splitting zones into places later only changes this service.
]=]
local ZoneService = {}

local function addVolume(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local id = instance:GetAttribute("ZoneId")
	if type(id) ~= "string" or not Zones.ById[id] then
		log:Warn("Zone volume %s has unknown ZoneId", instance:GetFullName())
		return
	end
	table.insert(volumes, { id = id, cframe = instance.CFrame, half = instance.Size / 2 })
end

--[=[ Zone id containing a world position, or nil outside every zone. ]=]
function ZoneService.ZoneAt(position: Vector3): string?
	for _, volume in volumes do
		local localPoint = volume.cframe:PointToObjectSpace(position)
		if
			math.abs(localPoint.X) <= volume.half.X
			and math.abs(localPoint.Y) <= volume.half.Y
			and math.abs(localPoint.Z) <= volume.half.Z
		then
			return volume.id
		end
	end
	return nil
end

--[=[ True inside a safe zone: players there take no damage and enemies do not enter. ]=]
function ZoneService.IsSafe(position: Vector3): boolean
	local id = ZoneService.ZoneAt(position)
	return id ~= nil and Zones.ById[id].safe
end

--[=[ Center of a zone's first volume, or nil when the map has none for it. ]=]
function ZoneService.Anchor(id: string): Vector3?
	for _, volume in volumes do
		if volume.id == id then
			return volume.cframe.Position
		end
	end
	return nil
end

local function spawnTagged(tag: string): SpawnLocation?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("SpawnLocation") then
			return instance
		end
	end
	return nil
end

--[=[ The inn's spawn point, where players come back after dying, if the map has one. ]=]
function ZoneService.RespawnPoint(): SpawnLocation?
	return spawnTagged("RespawnPoint")
end

--[=[ The dock's spawn point, where players arrive when they join, if the map has one. ]=]
function ZoneService.ArrivalPoint(): SpawnLocation?
	return spawnTagged("ArrivalSpawn")
end

--[=[
	Where Gate lands at the Pylon: its `Arrival` part when it has one, else ten studs south of
	the tagged model. Nil when the map has no Pylon.
]=]
function ZoneService.PylonPoint(): Vector3?
	for _, instance in CollectionService:GetTagged("Pylon") do
		if instance:IsA("PVInstance") then
			local arrival = instance:FindFirstChild("Arrival", true)
			if arrival and arrival:IsA("BasePart") then
				return arrival.Position
			end
			return instance:GetPivot().Position + Vector3.new(0, 0, 10)
		end
	end
	return nil
end

--[=[ Sends a player's next spawn to the inn (after a death); joining spawns at the dock. ]=]
function ZoneService.UseRespawnPoint(player: Player)
	local respawn = ZoneService.RespawnPoint()
	if respawn then
		player.RespawnLocation = respawn
	end
end

function ZoneService.Init(_deps: { [string]: any })
	for _, instance in CollectionService:GetTagged("Zone") do
		addVolume(instance)
	end
	CollectionService:GetInstanceAddedSignal("Zone"):Connect(addVolume)
end

function ZoneService.Start()
	-- Joining lands at the dock; dying sends the next spawn to the inn (AvatarService).
	local function arrive(player: Player)
		local point = ZoneService.ArrivalPoint() or ZoneService.RespawnPoint()
		if point then
			player.RespawnLocation = point
		end
	end
	Players.PlayerAdded:Connect(arrive)
	for _, player in Players:GetPlayers() do
		arrive(player)
	end

	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local zone = ZoneService.ZoneAt(root.Position)
					if player:GetAttribute("Zone") ~= zone then
						player:SetAttribute("Zone", zone)
					end
				end
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return ZoneService
