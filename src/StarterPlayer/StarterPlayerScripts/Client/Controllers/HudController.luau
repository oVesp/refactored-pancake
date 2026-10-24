--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Disciplines = require(ReplicatedStorage.Content.Disciplines)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Skills = require(ReplicatedStorage.Content.Skills)
local Statuses = require(ReplicatedStorage.Content.Statuses)
local Strings = require(ReplicatedStorage.Content.Strings)
local Zones = require(ReplicatedStorage.Content.Zones)

local Attributes = Constants.Attributes
local TOAST_SECONDS = 4
local MAX_TOASTS = 5
local KEY_LABELS = { "1", "2", "3", "4", "5", "6", "7", "8" }

local REJECT_TEXT: { [string]: string } = {
	Resource = "Not enough resource",
	Cooldown = "Not ready",
	Disabled = "You cannot act",
	Busy = "Already casting",
	Dodge = "Cannot dodge",
}

--[=[
	View model for the HUD: pools, XP, level, zone, hotbar with cooldowns, statuses, cast bar and
	toasts. Reads replicated attributes and the profile snapshot; never writes authoritative state.
]=]
local HudController = {}

local UIController: any
local ProfileController: any
local CombatController: any

local player = Players.LocalPlayer
local characterMaid = Maid.new()
local bound: { [string]: GuiObject }
local slotFrames: { { frame: Frame, cooldown: Frame, id: string, kind: string } } = {}
local castEndsAt = 0
local castStartedAt = 0

local function fill(barFill: GuiObject, text: GuiObject, value: number, max: number, format: string?)
	local ratio = if max > 0 then math.clamp(value / max, 0, 1) else 0
	barFill.Size = UDim2.fromScale(ratio, 1)
	if text:IsA("TextLabel") then
		text.Text = string.format(format or "%d / %d", math.floor(value + 0.5), math.floor(max + 0.5))
	end
end

local function setText(name: string, value: string)
	local label = bound[name]
	if label:IsA("TextLabel") then
		label.Text = value
	end
end

--[=[ Shows a toast built from a Strings key and arguments. ]=]
function HudController.Toast(key: string, args: { any }?)
	local template = Strings[key] or key
	local ok, text = pcall(string.format, template, table.unpack(args or {}))
	local toast = UIController.Clone("Toast") :: TextLabel
	toast.Text = if ok then text else template
	toast.Parent = bound.Bind_Toasts
	local rows = {}
	for _, child in bound.Bind_Toasts:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(rows, child)
		end
	end
	if #rows > MAX_TOASTS then
		rows[1]:Destroy()
	end
	task.delay(TOAST_SECONDS, function()
		if toast.Parent then
			local tween =
				TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			toast:Destroy()
		end
	end)
end

local function renderPools(character: Model)
	local function num(name: string): number
		local value = character:GetAttribute(name)
		return if type(value) == "number" then value else 0
	end
	local shield = num("Shield")
	fill(bound.Bind_HpFill, bound.Bind_HpText, num(Attributes.Hp), num(Attributes.MaxHp))
	if shield > 0 then
		setText("Bind_HpText", string.format("%d / %d  (+%d)", num(Attributes.Hp), num(Attributes.MaxHp), shield))
	end
	fill(bound.Bind_MpFill, bound.Bind_MpText, num(Attributes.Mp), num(Attributes.MaxMp))
	fill(bound.Bind_StaminaFill, bound.Bind_StaminaText, num("Stamina"), num("MaxStamina"))
	setText("Bind_FocusText", string.format("Focus %d / %d", num(Attributes.Focus), num(Attributes.MaxFocus)))
end

local function renderStatuses(character: Model)
	UIController.ClearRows(bound.Bind_Statuses)
	local raw = character:GetAttribute("Statuses")
	if type(raw) ~= "string" or raw == "" then
		return
	end
	for _, id in string.split(raw, ",") do
		local def = Statuses.ById[id]
		local chip = UIController.Clone("StatusChip") :: TextLabel
		chip.Text = if def then def.name else id
		chip.BackgroundColor3 = if def and def.harmful then Color3.fromRGB(110, 35, 35) else Color3.fromRGB(35, 80, 50)
		chip.Parent = bound.Bind_Statuses
	end
end

local function watchCharacter(character: Model)
	characterMaid:Clean()
	for _, name in
		{
			Attributes.Hp,
			Attributes.MaxHp,
			Attributes.Mp,
			Attributes.MaxMp,
			"Stamina",
			"MaxStamina",
			Attributes.Focus,
			Attributes.MaxFocus,
			"Shield",
		}
	do
		characterMaid:Give(character:GetAttributeChangedSignal(name):Connect(function()
			renderPools(character)
		end))
	end
	characterMaid:Give(character:GetAttributeChangedSignal("Statuses"):Connect(function()
		renderStatuses(character)
	end))
	renderPools(character)
	renderStatuses(character)
end

