--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TextChatService = game:GetService("TextChatService")

local Classes = require(ReplicatedStorage.Content.Classes)
local DevAllowlist = require(ServerStorage.ContentServerOnly.DevAllowlist)
local Enemies = require(ReplicatedStorage.Content.Enemies)
local Items = require(ReplicatedStorage.Content.Items)
local Logger = require(ReplicatedStorage.Shared.Logger)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local NpcDefs = require(ReplicatedStorage.Shared.NpcDefs)
local Npcs = require(ReplicatedStorage.Content.Npcs)
local RateLimiter = require(ReplicatedStorage.Shared.RateLimiter)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local MAX_LATENCY_MS = 1000
local MAX_SPAWN = 5

local log = Logger.new("DevService")

local AvatarService: any
local CombatService: any
local EntityService: any
local InventoryService: any
local ProgressionService: any
local SpawnService: any
local StatService: any

local limiter = RateLimiter.new(5, 2)

--[=[
	Server-gated dev commands (scope 01, section 7) as TextChatCommands, plus the damage log
	streamed to dev clients. Allowed in Studio or for allowlisted UserIds; everyone else is refused.
]=]
local DevService = {}

--[=[ True when a player may use dev tools. ]=]
function DevService.IsDev(player: Player): boolean
	return RunService:IsStudio() or table.find(DevAllowlist, player.UserId) ~= nil
end

local function reply(player: Player, text: string)
	NetServer.Fire("Notify", player, "DevDone", { text })
end

local function devPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("IsDev") then
			table.insert(list, player)
		end
	end
	return list
end

local function spawnPosition(player: Player): Vector3
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pads = CollectionService:GetTagged("DevSpawnPad")
	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		return root.Position + Vector3.new(look.X, 0, look.Z).Unit * 14 - Vector3.new(0, 2.8, 0)
	elseif #pads > 0 and pads[1]:IsA("BasePart") then
		return pads[1].Position
	end
	return Vector3.zero
end

type Handler = (player: Player, args: { string }) -> string

local commands: { [string]: Handler } = {
	level = function(player, args)
		local level = tonumber(args[1])
		if not level then
			return "Usage: /level <1-5>"
		end
		ProgressionService.SetLevel(player, level)
		return `Level set to {math.floor(level)}`
	end,
	xp = function(player, args)
		local amount = tonumber(args[1])
		if not amount or amount <= 0 then
			return "Usage: /xp <amount>"
		end
		ProgressionService.GrantXp(player, math.floor(amount))
		return `Granted {math.floor(amount)} XP`
	end,
	newchar = function(player, args)
		local classId = args[1] and string.lower(args[1])
		if classId and not Classes.ById[classId] then
			return "Usage: /newchar [fighter|mage|healer]"
		end
		local ok, reason = AvatarService.CreateDefault(player, classId)
		return if ok then "Created a default character" else `Cannot create: {reason}`
	end,
	class = function(player, args)
		local action, classId = args[1], args[2] and string.lower(args[2])
		if not classId or not Classes.ById[classId] then
			return "Usage: /class add|remove fighter|mage|healer"
		end
		if action == "add" then
			local ok, reason = ProgressionService.TrainClass(player, classId)
			return if ok then `Trained {classId}` else `Cannot train: {reason}`
		elseif action == "remove" then
			ProgressionService.RemoveClass(player, classId)
			return `Removed {classId}`
		end
		return "Usage: /class add|remove <class>"
	end,
	proficiency = function(player, args)
		local family = args[1] and string.lower(args[1]) or ""
		local ok, reason = ProgressionService.SetProficiency(player, family)
		return if ok then `Weapon Proficiency set to {family}` else `Usage: /proficiency sword|bow ({reason})`
	end,
	spawn = function(player, args)
		local enemyId = args[1] and string.lower(args[1])
		local def = enemyId and NpcDefs.Get(enemyId)
		if not enemyId or not def then
			local ids = {}
			for _, source in { Enemies.ById, Npcs.ById } do
				for id in source do
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			return "Usage: /spawn <npc> [level] [count]. NPCs: " .. table.concat(ids, ", ")
		end
		local level = math.clamp(math.floor(tonumber(args[2]) or def.levelMin), 1, 20)
		local count = math.clamp(math.floor(tonumber(args[3]) or 1), 1, MAX_SPAWN)
		local origin = spawnPosition(player)
		for i = 1, count do
			SpawnService.DevSpawn(enemyId, level, origin + Vector3.new((i - 1) * 4, 0, 0))
		end
		return `Spawned {count} {enemyId} at level {level}`
	end,
	clear = function()
		return `Cleared {SpawnService.ClearDevSpawned()} dev spawns`
	end,
	god = function(player)
		local entity = EntityService.ForPlayer(player)
		if not entity then
			return "No character"
		end
		entity.god = not entity.god
		entity.model:SetAttribute("God", entity.god)
		return if entity.god then "God mode on" else "God mode off"
	end,
	heal = function(player)
		local entity = EntityService.ForPlayer(player)
		if entity then
			StatService.Refill(entity)
		end
		return "Refilled"
	end,
	latency = function(player, args)
		if not RunService:IsStudio() then
			return "Simulated latency is Studio-only"
		end
		local ms = math.clamp(math.floor(tonumber(args[1]) or 0), 0, MAX_LATENCY_MS)
		player:SetAttribute("SimLatencyMs", ms)
		return `Simulated latency {ms} ms`
	end,
	give = function(player, args)
		local itemId = args[1] and string.lower(args[1])
		if not itemId or not Items.ById[itemId] then
			return "Usage: /give <item> [count]"
		end
		local count = math.clamp(math.floor(tonumber(args[2]) or 1), 1, 50)
		local leftover = InventoryService.Grant(player, itemId, count)
		return `Gave {count - leftover} {itemId}`
	end,
	damage = function(player, args)
		local amount = tonumber(args[1])
		local entity = EntityService.ForPlayer(player)
		if not amount or amount <= 0 or not entity then
			return "Usage: /damage <amount> (hits the nearest enemy within 40 studs)"
		end
		local nearest, nearestDistance = nil, 40
		for _, other in EntityService.All() do
			if other.alive and other.kind == "Npc" then
				local distance = (other.root.Position - entity.root.Position).Magnitude
				if distance < nearestDistance then
					nearest, nearestDistance = other, distance
				end
			end
		end
		if not nearest then
			return "No enemy within 40 studs"
		end
		CombatService.DealTick(nearest, math.floor(amount), "mental", entity)
		return `Dealt {math.floor(amount)} to {nearest.name}`
	end,
	kill = function(player)
		local entity = EntityService.ForPlayer(player)
		if entity then
			CombatService.Kill(entity, nil)
		end
		return "Killed"
	end,
}

