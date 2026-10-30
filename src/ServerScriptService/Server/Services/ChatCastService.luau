--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ChatCast = require(ReplicatedStorage.Shared.ChatCast)
local DevService = require(script.Parent.DevService)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Skills = require(ReplicatedStorage.Content.Skills)

local DataService: any
local SkillService: any

--[=[
	Chat casting (docs/systems/combat.md): a chat message that is exactly the name of a spell the
	player knows casts it through the `UseSkill` path, and is not delivered as chat. Anything else
	stays ordinary chat; `/` commands never match.
]=]
local ChatCastService = {}

local function knownFor(player: Player): { string }?
	local profile = DataService.Get(player)
	return if profile then SkillService.KnownActives(profile, DevService.IsDev(player)) else nil
end

--[=[ The skill and argument a player's chat message casts, or nil for ordinary chat. ]=]
function ChatCastService.Resolve(player: Player, text: string): (string?, string?)
	local known = knownFor(player)
	if not known then
		return nil, nil
	end
	return ChatCast.Resolve(text, known, Skills.ById)
end

local function handleCast(player: Player, text: string, aim: Vector3, seq: number, target: Model?)
	local skillId, arg = ChatCastService.Resolve(player, text)
	if not skillId then
		NetServer.Fire("RejectSkill", player, seq, "Unknown")
		return
	end
	SkillService.Use(player, skillId, aim, seq, target, arg)
end

-- Runs once per recipient; it only decides delivery; the sender's client sends the cast.
local function shouldDeliver(message: TextChatMessage, _recipient: TextSource): boolean
	local source = message.TextSource
	local player = source and Players:GetPlayerByUserId(source.UserId)
	return not (player and ChatCastService.Resolve(player, message.Text))
end

local function hookChannel(instance: Instance)
	if instance:IsA("TextChannel") then
		(instance :: any).ShouldDeliverCallback = shouldDeliver
	end
end

function ChatCastService.Init(deps: { [string]: any })
	DataService = deps.DataService
	SkillService = deps.SkillService

	NetServer.Connect(
		"CastSpellByName",
		function(player: Player, text: string, aim: Vector3, seq: number, target: Model?)
			handleCast(player, text, aim, seq, target)
		end
	)
end

function ChatCastService.Start()
	TextChatService.DescendantAdded:Connect(hookChannel)
	for _, instance in TextChatService:GetDescendants() do
		hookChannel(instance)
	end
end

return ChatCastService
