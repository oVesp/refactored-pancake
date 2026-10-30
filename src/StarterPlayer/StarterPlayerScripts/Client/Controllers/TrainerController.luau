--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Content.Classes)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)

--[=[
	Trainer panel (docs/art/ui-style.md, Floating UI): a trainer's prompt opens the Trainer
	screen in the world beside the trainer. The panel says what the trainer offers; its button
	asks the server, which validates range and runs the training.
]=]
local TrainerController = {}

local UIController: any
local ProfileController: any

local bound: { [string]: GuiObject }
local trainer: BasePart? = nil

local function classLevel(snapshot: { [string]: any }?, classId: string): number
	for _, entry in (snapshot and snapshot.classes or {}) :: { any } do
		if entry.id == classId then
			return entry.level
		end
	end
	return 0
end

local function render()
	local body = trainer
	if not body then
		return
	end
	local snapshot = ProfileController.Get()
	local prompt = body:FindFirstChildOfClass("ProximityPrompt")
	local kind = body:GetAttribute("TrainerType")
	local primary = bound.Bind_Primary :: TextButton
	UIController.SetText(bound.Bind_Title, string.upper(if prompt then prompt.ObjectText else body.Name))
	primary.Visible = true
	if kind == "Class" then
		local classId = body:GetAttribute("ClassId")
		local class = if type(classId) == "string" then Classes.ById[classId] else nil
		local unspent = snapshot and snapshot.unspent or 0
		local name = if class then class.name else "this class"
		local level = if type(classId) == "string" then classLevel(snapshot, classId) else 0
		UIController.SetText(
			bound.Bind_Info,
			string.format(
				"Train %s to level %d.\nTraining spends one unspent level. You have %d.",
				name,
				level + 1,
				unspent
			)
		)
		primary.Text = string.format("Train %s", name)
	elseif kind == "Discipline" then
		UIController.SetText(bound.Bind_Info, "Learn every Discipline taught here.")
		primary.Text = "Learn Disciplines"
	end
end

local function open(body: Instance)
	if not body:IsA("BasePart") then
		return
	end
	trainer = body
	render()
	UIController.Close("Trainer")
	UIController.Open("Trainer", body)
end

function TrainerController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
end

function TrainerController.Start()
	local screen = UIController.GetScreen("Trainer")
	bound = UIController.Bind(screen, { "Bind_Title", "Bind_Info", "Bind_Primary", "Bind_Close" })
	UIController.BindClose("Trainer")
	local primary = bound.Bind_Primary :: TextButton
	primary.Activated:Connect(function()
		if trainer then
			NetClient.Fire("RequestTrain", trainer)
		end
	end)
	ProfileController.Changed:Connect(function()
		if screen.Enabled then
			render()
		end
	end)
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "Trainer" and not isOpen then
			trainer = nil
		end
	end)
	NetClient.Connect("OpenTrainer", open)
end

return TrainerController
