--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local log = Logger.new("Animations")

--[=[
	Playable animations: the `Animation` instances under ReplicatedStorage.Animations, one per key,
	generated from content/animations/<set>.json by `python tools/anim/anim.py sync`
	(docs/art/animation-pipeline.md). Enemy keys are `<AnimSet><Role>` (Content/AnimRoles); combat keys
	are named by `SkillDef.animation` or the drivers beside this module. Markers inside a clip use the
	names in `AnimRoles.Markers`.
]=]
local Animations = {}

--[=[ The `Animation` instance for `key`, or nil when no such animation exists. ]=]
function Animations.Get(key: string): Animation?
	local folder = ReplicatedStorage:FindFirstChild("Animations")
	local animation = folder and folder:FindFirstChild(key)
	if animation and animation:IsA("Animation") then
		return animation
	end
	log:Throttled("missing-" .. key, 60, "warn", "No animation %s under ReplicatedStorage.Animations", key)
	return nil
end

--[=[ Loads `key` on `animator` with the given priority and looping, or nil when it does not exist. ]=]
function Animations.Load(
	animator: Animator,
	key: string,
	priority: Enum.AnimationPriority,
	looped: boolean
): AnimationTrack?
	local animation = Animations.Get(key)
	if not animation then
		return nil
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = looped
	return track
end

return Animations
