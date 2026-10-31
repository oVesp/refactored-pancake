--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = require(script.Parent.Animations)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)

local FADE_IN = 0.1
local FADE_OUT = 0.15

local player = Players.LocalPlayer

local hold: AnimationTrack? = nil
local shieldHold: AnimationTrack? = nil
local parry: AnimationTrack? = nil
local guardConnection: RBXScriptConnection? = nil
local shieldConnection: RBXScriptConnection? = nil

--[=[
	Local character's guard animations (docs/systems/combat.md, Animation): GuardHold (ShieldBlock with a shield) loops while the
	server-set `Guarding` attribute is true, and GuardParry plays when `ShowParry` names this
	character as the defender. Effects for the parry belong to VfxController.
]=]
local GuardAnimations = {}

local function drive(track: AnimationTrack?, on: boolean)
	if not track then
		return
	end
	if on and not track.IsPlaying then
		track:Play(FADE_IN)
	elseif not on and track.IsPlaying then
		track:Stop(FADE_OUT)
	end
end

local function refresh(character: Model)
	local guarding = character:GetAttribute("Guarding") == true
	-- A held shield raises its own one-arm clip; without one the two-forearm guard plays.
	local shielded = character:GetAttribute("Shield") ~= nil and shieldHold ~= nil
	drive(hold, guarding and not shielded)
	drive(shieldHold, guarding and shielded)
end

local function load(character: Model)
	if guardConnection then
		guardConnection:Disconnect()
		guardConnection = nil
	end
	if shieldConnection then
		shieldConnection:Disconnect()
		shieldConnection = nil
	end
	hold, shieldHold, parry = nil, nil, nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not animator or not animator:IsA("Animator") or character ~= player.Character then
		return
	end
	hold = Animations.Load(animator, "GuardHold", Enum.AnimationPriority.Action, true)
	shieldHold = Animations.Load(animator, "ShieldBlock", Enum.AnimationPriority.Action, true)
	-- Above the hold so the deflection reads while guard is still up.
	parry = Animations.Load(animator, "GuardParry", Enum.AnimationPriority.Action2, false)
	local changed = function()
		refresh(character)
	end
	guardConnection = character:GetAttributeChangedSignal("Guarding"):Connect(changed)
	shieldConnection = character:GetAttributeChangedSignal("Shield"):Connect(changed)
	refresh(character)
end

--[=[ Loads the animations on every spawn and listens for parries. Called once by CombatController. ]=]
function GuardAnimations.Start()
	NetClient.Connect("ShowParry", function(defender: Model)
		local track = parry
		if track and defender == player.Character then
			track:Play(0.05)
		end
	end)
	player.CharacterAdded:Connect(load)
	if player.Character then
		task.spawn(load, player.Character)
	end
end

return GuardAnimations
