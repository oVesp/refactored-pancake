--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseStats = require(ReplicatedStorage.Content.BaseStats)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Logger = require(ReplicatedStorage.Shared.Logger)

local Attributes = Constants.Attributes
local log = Logger.new("StatService")

--[=[
	Owns character pools. The `Hp` attribute is authoritative; the Humanoid's health mirrors it
	so default Roblox behavior (death, health display) stays consistent.
]=]
local StatService = {}

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

--[=[ Sets current HP, clamped to `[0, MaxHp]`, and mirrors it to the Humanoid. Returns the applied value. ]=]
function StatService.SetHp(character: Model, hp: number): number
	local maxHp = character:GetAttribute(Attributes.MaxHp)
	assert(type(maxHp) == "number", "Character has no MaxHp; it was not set up by StatService")

	local applied = math.clamp(hp, 0, maxHp)
	character:SetAttribute(Attributes.Hp, applied)

	local humanoid = getHumanoid(character)
	if humanoid then
		humanoid.Health = applied
	end
	return applied
end

--[=[ Reduces HP by a non-negative amount after mitigation has been applied by the caller. ]=]
function StatService.ApplyDamage(character: Model, amount: number): number
	assert(amount >= 0, "Damage must be non-negative")
	local hp = character:GetAttribute(Attributes.Hp)
	assert(type(hp) == "number", "Character has no Hp; it was not set up by StatService")
	return StatService.SetHp(character, hp - amount)
end

local function setUpCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		log:Warn("Character %s has no Humanoid", character:GetFullName())
		return
	end

	character:SetAttribute(Attributes.MaxHp, BaseStats.MaxHp)
	character:SetAttribute(Attributes.MaxMp, BaseStats.MaxMp)
	character:SetAttribute(Attributes.Mp, BaseStats.MaxMp)
	character:SetAttribute(Attributes.MaxFocus, BaseStats.MaxFocus)
	character:SetAttribute(Attributes.Focus, BaseStats.MaxFocus)

	humanoid.MaxHealth = BaseStats.MaxHp
	StatService.SetHp(character, BaseStats.MaxHp)

	humanoid.Died:Once(function()
		character:SetAttribute(Attributes.Hp, 0)
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(setUpCharacter)
	if player.Character then
		task.spawn(setUpCharacter, player.Character)
	end
end

function StatService.Init(_deps: { [string]: any }) end

function StatService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

return StatService
