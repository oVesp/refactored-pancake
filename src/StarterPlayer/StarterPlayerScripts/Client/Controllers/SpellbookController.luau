--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Classes = require(ReplicatedStorage.Content.Classes)
local Disciplines = require(ReplicatedStorage.Content.Disciplines)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Hotbar = require(ReplicatedStorage.Shared.Hotbar)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Skills = require(ReplicatedStorage.Content.Skills)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Tuning = require(ReplicatedStorage.Content.Tuning)

local PAGE_SIZE = 16
-- Class filter value for Disciplines, which belong to no class.
local GENERAL = "General"

local REASON_TEXT: { [string]: string } = {
	CircleLocked = "Your Circle is too low",
	NoPick = "No spell pick left",
	NotOnClassList = "Not on your classes' lists",
}

type Tab = "Spells" | "Techniques"
type Status = "All" | "Known" | "Learnable" | "Locked"
type State = "Known" | "Learnable" | "Locked"

local STATUSES: { Status } = { "All", "Known", "Learnable", "Locked" }

type Entry = {
	kind: "Skill" | "Discipline",
	id: string,
	number: number,
	name: string,
	--[=[ Owning class id, or `GENERAL` for Disciplines. ]=]
	group: string,
	--[=[ Class level that grants a class skill. ]=]
	grantLevel: number?,
}

--[=[
	Spellbook (docs/systems/progression.md, Spellbook): numbered pages of every spell and
	technique, a detail pane, learning and the hotbar loadout. Unknown entries show as silhouettes.
	Learning sends `LearnSpell`; placing sends `SetHotbarSlot` (assign buttons or a drag through
	DragController). The server re-checks both.
]=]
local SpellbookController = {}

local UIController: any
local ProfileController: any
local DragController: any

local bound: { [string]: GuiObject }
local assignButtons: { TextButton } = {}
local spellList: { Entry } = {}
local techniqueList: { Entry } = {}

local snapshot: { [string]: any }? = nil
local tab: Tab = "Spells"
local status: Status = "All"
local group = "All"
local page = 1
local selected: Entry? = nil
local isOpen = false

local function buildLists()
	local spellGroup: { [string]: string } = {}
	for _, classId in Classes.Order do
		for _, spellId in Classes.ById[classId].spellList do
			spellGroup[spellId] = spellGroup[spellId] or classId
		end
	end
	for id, skill in Skills.ById do
		if skill.source == "Spell" then
			table.insert(spellList, {
				kind = "Skill",
				id = id,
				number = skill.number :: number,
				name = skill.name,
				group = spellGroup[id] or GENERAL,
			})
		end
	end
	table.sort(spellList, function(a, b)
		return a.number < b.number
	end)

	for _, classId in Classes.Order do
		for level, skillId in Classes.ById[classId].grants do
			local skill = Skills.ById[skillId]
			if skill.kind == "Active" then
				table.insert(techniqueList, {
					kind = "Skill",
					id = skillId,
					number = #techniqueList + 1,
					name = skill.name,
					group = classId,
					grantLevel = level,
				})
			end
		end
	end
	for _, id in Disciplines.Order do
		table.insert(techniqueList, {
			kind = "Discipline",
			id = id,
			number = #techniqueList + 1,
			name = Disciplines.ById[id].name,
			group = GENERAL,
		})
	end
end

local function groupName(id: string): string
	local class = Classes.ById[id]
	return if class then class.name else id
end

local function stateOf(entry: Entry): (State, string?)
	local snap = snapshot :: { [string]: any }
	if entry.kind == "Discipline" then
		if table.find(snap.disciplines, entry.id) then
			return "Known", nil
		end
		return "Locked", "Taught by the Discipline trainer"
	end
	if entry.grantLevel then
		if table.find(snap.granted, entry.id) then
			return "Known", nil
		end
		return "Locked", string.format("Reach %s level %d", groupName(entry.group), entry.grantLevel)
	end
	if table.find(snap.spells, entry.id) then
		return "Known", nil
	end
	local ok, reason =
		Formulas.CanLearnSpell(snap.classes, snap.spells, entry.id, Classes.ById, Skills.ById, Tuning.Magic)
	if ok then
		return "Learnable", nil
	end
	return "Locked", REASON_TEXT[reason or ""] or "Locked"
