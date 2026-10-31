--!strict

local Players = game:GetService("Players")

local Animations = require(script.Parent.Animations)

local FADE = 0.15

local player = Players.LocalPlayer

local track: AnimationTrack?
local humanoid: Humanoid?
local running = false
local connections: { RBXScriptConnection } = {}

--[=[
	Local character's run clip while the double-tap run is on. The default Animate script already shows
	its own run at walking speed, so this plays over it, on the ground only. It sits at Idle priority,
	above Animate (Core) and below the weapon idles (Movement), which keep their arms over its legs.
]=]
local RunAnimations = {}

local function refresh()
	if not track or not humanoid then
		return
	end
	local active = running and humanoid:GetState() == Enum.HumanoidStateType.Running
	if active and not track.IsPlaying then
		track:Play(FADE)
	elseif not active and track.IsPlaying then
		track:Stop(FADE)
	end
end

local function load(character: Model)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	track = nil
	humanoid = nil
	local found = character:WaitForChild("Humanoid", 10)
	local animator = found and found:WaitForChild("Animator", 10)
	if not found or not found:IsA("Humanoid") or not animator or not animator:IsA("Animator") then
		return
	end
	if character ~= player.Character then
		return
	end
	humanoid = found
	track = Animations.Load(animator, "PlayerRun", Enum.AnimationPriority.Idle, true)
	table.insert(connections, found.StateChanged:Connect(refresh))
	refresh()
end

--[=[ Turns the run clip on or off with the run gait. ]=]
function RunAnimations.SetRunning(on: boolean)
	running = on
	refresh()
end

--[=[ Loads the run animation on every spawn. Called once by CombatController. ]=]
function RunAnimations.Start()
	player.CharacterAdded:Connect(load)
	if player.Character then
		task.spawn(load, player.Character)
	end
end

return RunAnimations
