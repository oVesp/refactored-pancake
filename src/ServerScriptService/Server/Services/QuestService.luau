--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Quests = require(ReplicatedStorage.Content.Quests)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local BOARD_TAG = "QuestBoard"
local SPOT_TRIES = 24
local SPOT_ARC = math.rad(80) -- spots lie within this angle of north (-Z) from the board
local GROUND_TOP = 400
-- Slack on top of the board's reach for lag, in studs.
local REACH_SLACK = 8
-- Straight north of the board, used when no random spot is dry land.
local FALLBACK_DISTANCE = 200

local log = Logger.new("QuestService")

local CombatService: any
local DataService: any
local GroupService: any
local ProgressionService: any
local ZoneService: any

local random = Random.new()
-- The goblin party each player's quest spawned, removed when the quest ends.
local parties: { [Player]: any } = {}

--[=[
	Extermination quests (docs/systems/economy.md). A board is a part tagged `QuestBoard`; players
	take one quest at a time, a goblin party appears `Tuning.Quests.SpawnMin` to `SpawnMax` studs from
	the board, kills of the quest's targets count, and the reward is paid at the board. The active
	quest is saved in the profile; the party is spawned again on rejoin.
]=]
local QuestService = {}

local function notify(player: Player, key: string, ...: any)
	NetServer.Fire("Notify", player, key, { ... })
end

local function boardNear(player: Player, body: Instance): boolean
	if not body:IsA("BasePart") or not CollectionService:HasTag(body, BOARD_TAG) then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil
		and root:IsA("BasePart")
		and (root.Position - body.Position).Magnitude <= Tuning.Quests.Reach + REACH_SLACK
end

local raycast = RaycastParams.new()
raycast.FilterType = Enum.RaycastFilterType.Include

-- Dry, level, unprotected ground at (x, z), or nil.
local function groundAt(x: number, z: number): Vector3?
	local world = workspace:FindFirstChild("World")
	raycast.FilterDescendantsInstances = if world then { workspace.Terrain, world } else { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, GROUND_TOP, z), Vector3.new(0, -GROUND_TOP * 2, 0), raycast)
	if not hit or hit.Material == Enum.Material.Water or hit.Normal.Y < 0.9 or hit.Position.Y < 0 then
		return nil
	end
	if ZoneService.IsSafe(hit.Position) then
		return nil
	end
	return hit.Position
end

-- A spot for the party north of the board (the sea is south of the Harbor), 150 to 300 studs out.
local function findSpot(origin: Vector3): Vector3?
	for _ = 1, SPOT_TRIES do
		local angle = random:NextNumber(-SPOT_ARC, SPOT_ARC)
		local distance = random:NextNumber(Tuning.Quests.SpawnMin, Tuning.Quests.SpawnMax)
		local ground = groundAt(origin.X + math.sin(angle) * distance, origin.Z - math.cos(angle) * distance)
		if ground then
			return ground
		end
	end
	return groundAt(origin.X, origin.Z - FALLBACK_DISTANCE)
end

local function firstBoard(): BasePart?
	for _, instance in CollectionService:GetTagged(BOARD_TAG) do
		if instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

local function endParty(player: Player)
	local group = parties[player]
	parties[player] = nil
	if group and not group.removed then
		GroupService.Remove(group)
	end
end