local function renderProfile(snapshot: { [string]: any })
	setText("Bind_LevelText", string.format("Level %d", snapshot.level))
	if snapshot.xpNeed then
		fill(bound.Bind_XpFill, bound.Bind_XpText, snapshot.xpInto, snapshot.xpNeed, "XP %d / %d")
	else
		fill(bound.Bind_XpFill, bound.Bind_XpText, 1, 1, "Level cap")
	end
	if snapshot.xpDebt > 0 then
		setText(
			"Bind_XpText",
			string.format("XP %d / %s  (debt %d)", snapshot.xpInto, tostring(snapshot.xpNeed or "-"), snapshot.xpDebt)
		)
	end

	local hints = {}
	if snapshot.unspent > 0 then
		table.insert(hints, string.format("%d unspent level(s): visit a class trainer", snapshot.unspent))
	end
	local picks = 0
	for _, count in snapshot.picks do
		picks += count
	end
	if picks > 0 then
		table.insert(hints, string.format("%d spell pick(s): press B", picks))
	end
	setText("Bind_HintText", table.concat(hints, "\n"))
end

local function renderZone()
	local id = player:GetAttribute("Zone")
	local zone = if type(id) == "string" then Zones.ById[id] else nil
	setText(
		"Bind_ZoneText",
		if zone then string.format("%s · %s (%s)", Zones.Realm, zone.name, zone.band) else Zones.Realm
	)
end

local function renderHotbar(slots: { any })
	UIController.ClearRows(bound.Bind_Hotbar)
	table.clear(slotFrames)
	for index, slot in slots do
		local frame = UIController.Clone("HotbarSlot") :: Frame
		frame.LayoutOrder = index
		local parts = UIController.Bind(frame, { "Bind_Name", "Bind_Key", "Bind_Cost", "Bind_Cooldown" })
		local name, cost = slot.id, ""
		if slot.kind == "Skill" then
			local skill = Skills.ById[slot.id]
			name = skill.name
			if skill.cost then
				cost = string.format("%d %s", skill.cost.amount, if skill.cost.resource == "Mp" then "MP" else "ST")
			end
		else
			local def = Disciplines.ById[slot.id]
			name = def.name
			cost = string.format("%d Focus", def.cost)
		end
		UIController.SetText(parts.Bind_Name, name)
		UIController.SetText(parts.Bind_Key, KEY_LABELS[index] or "")
		UIController.SetText(parts.Bind_Cost, cost)
		frame.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				CombatController.ActivateSlot(index)
			end
		end)
		frame.Parent = bound.Bind_Hotbar
		table.insert(
			slotFrames,
			{ frame = frame, cooldown = parts.Bind_Cooldown :: Frame, id = slot.id, kind = slot.kind }
		)
	end
end

local function updateCooldowns()
	local character = player.Character
	local active = if character then character:GetAttribute("Statuses") else nil
	for _, slot in slotFrames do
		if slot.kind == "Skill" then
			local skill = Skills.ById[slot.id]
			local remaining = CombatController.Remaining(slot.id)
			local total = skill.cooldown or 1
			slot.cooldown.Size = UDim2.fromScale(1, if total > 0 then math.clamp(remaining / total, 0, 1) else 0)
		else
			local def = Disciplines.ById[slot.id]
			local on = type(active) == "string" and table.find(string.split(active, ","), def.status) ~= nil
			slot.cooldown.Size = UDim2.fromScale(1, 0)
			slot.frame.BackgroundColor3 = if on then Color3.fromRGB(60, 90, 50) else Color3.fromRGB(18, 18, 23)
		end
	end

	local castBar = bound.Bind_CastBar
	local now = os.clock()
	if now < castEndsAt then
		castBar.Visible = true
		bound.Bind_CastFill.Size =
			UDim2.fromScale((now - castStartedAt) / math.max(castEndsAt - castStartedAt, 1e-3), 1)
	else
		castBar.Visible = false
	end
end

function HudController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
	CombatController = deps.CombatController
end

function HudController.Start()
	local screen = UIController.GetScreen("Hud")
	bound = UIController.Bind(screen, {
		"Bind_HpFill",
		"Bind_HpText",
		"Bind_MpFill",
		"Bind_MpText",
		"Bind_StaminaFill",
		"Bind_StaminaText",
		"Bind_FocusText",
		"Bind_LevelText",
		"Bind_ZoneText",
		"Bind_HintText",
		"Bind_Statuses",
		"Bind_Hotbar",
		"Bind_XpFill",
		"Bind_XpText",
		"Bind_CastBar",
		"Bind_CastFill",
		"Bind_CastText",
		"Bind_Toasts",
		"Bind_KeysText",
	})

	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	player:GetAttributeChangedSignal("Zone"):Connect(renderZone)
	renderZone()

	ProfileController.Changed:Connect(renderProfile)
	local snapshot = ProfileController.Get()
	if snapshot then
		renderProfile(snapshot)
	end
	CombatController.HotbarChanged:Connect(renderHotbar)
	renderHotbar(CombatController.Hotbar())
	CombatController.Rejected:Connect(function(_skillId: string, reason: string)
		if REJECT_TEXT[reason] then
			HudController.Toast(REJECT_TEXT[reason])
		end
	end)

	NetClient.Connect("Notify", function(key: string, args: { any })
		HudController.Toast(key, args)
	end)
	NetClient.Connect("ShowCast", function(info: { [string]: any })
		if info.caster ~= player.Character then
			return
		end
		if info.kind == "Cast" or info.kind == "Telegraph" then
			castStartedAt = os.clock()
			castEndsAt = castStartedAt + info.duration
			local skill = Skills.ById[info.skillId]
			setText("Bind_CastText", if skill then skill.name else "")
		elseif info.kind == "Interrupted" then
			castEndsAt = 0
		end
	end)

	RunService.RenderStepped:Connect(updateCooldowns)
end

return HudController
