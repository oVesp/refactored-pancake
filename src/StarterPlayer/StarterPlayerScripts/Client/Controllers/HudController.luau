--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Disciplines = require(ReplicatedStorage.Content.Disciplines)
local Hotbar = require(ReplicatedStorage.Shared.Hotbar)
local Maid = require(ReplicatedStorage.Shared.Maid)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Skills = require(ReplicatedStorage.Content.Skills)
local Statuses = require(ReplicatedStorage.Content.Statuses)
local Strings = require(ReplicatedStorage.Content.Strings)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Tuning = require(ReplicatedStorage.Content.Tuning)
local Zones = require(ReplicatedStorage.Content.Zones)

local Attributes = Constants.Attributes
-- Cast fill tint once the slidecast window opens (moving no longer cancels).
local SLIDECAST_COLOR = Theme.Green
local TARGET_ATTRIBUTES = { Attributes.Hp, Attributes.MaxHp, "Level", "DisplayName", "Elite", "Casting" }
local TOAST_SECONDS = 4
local MAX_TOASTS = 5
local KEY_LABELS = { "1", "2", "3", "4", "5", "6", "7", "8" }
-- Background transparency of an empty hotbar slot (shown only while the spellbook is open).
local EMPTY_SLOT_TRANSPARENCY = 0.55

local REJECT_TEXT: { [string]: string } = {
	Resource = "Not enough resource",
	Cooldown = "Not ready",
	Disabled = "You cannot act",
	Busy = "Already casting",
	Sheathed = "Weapon sheathed",
	Dodge = "Cannot dodge",
	NoTarget = "No target",
	Range = "Out of range",
	Summon = "SummonUnavailable",
}

--[=[
	View model for the HUD: pools, XP, level, zone, hotbar with cooldowns, statuses, cast bar and
	toasts. Reads replicated attributes and the profile snapshot; never writes authoritative state.
]=]
local HudController = {}

local UIController: any
local ProfileController: any
local CombatController: any
local TargetController: any
local DragController: any
local CameraController: any

local player = Players.LocalPlayer
local characterMaid = Maid.new()
local targetMaid = Maid.new()
local bound: { [string]: GuiObject }
local slotFrames: { { frame: Frame, cooldown: Frame, id: string, kind: string } } = {}
local castEndsAt = 0
local castStartedAt = 0
local castFillColor: Color3? = nil
local editingHotbar = false
local hotbarFilled = false

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
			local fade = TweenInfo.new(0.4)
			for _, part in toast:GetDescendants() do
				if part:IsA("UIStroke") then
					TweenService:Create(part, fade, { Transparency = 1 }):Play()
				elseif part:IsA("Frame") then
					TweenService:Create(part, fade, { BackgroundTransparency = 1 }):Play()
				end
			end
			local tween = TweenService:Create(toast, fade, { TextTransparency = 1, BackgroundTransparency = 1 })
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

local function renderNeeds()
	for _, kind in { "Hunger", "Thirst" } do
		local value = player:GetAttribute(Attributes[kind])
		local shown = if type(value) == "number" then value else Tuning.Needs.Max
		local barFill = bound[`Bind_{kind}Fill`]
		fill(barFill, bound[`Bind_{kind}Text`], shown, Tuning.Needs.Max, "%d")
		barFill.BackgroundColor3 = if shown < Tuning.Needs.Max * Tuning.Needs.LowThreshold
			then Theme.HpBright
			else Theme.Gold
	end
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
		local edge = chip:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = if def and def.harmful then Theme.HpBright else Theme.Green
		end
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

local function renderTarget(model: Model?, locked: boolean)
	targetMaid:Clean()
	bound.Bind_TargetFrame.Visible = model ~= nil
	if not model then
		return
	end
	local target = model
	local function render()
		local name = target:GetAttribute("DisplayName") or target.Name
		local level = target:GetAttribute("Level")
		local elite = if target:GetAttribute("Elite") == true then "  \u{2605}" else ""
		setText("Bind_TargetName", string.format("Lv %s  %s%s", tostring(level or "?"), tostring(name), elite))
		local hp = target:GetAttribute(Attributes.Hp)
		local maxHp = target:GetAttribute(Attributes.MaxHp)
		if type(hp) == "number" and type(maxHp) == "number" then
			fill(bound.Bind_TargetHpFill, bound.Bind_TargetHpText, hp, maxHp)
		end
		local casting = target:GetAttribute("Casting")
		local info = {}
		if locked then
			table.insert(info, "Locked")
		end
		if type(casting) == "string" then
			table.insert(info, "Casting " .. casting)
		end
		setText("Bind_TargetInfo", table.concat(info, " \u{00b7} "))
	end
	for _, name in TARGET_ATTRIBUTES do
		targetMaid:Give(target:GetAttributeChangedSignal(name):Connect(render))
	end
	render()
end

local function renderProfile(snapshot: { [string]: any })
	setText("Bind_NameText", if snapshot.name ~= "" then snapshot.name else player.DisplayName)
	setText("Bind_LevelText", tostring(snapshot.level))
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
	bound.Bind_HintPanel.Visible = #hints > 0
end

local function renderZone()
	local id = player:GetAttribute("Zone")
	local zone = if type(id) == "string" then Zones.ById[id] else nil
	setText(
		"Bind_ZoneText",
		if zone then string.format("%s · %s (%s)", Zones.Realm, zone.name, zone.band) else Zones.Realm
	)
