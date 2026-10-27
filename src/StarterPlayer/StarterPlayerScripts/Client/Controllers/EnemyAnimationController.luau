--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Maid = require(ReplicatedStorage.Shared.Maid)

local Clips = require(script.Parent.Parent.Animation.Clips)

type Rig = {
	model: Model,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	locomotion: AnimationTrack?,
	dead: boolean,
}

-- Above this planar speed (studs/s) the run clip replaces the walk clip.
local RUN_SPEED = 10
local MOVE_SPEED = 0.5
local FADE = 0.2

type ClipSpec = { priority: Enum.AnimationPriority, looped: boolean }

local CLIPS: { [string]: ClipSpec } = {
	Idle = { priority = Enum.AnimationPriority.Core, looped = true },
	Walk = { priority = Enum.AnimationPriority.Core, looped = true },
	Run = { priority = Enum.AnimationPriority.Core, looped = true },
	Attack = { priority = Enum.AnimationPriority.Action, looped = false },
	Throw = { priority = Enum.AnimationPriority.Action, looped = false },
	Hit = { priority = Enum.AnimationPriority.Action, looped = false },
	Death = { priority = Enum.AnimationPriority.Action4, looped = false },
}

local maids: { [Instance]: Maid.Maid } = {}
local rigs: { [Model]: Rig } = {}

--[=[
	Plays enemy animations locally (game-design.md 5.6 visuals are client-side). Locomotion follows
	the replicated root velocity; one-shot clips follow the server's `AnimCue` attribute
	("<clip>:<sequence>"). Clips resolve through `Animation/Clips`.
]=]
local EnemyAnimationController = {}

local function setLocomotion(rig: Rig, key: string, speed: number)
	local track = rig.tracks[key]
	if rig.locomotion ~= track then
		if rig.locomotion then
			rig.locomotion:Stop(FADE)
		end
		rig.locomotion = track
		if track then
			track:Play(FADE)
		end
	end
	if track and key ~= "Idle" then
		track:AdjustSpeed(math.clamp(speed / (if key == "Run" then 16 else 8), 0.6, 1.6))
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
	local rig: Rig = { model = model, root = root, tracks = {}, locomotion = nil, dead = false }
	for clip, spec in CLIPS do
		local track = Clips.Load(animator, set .. clip, spec.priority, spec.looped)
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

	RunService.Heartbeat:Connect(function()
		for _, rig in rigs do
			if rig.dead then
				continue
			end
			local velocity = rig.root.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			-- Sets without a run clip keep walking.
			if speed > RUN_SPEED and rig.tracks.Run then
				setLocomotion(rig, "Run", speed)
			elseif speed > MOVE_SPEED then
				setLocomotion(rig, "Walk", speed)
			else
				setLocomotion(rig, "Idle", 0)
			end
		end
	end)
end

return EnemyAnimationController
