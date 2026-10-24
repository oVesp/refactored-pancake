--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Assets = require(ReplicatedStorage.Content.Assets)
local Zones = require(ReplicatedStorage.Content.Zones)

--[=[
	Cosmetic audio from the Assets manifest: one-shots (2D or at a world position) and a zone loop
	(village ambience in safe zones, music outside). Never authoritative.
]=]
local AudioController = {}

local sounds: { [string]: Sound } = {}
local currentLoop: Sound? = nil

local function sound(key: string): Sound?
	local existing = sounds[key]
	if existing then
		return existing
	end
	local asset = Assets.Audio[key]
	if not asset then
		return nil
	end
	local created = Instance.new("Sound")
	created.Name = key
	created.SoundId = asset.id
	created.Volume = asset.volume
	created.Looped = asset.looped == true
	created.Parent = SoundService
	sounds[key] = created
	return created
end

--[=[ Plays a 2D one-shot. ]=]
function AudioController.Play(key: string)
	local base = sound(key)
	if base then
		SoundService:PlayLocalSound(base)
	end
end

--[=[ Plays a one-shot at a world position (distance-attenuated). ]=]
function AudioController.PlayAt(key: string, position: Vector3)
	local base = sound(key)
	if not base then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local copy = base:Clone()
	copy.RollOffMaxDistance = 120
	copy.Parent = anchor
	copy:Play()
	copy.Ended:Once(function()
		anchor:Destroy()
	end)
	task.delay(6, function()
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

local function setLoop(key: string)
	local next = sound(key)
	if next == currentLoop then
		return
	end
	if currentLoop then
		currentLoop:Stop()
	end
	currentLoop = next
	if next then
		next:Play()
	end
end

local function onZoneChanged()
	local id = Players.LocalPlayer:GetAttribute("Zone")
	local zone = if type(id) == "string" then Zones.ById[id] else nil
	setLoop(if zone and not zone.safe then "FieldMusic" else "VillageAmbience")
end

function AudioController.Init(_deps: { [string]: any }) end

function AudioController.Start()
	Players.LocalPlayer:GetAttributeChangedSignal("Zone"):Connect(onZoneChanged)
	onZoneChanged()
end

return AudioController