-- Members the quest still needs, as the party the world holds for the player.
local function spawnParty(player: Player, quest: Quests.QuestDef, remaining: number, origin: Vector3): boolean
	local spot = findSpot(origin)
	if not spot then
		return false
	end
	local members = {}
	for _, entry in quest.party do
		for _ = 1, entry.count do
			if #members < math.max(remaining, 1) then
				table.insert(members, {
					npc = entry.npc,
					level = random:NextInteger(entry.level[1], entry.level[2]),
					range = entry.level,
					hp = 1,
					entity = nil,
				})
			end
		end
	end
	endParty(player)
	local group
	group = GroupService.Create({
		label = `quest/{quest.id}`,
		members = members,
		station = spot,
		wander = Tuning.Quests.PartyWander,
		onEmpty = function()
			if parties[player] == group then
				parties[player] = nil
			end
		end,
	})
	parties[player] = group
	log:Debug("%s: party of %d at %s", quest.id, #members, tostring(spot))
	return true
end

local function accept(player: Player, board: Instance, questId: string)
	local profile = DataService.Get(player)
	local quest = Quests.ById[questId]
	if not profile or not quest or not boardNear(player, board) then
		return
	end
	if profile.quest then
		notify(player, "QuestBusy")
		return
	end
	if not spawnParty(player, quest, quest.count, (board :: BasePart).Position) then
		notify(player, "QuestNoSpot")
		return
	end
	DataService.Update(player, function(p: any)
		p.quest = { id = quest.id, kills = 0 }
	end, "quest")
	notify(player, "QuestAccepted", quest.name)
end

local function turnIn(player: Player, board: Instance)
	local profile = DataService.Get(player)
	local active = profile and profile.quest
	local quest = active and Quests.ById[active.id]
	if not profile or not boardNear(player, board) then
		return
	end
	if not active or not quest then
		notify(player, "QuestNone")
		return
	end
	if active.kills < quest.count then
		notify(player, "QuestUnfinished")
		return
	end
	DataService.Update(player, function(p: any)
		p.gold += quest.reward.gold
		p.quest = nil
	end, "gold")
	endParty(player)
	ProgressionService.GrantXp(player, quest.reward.xp)
	NetServer.Fire("ShowGain", player, "Gold", "Gold", quest.reward.gold)
	notify(player, "QuestDone", quest.name, quest.reward.gold)
end

local function abandon(player: Player, board: Instance)
	local profile = DataService.Get(player)
	if not profile or not boardNear(player, board) then
		return
	end
	if not profile.quest then
		notify(player, "QuestNone")
		return
	end
	DataService.Update(player, function(p: any)
		p.quest = nil
	end, "quest")
	endParty(player)
	notify(player, "QuestAbandoned")
end

local function onAction(player: Player, board: Instance, action: string, questId: string)
	if action == "Accept" then
		accept(player, board, questId)
	elseif action == "Turn" then
		turnIn(player, board)
	elseif action == "Abandon" then
		abandon(player, board)
	end
end

-- A kill of a quest target by a player (or a summon of theirs) counts toward their quest.
local function onDied(victim: Entity, killer: Entity?)
	local player = if killer and killer.kind == "Player" then killer.player else nil
	if not player or victim.kind ~= "Npc" then
		return
	end
	local profile = DataService.Get(player)
	local active = profile and profile.quest
	local quest = active and Quests.ById[active.id]
	if not profile or not active or not quest or active.kills >= quest.count then
		return
	end
	if not table.find(quest.targets, victim.defId) then
		return
	end
	DataService.Update(player, function(p: any)
		if p.quest then
			p.quest.kills += 1
		end
	end, "quest")
	notify(player, "QuestProgress", quest.name, profile.quest and profile.quest.kills or quest.count, quest.count)
end

local function bindBoard(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local prompt = instance:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	if not prompt.Parent then
		prompt.ActionText = "Read"
		prompt.ObjectText = "Quest Board"
		prompt.MaxActivationDistance = Tuning.Quests.Reach
		prompt.RequiresLineOfSight = false
		prompt.Parent = instance
	end
	prompt.Triggered:Connect(function(player: Player)
		NetServer.Fire("OpenQuestBoard", player, instance)
	end)
end

-- A character that logs in with a quest in hand finds its party again.
local function restore(player: Player)
	local profile = DataService.WaitForProfile(player)
	local active = profile and profile.quest
	local quest = active and Quests.ById[active.id]
	local board = firstBoard()
	if not quest or not active or not board or player.Parent == nil then
		return
	end
	if active.kills < quest.count then
		spawnParty(player, quest, quest.count - active.kills, board.Position)
	end
end

function QuestService.Init(deps: { [string]: any })
	CombatService = deps.CombatService
	DataService = deps.DataService
	GroupService = deps.GroupService
	ProgressionService = deps.ProgressionService
	ZoneService = deps.ZoneService
end

function QuestService.Start()
	NetServer.Connect("QuestAction", onAction)
	CombatService.Died:Connect(onDied)
	for _, instance in CollectionService:GetTagged(BOARD_TAG) do
		bindBoard(instance)
	end
	CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(bindBoard)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(restore, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(restore, player)
	end
	Players.PlayerRemoving:Connect(endParty)
end

return QuestService
