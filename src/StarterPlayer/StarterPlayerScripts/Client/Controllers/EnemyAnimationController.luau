--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimRoles = require(ReplicatedStorage.Content.AnimRoles)
local Locomotion = require(ReplicatedStorage.Shared.Locomotion)
local Maid = require(ReplicatedStorage.Shared.Maid)

local Clips = require(script.Parent.Parent.Animation.Clips)

type Rig = {
	model: Model,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	locomotion: AnimationTrack?,
	motion: Locomotion.State,
	-- Playback rate last given to the locomotion track.
	rate: number,
	dead: boolean,
}

local FADE = 0.2
-- Rate changes smaller than this are not applied, so a hitstop freeze holds while the rig moves.
local RATE_STEP = 0.05

local PRIORITIES: { [AnimRoles.Priority]: Enum.AnimationPriority } = {
	Core = Enum.AnimationPriority.Core,
	Idle = Enum.AnimationPriority.Idle,
	Movement = Enum.AnimationPriority.Movement,
	Action = Enum.AnimationPriority.Action,
	Action2 = Enum.AnimationPriority.Action2,
	Action3 = Enum.AnimationPriority.Action3,
	Action4 = Enum.AnimationPriority.Action4,
}

local maids: { [Instance]: Maid.Maid } = {}
local rigs: { [Model]: Rig } = {}

--[=[
	Plays enemy animations locally (game-design.md 5.6 visuals are client-side). Locomotion follows
	the replicated root velocity through `Shared/Locomotion`, which smooths it and holds each clip
	long enough that jitter never restarts one; one-shot clips follow the server's `AnimCue` attribute
	("<clip>:<sequence>"). Roles come from `Content/AnimRoles`; clips resolve through `Animation/Clips`.
]=]
local EnemyAnimationController = {}

local function setLocomotion(rig: Rig, key: Locomotion.Clip, speed: number)
	local track = rig.tracks[key]
	if rig.locomotion ~= track then
		if rig.locomotion then
			rig.locomotion:Stop(FADE)
		end
		rig.locomotion = track
		rig.rate = 1
		if track then
			track:Play(FADE)
		end
	end
	if track and key ~= "Idle" then
		local rate = math.clamp(speed / (if key == "Run" then 16 else 8), 0.6, 1.6)
		if math.abs(rate - rig.rate) >= RATE_STEP then
			rig.rate = rate
			track:AdjustSpeed(rate)
		end
	end
end

local function onCue(rig: Rig)
	local cue = rig.model:GetAttribute("AnimCue")
	if type(cue) ~= "string" then
		return
	end
	local clip = string.match(cue, "^(%a+):")
	local track = clip and rig.tracks[clip]
	if not track then
		return
	end
	if clip == "Death" then
		rig.dead = true
		for _, other in rig.tracks do
			other:Stop(FADE)
		end
		rig.locomotion = nil
	end
	track:Play(0.05)
end

local function attach(model: Instance)
	if not model:IsA("Model") or maids[model] then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not animator or not root or not root:IsA("BasePart") then
		return
	end
	local set = model:GetAttribute("AnimSet")
	if type(set) ~= "string" then
		return
	end

	local maid = Maid.new()
	maids[model] = maid
	local rig: Rig =
		{ model = model, root = root, tracks = {}, locomotion = nil, motion = Locomotion.new(), rate = 1, dead = false }
	for clip, role in AnimRoles.Enemy do
		local track = Clips.Load(animator, set .. clip, PRIORITIES[role.priority], role.looped)
		if track then
			rig.tracks[clip] = track
		end
	end
	rigs[model] = rig

	maid:Give(model:GetAttributeChangedSignal("AnimCue"):Connect(function()
		onCue(rig)
	end))
	maid:Give(function()
		for _, track in rig.tracks do
			track:Stop(0)
			track:Destroy()
		end
		rigs[model] = nil
	end)
	maid:Give(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			maid:Clean()
			maids[model] = nil
		end
	end))
end

local function detach(model: Instance)
	local maid = maids[model]
	if maid then
		maid:Clean()
		maids[model] = nil
	end
end

function EnemyAnimationController.Init(_deps: { [string]: any }) end

function EnemyAnimationController.Start()
	for _, model in CollectionService:GetTagged("Enemy") do
		task.spawn(attach, model)
	end
	CollectionService:GetInstanceAddedSignal("Enemy"):Connect(attach)
	CollectionService:GetInstanceRemovedSignal("Enemy"):Connect(detach)

	RunService.Heartbeat:Connect(function(dt: number)
		for _, rig in rigs do
			if rig.dead then
				continue
			end
			local velocity = rig.root.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local clip = Locomotion.Step(rig.motion, speed, dt, if rig.tracks.Run then true else false)
			setLocomotion(rig, clip, rig.motion.speed)
		end
	end)
end

return EnemyAnimationController
