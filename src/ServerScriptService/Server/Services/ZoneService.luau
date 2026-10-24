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

--[=[ The respawn point in the respawn zone, if the map has one. ]=]
function ZoneService.RespawnPoint(): SpawnLocation?
	for _, instance in CollectionService:GetTagged("RespawnPoint") do
		if instance:IsA("SpawnLocation") then
			return instance
		end
	end
	return nil
end

function ZoneService.Init(_deps: { [string]: any })
	for _, instance in CollectionService:GetTagged("Zone") do
		addVolume(instance)
	end
	CollectionService:GetInstanceAddedSignal("Zone"):Connect(addVolume)
end

function ZoneService.Start()
	local respawn = ZoneService.RespawnPoint()
	Players.PlayerAdded:Connect(function(player)
		if respawn then
			player.RespawnLocation = respawn
		end
	end)
	for _, player in Players:GetPlayers() do
		if respawn then
			player.RespawnLocation = respawn
		end
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
