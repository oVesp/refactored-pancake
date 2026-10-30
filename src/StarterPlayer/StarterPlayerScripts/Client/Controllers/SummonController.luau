--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Shared.Maid)
local NpcDefs = require(ReplicatedStorage.Shared.NpcDefs)
local Tuning = require(ReplicatedStorage.Content.Tuning)

--[=[
	The summon picker (docs/systems/ai-and-spawning.md, Summons): pressing a summon skill with more
	than one option opens it, with the last choice marked. Choosing an option casts it; pressing the
	skill again casts the marked one. The server validates the choice.
]=]
local SummonController = {}

local CombatController: any
local UIController: any

local screen: ScreenGui
local bound: { [string]: GuiObject }
local rows = Maid.new()
local openSkill: string? = nil
local openToken = 0
-- Last choice per skill this session.
local lastChoice: { [string]: string } = {}

local function close()
	openSkill = nil
	openToken += 1
	screen.Enabled = false
	rows:Clean()
	UIController.ClearRows(bound.Bind_Options)
end

local function cast(skillId: string, id: string)
	lastChoice[skillId] = id
	close()
	CombatController.UseSkill(skillId, id)
end

local function open(skillId: string, options: { string })
	close()
	local marked = lastChoice[skillId]
	if not marked or not table.find(options, marked) then
		marked = options[1]
	end
	for order, id in options do
		local def = NpcDefs.Get(id)
		local option = UIController.Clone("SummonOption") :: TextButton
		option.LayoutOrder = order
		option.Text = if def then def.name else id
		local stroke = option:FindFirstChild("Bind_Stroke") :: UIStroke
		stroke.Enabled = id == marked
		rows:Give(option.Activated:Connect(function()
			cast(skillId, id)
		end))
		option.Parent = bound.Bind_Options
	end
	openSkill = skillId
	screen.Enabled = true
	local token = openToken
	task.delay(Tuning.Summons.PickerSeconds, function()
		if token == openToken then
			close()
		end
	end)
end

local function onPrompt(skillId: string, options: { string })
	if openSkill == skillId then
		local marked = lastChoice[skillId]
		cast(skillId, if marked and table.find(options, marked) then marked else options[1])
	else
		open(skillId, options)
	end
end

function SummonController.Init(deps: { [string]: any })
	CombatController = deps.CombatController
	UIController = deps.UIController
end

function SummonController.Start()
	screen = UIController.GetScreen("SummonPicker")
	bound = UIController.Bind(screen, { "Bind_Options" })
	CombatController.SummonPrompted:Connect(onPrompt)
end

return SummonController
