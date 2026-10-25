--!strict

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Content.Assets)
local Logger = require(ReplicatedStorage.Shared.Logger)

local log = Logger.new("Clips")

local resolved: { [string]: string } = {}

--[=[
	Resolves `Assets.Animations` keys to playable animation ids: the uploaded id, else the
	KeyframeSequence under ReplicatedStorage.Animations registered at runtime. Registration only
	works in Studio and its temporary id is local to this client.
]=]
local Clips = {}

--[=[ The animation id for `key`, or nil when the clip is missing or cannot be registered. ]=]
function Clips.Id(key: string): string?
	if resolved[key] then
		return resolved[key]
	end
	local asset = Assets.Animations[key]
	if not asset then
		return nil
	end
	local id = asset.id
	if not id then
		local folder = ReplicatedStorage:FindFirstChild("Animations")
		local sequence = folder and folder:FindFirstChild(asset.keyframes, true)
		if not sequence or not sequence:IsA("KeyframeSequence") then
			log:Warn("Missing KeyframeSequence %s", asset.keyframes)
			return nil
		end
		local ok, temp = pcall(function()
			return KeyframeSequenceProvider:RegisterKeyframeSequence(sequence)
		end)
		if not ok then
			log:Throttled("register", 60, "warn", "Animation %s has no uploaded id: %s", key, tostring(temp))
			return nil
		end
		id = temp
	end
	resolved[key] = id :: string
	return id
end

--[=[ Loads `key` on `animator` with the given priority and looping, or nil when it cannot resolve. ]=]
function Clips.Load(animator: Animator, key: string, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack?
	local id = Clips.Id(key)
	if not id then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	return track
end

return Clips
