--!strict

local Players = game:GetService("Players")

local Animations = require(script.Parent.Animations)

local FADE = 0.2
local MOVING_SPEED = 0.5

-- Weapon type (the character's `Weapon` attribute) to its idle animations: standing, and moving with
-- the legs left to the walk cycle.
local IDLES: { [string]: { stand: string, move: string } } = {
	sword = { stand = "BasicSwordIdle", move = "BasicSwordIdleNoLegs" },
}

local player = Players.LocalPlayer

type Pair = { stand: AnimationTrack, move: AnimationTrack }

local pairs_: { [string]: Pair } = {}
local connections: { RBXScriptConnection } = {}

--[=[
	Local character's weapon idle (docs/systems/weapons.md, Animations): while a weapon with idle
	clips is drawn, its standing idle replaces the default one, and the legless variant plays
	while moving so walk and run keep their legs. Attacks and guard clips play above both.
]=]
local WeaponAnimations = {}

local function refresh(character: Model, humanoid: Humanoid)
	-- Sheathed (out of combat mode) the default idle and walk play.
	local weapon = if character:GetAttribute("Drawn") == true then character:GetAttribute("Weapon") else nil
	local moving = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.WalkSpeed > MOVING_SPEED
	for name, pair in pairs_ do
		local active = name == weapon
		if active and not moving then
			if not pair.stand.IsPlaying then
				pair.stand:Play(FADE)
			end
		elseif pair.stand.IsPlaying then
			pair.stand:Stop(FADE)
		end
		if active and moving then
			if not pair.move.IsPlaying then
				pair.move:Play(FADE)
			end
		elseif pair.move.IsPlaying then
			pair.move:Stop(FADE)
		end
	end
end

local function load(character: Model)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(pairs_)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not animator or not animator:IsA("Animator") then
		return
	end
	if character ~= player.Character then
		return
	end
	for weapon, names in IDLES do
		local stand = Animations.Load(animator, names.stand, Enum.AnimationPriority.Idle, true)
		local move = Animations.Load(animator, names.move, Enum.AnimationPriority.Idle, true)
		if stand and move then
			pairs_[weapon] = { stand = stand, move = move }
		end
	end
	local function update()
		refresh(character, humanoid)
	end
	table.insert(connections, character:GetAttributeChangedSignal("Weapon"):Connect(update))
	table.insert(connections, character:GetAttributeChangedSignal("Drawn"):Connect(update))
	table.insert(connections, humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(update))
	update()
end

--[=[ Loads the idle animations on every spawn. Called once by CombatController. ]=]
function WeaponAnimations.Start()
	player.CharacterAdded:Connect(load)
	if player.Character then
		task.spawn(load, player.Character)
	end
end

return WeaponAnimations
