--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Quests = require(ReplicatedStorage.Content.Quests)
local Theme = require(ReplicatedStorage.Shared.Theme)

--[=[
	Quest board panel (docs/systems/economy.md): the guild hall's board lists the extermination
	quests; the server spawns the party on Accept and pays on Turn in.
]=]
local QuestController = {}

local UIController: any
local ProfileController: any

local bound: { [string]: GuiObject }
local board: BasePart? = nil

local function fire(action: string, questId: string)
	if board then
		NetClient.Fire("QuestAction", board, action, questId)
	end
end

local function dim(button: TextButton, on: boolean)
	button.AutoButtonColor = on
	button.BackgroundColor3 = if on then Theme.Gold else Theme.GoldDim
end

local function render()
	if not board then
		return
	end
	local snapshot = ProfileController.Get()
	local active = snapshot and snapshot.quest
	local activeDef = active and Quests.ById[active.id]
	if activeDef then
		UIController.SetText(
			bound.Bind_Status,
			string.format("Active: %s (%d/%d)", activeDef.name, active.kills, activeDef.count)
		)
	else
		UIController.SetText(bound.Bind_Status, "No active quest. Take one from the board.")
	end
	dim(bound.Bind_Turn :: TextButton, activeDef ~= nil and active.kills >= activeDef.count)
	dim(bound.Bind_Abandon :: TextButton, activeDef ~= nil)

	UIController.ClearRows(bound.Bind_List)
	for index, quest in Quests.List do
		local row = UIController.Clone("ListRow") :: Frame
		local parts = UIController.Bind(row, { "Bind_Title", "Bind_Detail", "Bind_Action" })
		UIController.SetText(parts.Bind_Title, quest.name)
		UIController.SetText(
			parts.Bind_Detail,
			string.format("%s Reward: %d gold, %d XP.", quest.description, quest.reward.gold, quest.reward.xp)
		)
		row.Size = UDim2.new(1, 0, 0, 74)
		local action = parts.Bind_Action :: TextButton
		action.Text = "Accept"
		dim(action, activeDef == nil)
		action.Activated:Connect(function()
			fire("Accept", quest.id)
		end)
		row.LayoutOrder = index
		row.Parent = bound.Bind_List
	end
end

local function open(body: Instance)
	if not body:IsA("BasePart") then
		return
	end
	board = body
	render()
	UIController.Close("QuestBoard")
	UIController.Open("QuestBoard", body)
end

function QuestController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
end

function QuestController.Start()
	local screen = UIController.GetScreen("QuestBoard")
	bound = UIController.Bind(screen, {
		"Bind_Title",
		"Bind_Close",
		"Bind_Status",
		"Bind_List",
		"Bind_Turn",
		"Bind_Abandon",
	})
	UIController.BindClose("QuestBoard")
	local turn = bound.Bind_Turn :: TextButton
	local abandon = bound.Bind_Abandon :: TextButton
	turn.Activated:Connect(function()
		fire("Turn", "")
	end)
	abandon.Activated:Connect(function()
		fire("Abandon", "")
	end)
	ProfileController.Changed:Connect(function()
		if screen.Enabled then
			render()
		end
	end)
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "QuestBoard" and not isOpen then
			board = nil
		end
	end)
	NetClient.Connect("OpenQuestBoard", open)
end

return QuestController