local function run(player: Player, message: string): string?
	if not DevService.IsDev(player) then
		NetServer.Fire("Notify", player, "DevOnly", {})
		log:Throttled(`refused:{player.UserId}`, 10, "warn", "Refused dev command from %d", player.UserId)
		return nil
	end
	if not limiter:Allow(player) then
		return nil
	end
	local words = string.split(message, " ")
	local name = string.lower(string.sub(table.remove(words, 1) or "", 2))
	local args = {}
	for _, word in words do
		if word ~= "" then
			table.insert(args, word)
		end
	end
	local handler = commands[name]
	if not handler then
		return nil
	end
	local ok, result = pcall(handler, player, args)
	reply(player, if ok then result else "Command failed")
	if not ok then
		log:Warn("Dev command /%s failed: %s", name, tostring(result))
		return nil
	end
	return result
end

local function onTriggered(textSource: TextSource, message: string)
	local player = Players:GetPlayerByUserId(textSource.UserId)
	if player then
		run(player, message)
	end
end

-- Studio-only test hook: lets Studio tooling run the same commands without chat. Server-side,
-- so clients cannot reach it.
local function createStudioHook()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "RunDevCommand"
	hook.OnInvoke = function(player: Player, message: string): string?
		return run(player, message)
	end
	hook.Parent = ServerStorage
end

local function createCommands()
	local folder = Instance.new("Folder")
	folder.Name = "DevCommands"
	for name in commands do
		local command = Instance.new("TextChatCommand")
		command.Name = "Dev_" .. name
		command.PrimaryAlias = "/" .. name
		command.Triggered:Connect(onTriggered)
		command.Parent = folder
	end
	folder.Parent = TextChatService
end

function DevService.Init(deps: { [string]: any })
	AvatarService = deps.AvatarService
	CombatService = deps.CombatService
	EntityService = deps.EntityService
	InventoryService = deps.InventoryService
	ProgressionService = deps.ProgressionService
	SpawnService = deps.SpawnService
	StatService = deps.StatService
end

function DevService.Start()
	createCommands()
	createStudioHook()

	local function onPlayerAdded(player: Player)
		player:SetAttribute("IsDev", DevService.IsDev(player))
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		limiter:Forget(player)
	end)

	CombatService.Damaged:Connect(
		function(target: Entity, amount: number, damageType: string, source: Entity?, crit: boolean, skillId: string?)
			local line = string.format(
				"%s -> %s: %d %s%s (%s) hp %d/%d",
				if source then source.name else "?",
				target.name,
				amount,
				damageType,
				if crit then " CRIT" else "",
				skillId or "tick",
				target.hp,
				target.stats.MaxHp
			)
			for _, player in devPlayers() do
				NetServer.Fire("SendDevLog", player, line)
			end
		end
	)
end

return DevService