end

local function updateHotbarVisible()
	bound.Bind_Hotbar.Visible = hotbarFilled or editingHotbar
end

local function renderHotbar(slots: { [number]: any })
	UIController.ClearRows(bound.Bind_Hotbar)
	table.clear(slotFrames)
	local targets: { [number]: GuiObject } = {}
	hotbarFilled = false
	for index = 1, Hotbar.Size do
		local slot = slots[index]
		local frame = UIController.Clone("HotbarSlot") :: Frame
		frame.LayoutOrder = index
		-- Active makes the slot sink clicks so tapping it does not also fire the light attack.
		frame.Active = true
		targets[index] = frame
		local parts = UIController.Bind(frame, { "Bind_Name", "Bind_Key", "Bind_Cost", "Bind_Cooldown" })
		UIController.SetText(parts.Bind_Key, KEY_LABELS[index] or "")
		if not slot then
			UIController.SetText(parts.Bind_Name, "")
			UIController.SetText(parts.Bind_Cost, "")
			frame.BackgroundTransparency = EMPTY_SLOT_TRANSPARENCY
			frame.Parent = bound.Bind_Hotbar
			continue
		end
		hotbarFilled = true
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
		UIController.SetText(parts.Bind_Cost, cost)
		frame.InputBegan:Connect(function(input)
			if
				input.UserInputType ~= Enum.UserInputType.Touch
				and input.UserInputType ~= Enum.UserInputType.MouseButton1
			then
				return
			end
			-- While the spellbook is open the bar is being arranged: presses drag instead of cast.
			if editingHotbar then
				DragController.Begin(input, { kind = slot.kind, id = slot.id }, name, index)
			else
				CombatController.ActivateSlot(index)
				-- Tracked on the input so letting go off the slot still shoots a draw.
				local released: RBXScriptConnection
				released = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						released:Disconnect()
						CombatController.ReleaseSlot(index)
					elseif input.UserInputState == Enum.UserInputState.Cancel then
						released:Disconnect()
						CombatController.CancelDraw()
					end
				end)
			end
		end)
		frame.Parent = bound.Bind_Hotbar
		table.insert(
			slotFrames,
			{ frame = frame, cooldown = parts.Bind_Cooldown :: Frame, id = slot.id, kind = slot.kind }
		)
	end
	DragController.SetTargets(targets)
	updateHotbarVisible()
end

local function updateCooldowns()
	local character = player.Character
	local active = if character then character:GetAttribute("Statuses") else nil
	for _, slot in slotFrames do
		if slot.kind == "Skill" then
			local remaining, total = CombatController.Cooldown(slot.id)
			slot.cooldown.Size = UDim2.fromScale(1, if total > 0 then math.clamp(remaining / total, 0, 1) else 0)
		else
			local def = Disciplines.ById[slot.id]
			local on = type(active) == "string" and table.find(string.split(active, ","), def.status) ~= nil
			slot.cooldown.Size = UDim2.fromScale(1, 0)
			slot.frame.BackgroundColor3 = if on then Theme.GreenDeep else Theme.PanelRaised
		end
	end

	local castBar = bound.Bind_CastBar
	local now = os.clock()
	if now < castEndsAt then
		local castFill = bound.Bind_CastFill
		castFillColor = castFillColor or castFill.BackgroundColor3
		castBar.Visible = true
		castFill.Size = UDim2.fromScale((now - castStartedAt) / math.max(castEndsAt - castStartedAt, 1e-3), 1)
		castFill.BackgroundColor3 = if castEndsAt - now <= Tuning.Combat.Gcd.SlidecastWindow
			then SLIDECAST_COLOR
			else castFillColor :: Color3
	else
		castBar.Visible = false
	end
end

function HudController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
	CombatController = deps.CombatController
	TargetController = deps.TargetController
	DragController = deps.DragController
	CameraController = deps.CameraController
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
		"Bind_HungerFill",
		"Bind_HungerText",
		"Bind_ThirstFill",
		"Bind_ThirstText",
		"Bind_FocusText",
		"Bind_NameText",
		"Bind_LevelText",
		"Bind_ZoneText",
		"Bind_HintPanel",
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
		"Bind_TargetFrame",
		"Bind_TargetName",
		"Bind_TargetHpFill",
		"Bind_TargetHpText",
		"Bind_TargetInfo",
		"Bind_CombatMode",
	})
	local modeLabel = bound.Bind_CombatMode :: TextLabel
	local exploreColor = modeLabel.TextColor3
	local function renderMode(inCombat: boolean)
		modeLabel.Text = if inCombat then "Combat mode" else "Exploration"
		modeLabel.TextColor3 = if inCombat then Theme.Gold else exploreColor
	end
	CameraController.Changed:Connect(renderMode)
	renderMode(CameraController.InCombat())
	setText("Bind_NameText", player.DisplayName)
	TargetController.Changed:Connect(renderTarget)
	renderTarget(TargetController.Enemy(), TargetController.IsLocked())

	player:GetAttributeChangedSignal(Attributes.Hunger):Connect(renderNeeds)
	player:GetAttributeChangedSignal(Attributes.Thirst):Connect(renderNeeds)
	renderNeeds()
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
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "Spellbook" then
			editingHotbar = isOpen
			updateHotbarVisible()
		end
	end)
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
