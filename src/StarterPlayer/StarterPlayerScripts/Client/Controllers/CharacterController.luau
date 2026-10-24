--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Content.Classes)
local Disciplines = require(ReplicatedStorage.Content.Disciplines)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Skills = require(ReplicatedStorage.Content.Skills)

--[=[
	Character sheet: build path (class order and levels), the nine stats from replicated
	attributes, granted actives/passives and known Disciplines.
]=]
local CharacterController = {}

local UIController: any
local ProfileController: any

local bound: { [string]: GuiObject }

local function render()
	local snapshot = ProfileController.Get()
	local character = Players.LocalPlayer.Character
	if not snapshot then
		return
	end

	local path = {}
	for _, entry in snapshot.classes do
		table.insert(path, string.format("%s %d", Classes.ById[entry.id].name, entry.level))
	end
	UIController.SetText(
		bound.Bind_Build,
		string.format(
			"Level %d · Human · Build: %s%s",
			snapshot.level,
			if #path > 0 then table.concat(path, " > ") else "no class yet",
			if snapshot.unspent > 0 then string.format("  (%d unspent)", snapshot.unspent) else ""
		)
	)

	local stats = {}
	for _, name in Formulas.StatNames do
		local value = if character then character:GetAttribute("Stat_" .. name) else nil
		table.insert(stats, string.format("%-11s %4s", name, tostring(value or "-")))
	end
	UIController.SetText(bound.Bind_Stats, table.concat(stats, "\n"))

	local skills = {}
	for _, skillId in snapshot.granted do
		local skill = Skills.ById[skillId]
		table.insert(skills, string.format("%s (%s): %s", skill.name, skill.kind, skill.description))
	end
	for _, id in snapshot.disciplines do
		local def = Disciplines.ById[id]
		if def then
			table.insert(skills, string.format("%s (Discipline): %s", def.name, def.description))
		end
	end
	UIController.SetText(bound.Bind_Skills, if #skills > 0 then table.concat(skills, "\n") else "No skills yet.")
end

function CharacterController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
end

function CharacterController.Start()
	local screen = UIController.GetScreen("CharacterSheet")
	bound = UIController.Bind(screen, { "Bind_Build", "Bind_Stats", "Bind_Skills", "Bind_Close" })
	UIController.BindClose("CharacterSheet")
	ProfileController.Changed:Connect(function()
		if screen.Enabled then
			render()
		end
	end)
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "CharacterSheet" and isOpen then
			render()
		end
	end)
end

return CharacterController
