--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Appearance = require(ReplicatedStorage.Content.Appearance)
local Avatar = require(ReplicatedStorage.Shared.Avatar)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)

local log = Logger.new("AvatarService")

local DataService: any
local ProgressionService: any

-- Tag on the creation stage's pedestal.
local STAGE_TAG = "CreatorStage"
-- Studs under the pedestal where a player's placeholder character waits during creation.
local PARK_DEPTH = 8

local creating: { [Player]: boolean } = {}
local spawning: { [Player]: boolean } = {}

--[=[
	Character creation and spawning (docs/systems/character-creation.md). Characters do not
	auto-load; every spawn goes through `LoadCharacterWithHumanoidDescriptionAsync`, so the
	Roblox avatar never shows. A player without a created character still gets a character (the
	engine only copies StarterGui into PlayerGui on spawn) with the default look, parked and
	anchored under the creation stage, which also keeps streaming around the stage.
]=]
local AvatarService = {}

local function stagePart(): BasePart?
	for _, instance in CollectionService:GetTagged(STAGE_TAG) do
		if instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

local function respawnLater(player: Player, character: Model)
	task.delay(Players.RespawnTime, function()
		if player.Parent and player.Character == character then
			AvatarService.Spawn(player)
		end
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	local profile = DataService.Get(player)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not (humanoid and humanoid:IsA("Humanoid")) then
		return
	end
	if profile then
		humanoid.DisplayName = profile.name
	end
	humanoid.Died:Connect(function()
		respawnLater(player, character)
	end)
end

local function park(character: Model)
	local pedestal = stagePart()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if pedestal and root and root:IsA("BasePart") then
		root.Anchored = true
		character:PivotTo(CFrame.new(pedestal.Position - Vector3.new(0, PARK_DEPTH, 0)))
	end
end

--[=[
	Loads the player's character with their saved look at their respawn location, or, before
	creation, a parked placeholder under the creation stage. Yields.
]=]
function AvatarService.Spawn(player: Player)
	local profile = DataService.Get(player)
	if not profile or spawning[player] then
		return
	end
	spawning[player] = true
	local look = if profile.created then Avatar.LookOf(profile.appearance) else Appearance.Default
	local ok, err = pcall(function()
		player:LoadCharacterWithHumanoidDescriptionAsync(Avatar.Build(look))
	end)
	spawning[player] = nil
	if not ok then
		log:Warn("Spawn failed for %d: %s", player.UserId, tostring(err))
	elseif not profile.created and player.Character then
		park(player.Character)
	end
end

--[=[
	Creates the player's character from a creator submission: stores name, heritage and look,
	trains the starter class, learns the starter spell and spawns the character. Returns ok and a
	reason code (also sent as a notice when refused).
]=]
function AvatarService.Create(player: Player, creation: Avatar.Creation): (boolean, string?)
	local profile = DataService.Get(player)
	if not profile or profile.created or creating[player] then
		return false, "AlreadyCreated"
	end
	local ok, reason = Avatar.ValidateCreation(creation)
	if not ok then
		NetServer.Fire("Notify", player, reason or "BadCreation", {})
		return false, reason
	end
	creating[player] = true
	DataService.Update(player, function(p: any)
		p.name = creation.name
		p.heritage = creation.heritage
		p.appearance = Avatar.LookOf(creation)
	end, "appearance")
	local trained, trainReason = ProgressionService.TrainClass(player, creation.classId)
	if not trained then
		log:Warn("Starter class refused for %d: %s", player.UserId, tostring(trainReason))
	end
	if creation.spellId ~= "" then
		ProgressionService.LearnSpell(player, creation.spellId)
	end
	DataService.Update(player, function(p: any)
		p.created = true
	end, "created")
	creating[player] = nil
	AvatarService.Spawn(player)
	return true, nil
end

--[=[ Dev and tests: creates a default character (optionally of `classId`) without the creator. ]=]
function AvatarService.CreateDefault(player: Player, classId: string?): (boolean, string?)
	return AvatarService.Create(player, Avatar.DefaultCreation(classId))
end

local function onJoin(player: Player)
	local profile = DataService.WaitForProfile(player)
	if not profile or player.Parent == nil then
		return
	end
	AvatarService.Spawn(player)
end

function AvatarService.Init(deps: { [string]: any })
	DataService = deps.DataService
	ProgressionService = deps.ProgressionService
end

function AvatarService.Start()
	NetServer.Connect("CreateCharacter", function(player: Player, creation: any)
		AvatarService.Create(player, creation)
	end)
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		task.spawn(onJoin, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		creating[player] = nil
		spawning[player] = nil
	end)
end

return AvatarService
