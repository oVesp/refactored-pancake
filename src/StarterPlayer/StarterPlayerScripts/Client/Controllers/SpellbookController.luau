--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Content.Classes)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Skills = require(ReplicatedStorage.Content.Skills)
local Tuning = require(ReplicatedStorage.Content.Tuning)

local REASON_TEXT: { [string]: string } = {
	CircleLocked = "Circle locked",
	NoPick = "No pick",
	NotOnClassList = "Not your class",
	AlreadyKnown = "Known",
}

--[=[
	Spellbook screen: every spell of the player's caster classes with its Circle and whether it
	can be learned now. Learning sends `LearnSpell`; the server re-checks everything.
]=]
local SpellbookController = {}

local UIController: any
local ProfileController: any

local bound: { [string]: GuiObject }

local function render(snapshot: { [string]: any }?)
	if not snapshot then
		return
	end
	UIController.ClearRows(bound.Bind_List)

	local lines = {}
	for line, ceiling in snapshot.ceilings do
		table.insert(lines, string.format("%s line: Circle %d", line, ceiling))
	end
	local picks = {}
	for classId, count in snapshot.picks do
		table.insert(picks, string.format("%s %d", Classes.ById[classId].name, count))
	end
	local summary = if #lines == 0
		then "No casting line yet. Train Mage or Healer to learn spells."
		else table.concat(lines, " · ") .. "\nPicks left: " .. table.concat(picks, ", ")
	UIController.SetText(bound.Bind_Summary, summary)

	local order = 0
	for _, classId in Classes.Order do
		local class = Classes.ById[classId]
		if Formulas.ClassLevel(snapshot.classes, classId) == 0 or #class.spellList == 0 then
			continue
		end
		for _, spellId in class.spellList do
			local spell = Skills.ById[spellId]
			local ok, reason = Formulas.CanLearnSpell(
				snapshot.classes,
				snapshot.spells,
				spellId,
				Classes.ById,
				Skills.ById,
				Tuning.Magic
			)
			order += 1
			local row = UIController.Clone("ListRow") :: Frame
			row.LayoutOrder = order
			local parts = UIController.Bind(row, { "Bind_Title", "Bind_Detail", "Bind_Action" })
			UIController.SetText(
				parts.Bind_Title,
				string.format("%s  ·  Circle %d  ·  %s", spell.name, spell.circle or 0, class.name)
			)
			local cost = if spell.cost then string.format("%d MP", spell.cost.amount) else "free"
			UIController.SetText(
				parts.Bind_Detail,
				string.format("%s (%s, %.1fs cd)", spell.description, cost, spell.cooldown or 0)
			)
			local action = parts.Bind_Action :: TextButton
			if ok then
				action.Text = "Learn"
				action.Activated:Connect(function()
					NetClient.Fire("LearnSpell", spellId)
				end)
			else
				action.Text = REASON_TEXT[reason or ""] or "Locked"
				action.AutoButtonColor = false
				action.BackgroundTransparency = 0.6
			end
			row.Parent = bound.Bind_List
		end
	end
end

function SpellbookController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
end

function SpellbookController.Start()
	local screen = UIController.GetScreen("Spellbook")
	bound = UIController.Bind(screen, { "Bind_Summary", "Bind_List", "Bind_Close" })
	UIController.BindClose("Spellbook")
	ProfileController.Changed:Connect(function(snapshot)
		if screen.Enabled then
			render(snapshot)
		end
	end)
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "Spellbook" and isOpen then
			render(ProfileController.Get())
		end
	end)
end

return SpellbookController