end

local function slotOf(entry: Entry): number?
	local snap = snapshot :: { [string]: any }
	return table.find(snap.hotbar, Hotbar.Encode(entry.kind, entry.id))
end

local function currentList(): { Entry }
	return if tab == "Spells" then spellList else techniqueList
end

local function visibleEntries(): { Entry }
	local out = {}
	for _, entry in currentList() do
		if group ~= "All" and entry.group ~= group then
			continue
		end
		if status ~= "All" and stateOf(entry) ~= status then
			continue
		end
		table.insert(out, entry)
	end
	return out
end

local function groupOptions(): { string }
	local options = { "All" }
	for _, entry in currentList() do
		if not table.find(options, entry.group) then
			table.insert(options, entry.group)
		end
	end
	return options
end

local function styleToggle(button: GuiObject, on: boolean)
	local text = button :: TextButton
	text.BackgroundColor3 = if on then Theme.Gold else Theme.PanelRaised
	text.TextColor3 = if on then Theme.Ink else Theme.Gold
end

local function statLines(entry: Entry): string
	if entry.kind == "Discipline" then
		local def = Disciplines.ById[entry.id]
		return string.format(
			"Focus     %d\nMode      %s\nDuration  %.0fs\nRecast    %.0fs",
			def.cost,
			def.mode,
			def.duration,
			def.cooldown
		)
	end
	local skill = Skills.ById[entry.id]
	local cost = if skill.cost
		then string.format("%d %s", skill.cost.amount, if skill.cost.resource == "Mp" then "MP" else "Stamina")
		else "Free"
	local cast = if skill.castTime then string.format("%.1fs", skill.castTime) else "Instant"
	local recast = if skill.gcd
		then (if skill.cooldown then string.format("%.0fs + GCD", skill.cooldown) else "GCD")
		else (if skill.cooldown then string.format("%.0fs", skill.cooldown) else "None")
	local lines = {
		"Cost      " .. cost,
		"Cast      " .. cast,
		"Recast    " .. recast,
	}
	if skill.range then
		table.insert(lines, string.format("Range     %d", skill.range))
	end
	return table.concat(lines, "\n")
end

local function renderDetail()
	local entry = selected
	bound.Bind_Learn.Visible = false
	bound.Bind_AssignPanel.Visible = false
	if not entry then
		for _, name in { "Bind_DetailNumber", "Bind_DetailName", "Bind_DetailSub", "Bind_DetailStats" } do
			UIController.SetText(bound[name], "")
		end
		UIController.SetText(bound.Bind_DetailDesc, "Nothing matches these filters.")
		UIController.SetText(bound.Bind_DetailStatus, "")
		return
	end

	local state, reason = stateOf(entry)
	local hidden = state == "Locked"
	UIController.SetText(bound.Bind_DetailNumber, string.format("No. %03d", entry.number))

	local sub
	if entry.kind == "Discipline" then
		sub = "Discipline"
	elseif entry.grantLevel then
		sub = string.format("%s skill · level %d", groupName(entry.group), entry.grantLevel)
	else
		sub = string.format("Circle %d · %s", Skills.ById[entry.id].circle or 0, groupName(entry.group))
	end
	UIController.SetText(bound.Bind_DetailSub, sub)

	if hidden then
		UIController.SetText(bound.Bind_DetailName, "???")
		UIController.SetText(bound.Bind_DetailStats, "")
		UIController.SetText(bound.Bind_DetailDesc, "Not yet known.")
	else
		UIController.SetText(bound.Bind_DetailName, entry.name)
		UIController.SetText(bound.Bind_DetailStats, statLines(entry))
		local description = if entry.kind == "Discipline"
			then Disciplines.ById[entry.id].description
			else Skills.ById[entry.id].description
		UIController.SetText(bound.Bind_DetailDesc, description)
	end

	local statusLabel = bound.Bind_DetailStatus :: TextLabel
	local slot = slotOf(entry)
	if state == "Known" then
		statusLabel.Text = if slot then string.format("Known · on hotbar slot %d", slot) else "Known"
		statusLabel.TextColor3 = Theme.Gold
		bound.Bind_AssignPanel.Visible = true
		for index, button in assignButtons do
			styleToggle(button, index == slot)
		end
	elseif state == "Learnable" then
		statusLabel.Text = "Ready to learn"
		statusLabel.TextColor3 = Theme.Green
		bound.Bind_Learn.Visible = true
	else
		statusLabel.Text = reason or "Locked"
		statusLabel.TextColor3 = Theme.Dim
	end
