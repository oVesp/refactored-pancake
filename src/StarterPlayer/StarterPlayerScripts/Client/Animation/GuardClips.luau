--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Clips = require(script.Parent.Clips)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)

local FADE_IN = 0.1
local FADE_OUT = 0.15

local player = Players.LocalPlayer

local hold: AnimationTrack? = nil
local parry: AnimationTrack? = nil
local guardConnection: RBXScriptConnection? = nil

--[=[
	Local character's guard clips (docs/systems/combat.md, Animation): GuardHold loops while the
	server-set `Guarding` attribute is true, and GuardParry plays when `ShowParry` names this
	character as the defender. Effects for the parry belong to VfxController.
]=]
local GuardClips = {}

local function refresh(character: Model)
	local track = hold
	if not track then
		return
	end
	local guarding = character:GetAttribute("Guarding") == true
	if guarding and not track.IsPlaying then
		track:Play(FADE_IN)
	elseif not guarding and track.IsPlaying then
		track:Stop(FADE_OUT)
	end
end

local function load(character: Model)
	if guardConnection then
		guardConnection:Disconnect()
		guardConnection = nil
	end
	hold, parry = nil, nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not animator or not animator:IsA("Animator") or character ~= player.Character then
		return
	end
	hold = Clips.Load(animator, "GuardHold", Enum.AnimationPriority.Action, true)
	-- Above the hold so the deflection reads while guard is still up.
	parry = Clips.Load(animator, "GuardParry", Enum.AnimationPriority.Action2, false)
	guardConnection = character:GetAttributeChangedSignal("Guarding"):Connect(function()
		refresh(character)
	end)
	refresh(character)
end

--[=[ Loads the clips on every spawn and listens for parries. Called once by CombatController. ]=]
function GuardClips.Start()
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

return GuardClips
