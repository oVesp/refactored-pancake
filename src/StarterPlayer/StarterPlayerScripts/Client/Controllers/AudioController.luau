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

-- One-shots vary in pitch by this share so repeats do not sound identical.
local PITCH_VARIANCE = 0.06
-- A key played again within this many seconds is dropped, so a swarm's hits do not stack.
local RETRIGGER_GAP = 0.05

local sounds: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local currentLoop: Sound? = nil

local function ready(key: string): boolean
	local now = os.clock()
	if now - (lastPlayed[key] or 0) < RETRIGGER_GAP then
		return false
	end
	lastPlayed[key] = now
	return true
end

local function pitch(): number
	return 1 + (math.random() * 2 - 1) * PITCH_VARIANCE
end

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
	if base and ready(key) then
		base.PlaybackSpeed = pitch()
		SoundService:PlayLocalSound(base)
	end
end

--[=[ Plays a one-shot at a world position (distance-attenuated). Returns the copy, to stop it early. ]=]
function AudioController.PlayAt(key: string, position: Vector3): Sound?
	local base = sound(key)
	if not base or not ready(key) then
		return nil
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = position
	anchor.Parent = workspace.Terrain
	local copy = base:Clone()
	copy.RollOffMaxDistance = 120
	copy.PlaybackSpeed = pitch()
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
	return copy
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