end

local function selectEntry(entry: Entry?)
	selected = entry
	for _, cell in bound.Bind_Grid:GetChildren() do
		local mark = cell:FindFirstChild("Bind_Selected")
		if mark and mark:IsA("GuiObject") then
			mark.Visible = entry ~= nil and cell:GetAttribute("EntryNumber") == entry.number
		end
	end
	renderDetail()
end

local function renderSummary()
	local snap = snapshot :: { [string]: any }
	local parts = {}
	for _, classId in Classes.Order do
		local class = Classes.ById[classId]
		local ceiling = class.line and snap.ceilings[class.line]
		if ceiling then
			table.insert(
				parts,
				string.format("%s: Circle %d, %d pick(s)", class.name, ceiling, snap.picks[classId] or 0)
			)
		end
	end
	local summary = if #parts == 0
		then "No casting line yet. Train Mage or Healer to learn spells."
		else table.concat(parts, "   ·   ")
	UIController.SetText(bound.Bind_Summary, summary)
end

local function addCell(entry: Entry, order: number)
	local state = stateOf(entry)
	local hidden = state == "Locked"
	local cell = UIController.Clone("SpellCell") :: TextButton
	cell.LayoutOrder = order
	cell:SetAttribute("EntryNumber", entry.number)
	local parts =
		UIController.Bind(cell, { "Bind_Number", "Bind_Name", "Bind_Tag", "Bind_Slot", "Bind_Shade", "Bind_Selected" })
	UIController.SetText(parts.Bind_Number, string.format("%03d", entry.number))
	local name = parts.Bind_Name :: TextLabel
	name.Text = if hidden then "?" else entry.name
	name.TextColor3 = if state == "Learnable" then Theme.Green elseif hidden then Theme.Dim else Theme.Text
	local tag = if entry.kind == "Discipline"
		then "Discipline"
		elseif entry.grantLevel then string.format("%s %d", groupName(entry.group), entry.grantLevel)
		else string.format("Circle %d", Skills.ById[entry.id].circle or 0)
	UIController.SetText(parts.Bind_Tag, tag)
	local slot = if state == "Known" then slotOf(entry) else nil
	parts.Bind_Slot.Visible = slot ~= nil
	UIController.SetText(parts.Bind_Slot, if slot then tostring(slot) else "")
	parts.Bind_Shade.Visible = hidden
	parts.Bind_Selected.Visible = selected ~= nil and selected.number == entry.number

	cell.Activated:Connect(function()
		selectEntry(entry)
	end)
	if state == "Known" then
		cell.InputBegan:Connect(function(input: InputObject)
			DragController.Begin(input, { kind = entry.kind, id = entry.id }, entry.name, nil)
		end)
	end
	cell.Parent = bound.Bind_Grid
end

local function render()
	if not snapshot then
		return
	end
	renderSummary()
	styleToggle(bound.Bind_TabSpells, tab == "Spells")
	styleToggle(bound.Bind_TabTechniques, tab == "Techniques")
	styleToggle(bound.Bind_FilterAll, status == "All")
	styleToggle(bound.Bind_FilterKnown, status == "Known")
	styleToggle(bound.Bind_FilterLearnable, status == "Learnable")
	styleToggle(bound.Bind_FilterLocked, status == "Locked")
	UIController.SetText(bound.Bind_ClassFilter, if group == "All" then "All classes" else groupName(group))

	local entries = visibleEntries()
	local pages = math.max(1, math.ceil(#entries / PAGE_SIZE))
	page = math.clamp(page, 1, pages)
	UIController.SetText(bound.Bind_PageText, string.format("Page %d / %d", page, pages))
	bound.Bind_PrevPage.Visible = page > 1
	bound.Bind_NextPage.Visible = page < pages

	-- Keep the selection when it is still listed; otherwise select the first entry on the page.
	local first = (page - 1) * PAGE_SIZE + 1
	local keep = false
	UIController.ClearRows(bound.Bind_Grid)
	for index = first, math.min(first + PAGE_SIZE - 1, #entries) do
		local entry = entries[index]
		if selected and selected.kind == entry.kind and selected.id == entry.id then
			selected = entry
			keep = true
		end
		addCell(entry, index)
	end
	selectEntry(if keep then selected else entries[first])
end

local function setView(change: () -> ())
	change()
	page = 1
	render()
end

local function connect(name: string, handler: () -> ())
	local button = bound[name]
	assert(button:IsA("GuiButton"), `Spellbook.{name} must be a button`)
	button.Activated:Connect(handler)
end

function SpellbookController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
	DragController = deps.DragController
end

function SpellbookController.Start()
	buildLists()
	local screen = UIController.GetScreen("Spellbook")
	local names = {
		"Bind_Summary",
		"Bind_Grid",
		"Bind_PageText",
		"Bind_PrevPage",
		"Bind_NextPage",
		"Bind_TabSpells",
		"Bind_TabTechniques",
		"Bind_FilterAll",
		"Bind_FilterKnown",
		"Bind_FilterLearnable",
		"Bind_FilterLocked",
		"Bind_ClassFilter",
		"Bind_DetailNumber",
		"Bind_DetailName",
		"Bind_DetailSub",
		"Bind_DetailStats",
		"Bind_DetailDesc",
		"Bind_DetailStatus",
		"Bind_Learn",
		"Bind_AssignPanel",
		"Bind_Close",
	}
	for index = 1, Hotbar.Size do
		table.insert(names, `Bind_Assign{index}`)
	end
	bound = UIController.Bind(screen, names)
	UIController.BindClose("Spellbook")

	for index = 1, Hotbar.Size do
		local button = bound[`Bind_Assign{index}`] :: TextButton
		assignButtons[index] = button
		button.Activated:Connect(function()
			local entry = selected
			if not entry or not snapshot or stateOf(entry) ~= "Known" then
				return
			end
			-- Pressing the slot the entry already sits in takes it off the bar.
			if slotOf(entry) == index then
				NetClient.Fire("SetHotbarSlot", index, "", "")
			else
				NetClient.Fire("SetHotbarSlot", index, entry.kind, entry.id)
			end
		end)
	end
	connect("Bind_Learn", function()
		if selected and snapshot and stateOf(selected) == "Learnable" then
			NetClient.Fire("LearnSpell", selected.id)
		end
	end)
	connect("Bind_TabSpells", function()
		setView(function()
			tab, group = "Spells", "All"
		end)
	end)
	connect("Bind_TabTechniques", function()
		setView(function()
			tab, group = "Techniques", "All"
		end)
	end)
	for _, value: Status in STATUSES do
		connect(`Bind_Filter{value}`, function()
			setView(function()
				status = value
			end)
		end)
	end
	connect("Bind_ClassFilter", function()
		setView(function()
			local options = groupOptions()
			group = options[(table.find(options, group) or 1) % #options + 1]
		end)
	end)
	connect("Bind_PrevPage", function()
		page -= 1
		render()
	end)
	connect("Bind_NextPage", function()
		page += 1
		render()
	end)

	ProfileController.Changed:Connect(function(newSnapshot)
		snapshot = newSnapshot
		if isOpen then
			render()
		end
	end)
	UIController.ModalChanged:Connect(function(name: string, open: boolean)
		if name ~= "Spellbook" then
			return
		end
		isOpen = open
		if open then
			snapshot = ProfileController.Get()
			render()
		end
	end)
end

return SpellbookController
