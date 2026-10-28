--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Appearance = require(ReplicatedStorage.Content.Appearance)
local Assets = require(ReplicatedStorage.Content.Assets)
local Avatar = require(ReplicatedStorage.Shared.Avatar)
local Classes = require(ReplicatedStorage.Content.Classes)
local Heritages = require(ReplicatedStorage.Content.Heritages)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Names = require(ReplicatedStorage.Content.Names)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Skills = require(ReplicatedStorage.Content.Skills)
local Strings = require(ReplicatedStorage.Content.Strings)
local Theme = require(ReplicatedStorage.Shared.Theme)

--[=[
	Character creator (docs/systems/character-creation.md). Opens, locked, while the profile has
	no created character. The preview is a client-only model built from the same
	HumanoidDescription the server will spawn, standing on the creation stage; the server only
	sees the final submission and validates it.
]=]
local CreatorController = {}

local UIController: any
local ProfileController: any

local log = Logger.new("CreatorController")
local player = Players.LocalPlayer

local STEPS = { "Race", "Body", "Hair", "Facial", "Outfit", "Class", "Spells" }
local STEP_TITLES = {
	Race = "RACE",
	Body = "BODY",
	Hair = "HAIR",
	Facial = "FACIAL HAIR",
	Outfit = "OUTFIT",
	Class = "STARTING CLASS",
	Spells = "STARTING SPELL",
}
local HEAD_STEPS = { Hair = true, Facial = true }
local CAMERA_MOVE = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TURN_SPEED = 0.012
local CAMERA_STEP = "CreatorCamera"
local LINE_NAMES = { arcane = "Arcane", divine = "Divine", spiritual = "Spiritual", alternative = "Alternative" }
local STAT_LABELS = {
	MaxHp = "HP",
	MaxMp = "MP",
	PhysAtk = "Physical Attack",
	PhysDef = "Physical Defense",
	Agility = "Agility",
	MagAtk = "Magic Attack",
	MagDef = "Magic Defense",
	Resistance = "Resistance",
	Special = "Special",
}

type Option = {
	id: string,
	label: string,
	detail: string,
	selected: boolean,
	locked: boolean,
}

type Detail = {
	title: string,
	subtitle: string,
	body: string,
}

local screen: ScreenGui
local bound: { [string]: GuiObject }
local isOpen = false
local step = "Race"
local creation: Avatar.Creation
local nameIndex = 1
-- The entry shown in the detail pane per step (a locked race can be inspected but not chosen).
local inspected: { [string]: string } = {}

local stage: Model? = nil
local preview: Model? = nil
local previewToken = 0
local yaw = 0
local dragging = false
local submitting = false

local function names(): { string }
	return (Names :: any)[creation.gender]
end

local function isCaster(): boolean
	return #Avatar.StarterSpells(creation.classId) > 0
end

local function stagePart(name: string): BasePart?
	local found = stage and stage:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

-- Preview -----------------------------------------------------------------------------------

local function placePreview()
	local model = preview
	local pedestal = stagePart("Pedestal")
	if not model or not pedestal then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local top = pedestal.Position.Y + pedestal.Size.X / 2
	local at = Vector3.new(pedestal.Position.X, top + humanoid.HipHeight + root.Size.Y / 2, pedestal.Position.Z)
	-- Turned half way so the character faces +Z, toward the camera.
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, math.pi + yaw, 0))
end

local function playIdle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local animation = Instance.new("Animation")
	animation.AnimationId = Assets.Stock.PreviewIdle
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok and track then
		track.Looped = true
		track:Play(0)
	end
end

-- Builds the preview on a thread; a newer request makes an older result drop itself.
local function refreshPreview()
	previewToken += 1
	local token = previewToken
	local look = Avatar.LookOf(creation)
	task.spawn(function()
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Avatar.Build(look), Enum.HumanoidRigType.R15)
		end)
		if not ok then
			log:Warn("Preview failed: %s", tostring(model))
			return
		end
		if token ~= previewToken or not isOpen then
			model:Destroy()
			return
		end
		local animate = model:FindFirstChild("Animate")
		if animate then
			animate:Destroy()
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = true
		end
		model.Name = "CreatorPreview"
		if preview then
			preview:Destroy()
		end
		preview = model
		placePreview()
		model.Parent = workspace
		playIdle(model)
	end)
end

local function frameCamera(instant: boolean)
	local framing = if HEAD_STEPS[step] then "Head" else "Full"
	local eye = stagePart("Camera" .. framing)
	local focus = stagePart("Focus" .. framing)
	if not eye or not focus then
		return
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local goal = CFrame.lookAt(eye.Position, focus.Position)
	if instant then
		camera.CFrame = goal
	else
		TweenService:Create(camera, CAMERA_MOVE, { CFrame = goal }):Play()
	end
end

-- Options and detail --------------------------------------------------------------------------

local function classDetail(classId: string): Detail
	local def = Classes.ById[classId]
	local growth = {}
	for stat, amount in def.growth do
		table.insert(growth, `{STAT_LABELS[stat] or stat} +{amount}`)
	end
	table.sort(growth)
	local grants = {}
	for level, skillId in def.grants do
		local skill = Skills.ById[skillId]
		table.insert(grants, `Lv {level}: {skill.name} ({string.lower(skill.kind)})`)
	end
	local lines = {
		`<b>Per level:</b> {table.concat(growth, ", ")}`,
		"",
		`<b>Class skills:</b>`,
		table.concat(grants, "\n"),
	}
	if def.line then
		table.insert(lines, "")
		table.insert(lines, "Learns one spell per level from its list. You pick the first one next.")
	end
	return {
		title = def.name,
		subtitle = if def.line then `{LINE_NAMES[def.line] or def.line} caster` else "Martial",
		body = table.concat(lines, "\n"),
	}
end

local function spellDetail(spellId: string): Detail
	local skill = Skills.ById[spellId]
	local facts = {}
	if skill.cost then
		table.insert(facts, `{skill.cost.amount} {if skill.cost.resource == "Mp" then "MP" else skill.cost.resource}`)
	end
	table.insert(facts, if skill.castTime then `{skill.castTime} s cast` else "Instant")
	if skill.damage then
		table.insert(facts, `{skill.damage.type} damage`)
	elseif skill.heal then
		table.insert(facts, "Heals")
	end
	return {
		title = skill.name,
		subtitle = `Tier {skill.tier or 0} · {table.concat(facts, " · ")}`,
		body = (skill :: any).description or "",
	}
end

local function stepOptions(): { Option }
	local options: { Option } = {}
	local function add(id: string, label: string, detail: string, selected: boolean, locked: boolean?)
		table.insert(options, { id = id, label = label, detail = detail, selected = selected, locked = locked == true })
	end
	if step == "Race" then
		for _, id in Heritages.Order do
			local def = Heritages.ById[id]
			add(id, def.name, if def.playable then def.family else "Locked", creation.heritage == id, not def.playable)
		end
	elseif step == "Body" then
		for _, id in Appearance.Genders.Order do
			add(id, Appearance.Genders.ById[id].name, "", creation.gender == id)
		end
	elseif step == "Hair" then
		for _, id in Appearance.Hair.Order do
			add(id, Appearance.Hair.ById[id].name, "", creation.hair == id)
		end
	elseif step == "Facial" then
		for _, id in Appearance.FacialHair.Order do
			add(id, Appearance.FacialHair.ById[id].name, "", creation.facialHair == id)
		end
	elseif step == "Outfit" then
		for _, id in Appearance.Outfits.Order do
			add(id, Appearance.Outfits.ById[id].name, "", creation.outfit == id)
		end
	elseif step == "Class" then
		for _, id in Classes.Order do
			local def = Classes.ById[id]
			add(id, def.name, if def.line then LINE_NAMES[def.line] or def.line else "Martial", creation.classId == id)
		end
	elseif step == "Spells" then
		for _, id in Avatar.StarterSpells(creation.classId) do
			local skill = Skills.ById[id]
			add(id, skill.name, `Tier {skill.tier or 0}`, creation.spellId == id)
		end
	end
	return options
end

local function detailFor(id: string): Detail
	if step == "Race" then
		local def = Heritages.ById[id]
		return {
			title = def.name,
			subtitle = if def.playable then `{def.family} heritage` else `{def.family} heritage · not yet available`,
			body = def.description,
		}
	elseif step == "Body" then
		return {
			title = Appearance.Genders.ById[id].name,
			subtitle = "Body",
			body = `Sets the face and build. Every hair style, beard and outfit fits both.\n\nSkin tone: {Appearance.SkinTones.ById[creation.skinTone].name}.`,
		}
	elseif step == "Hair" or step == "Facial" then
		local list = if step == "Hair" then Appearance.Hair else Appearance.FacialHair
		return {
			title = list.ById[id].name,
			subtitle = `{Appearance.HairColors.ById[creation.hairColor].name} hair`,
			body = "The hair colour below applies to both hair and beard.",
		}
	elseif step == "Outfit" then
		return {
			title = Appearance.Outfits.ById[id].name,
			subtitle = "Starting clothes",
			body = "Shirt and trousers worn under any armour you find later.",
		}
	elseif step == "Class" then
		return classDetail(id)
	end
	return spellDetail(id)
end

local function selectedId(): string
	if step == "Race" then
		return creation.heritage
	elseif step == "Body" then
		return creation.gender
	elseif step == "Hair" then
		return creation.hair
	elseif step == "Facial" then
		return creation.facialHair
	elseif step == "Outfit" then
		return creation.outfit
	elseif step == "Class" then
		return creation.classId
	end
	return creation.spellId
end

local render: () -> ()

local function pick(id: string, locked: boolean)
	inspected[step] = id
	if locked then
		render()
		return
	end
	local looks = false
	if step == "Race" then
		creation.heritage = id
	elseif step == "Body" then
		creation.gender = id
		local list = names()
		creation.name = list[math.clamp(nameIndex, 1, #list)]
		looks = true
	elseif step == "Hair" then
		creation.hair = id
		looks = true
	elseif step == "Facial" then
		creation.facialHair = id
		looks = true
	elseif step == "Outfit" then
		creation.outfit = id
		looks = true
	elseif step == "Class" then
		if creation.classId ~= id then
			creation.classId = id
			creation.spellId = Avatar.StarterSpells(id)[1] or ""
		end
	elseif step == "Spells" then
		creation.spellId = id
	end
	if looks then
		refreshPreview()
	end
	render()
end

local function setStep(name: string)
	step = name
	inspected[name] = nil
	frameCamera(false)
	render()
end

local function setName(index: number)
	local list = names()
	nameIndex = (index - 1) % #list + 1
	creation.name = list[nameIndex]
	UIController.SetText(bound.Bind_Name, creation.name)
end

-- Body shows skin tones; Hair and Facial Hair show the shared hair colour.
local function renderSwatches()
	local skin = step == "Body"
	local field = if skin then "skinTone" else "hairColor"
	local container = bound.Bind_Swatches
	UIController.SetText(bound.Bind_SwatchLabel, if skin then "SKIN TONE" else "HAIR COLOUR")
	UIController.ClearRows(container)
	local order = if skin then Appearance.SkinTones.Order else Appearance.HairColors.Order
	for index, id in order do
		local swatch = UIController.Clone("CreatorSwatch") :: TextButton
		swatch.Name = id
		swatch.LayoutOrder = index
		swatch.BackgroundColor3 = if skin
			then Appearance.SkinTones.ById[id].color
			else Appearance.HairColors.ById[id].swatch
		local stroke = swatch:FindFirstChild("Bind_Stroke") :: UIStroke
		local chosen = (creation :: any)[field] == id
		stroke.Color = if chosen then Theme.GoldBright else Theme.GoldDim
		stroke.Thickness = if chosen then 3 else 2
		swatch.Activated:Connect(function()
			(creation :: any)[field] = id
			refreshPreview()
			render()
		end)
		swatch.Parent = container
	end
end

render = function()
	if not isCaster() and step == "Spells" then
		step = "Class"
	end
	for _, name in STEPS do
		local button = bound[`Bind_Step{name}`] :: TextButton
		button.Visible = name ~= "Spells" or isCaster()
		local active = name == step
		button.BackgroundColor3 = if active then Theme.Gold else Theme.PanelRaised
		button.TextColor3 = if active then Theme.Ink else Theme.Gold
	end
	UIController.SetText(bound.Bind_ListTitle, STEP_TITLES[step])

	local list = bound.Bind_Options
	UIController.ClearRows(list)
	for order, option in stepOptions() do
		local row = UIController.Clone("CreatorOption") :: TextButton
		row.Name = option.id
		row.LayoutOrder = order
		local parts = UIController.Bind(row, { "Bind_Label", "Bind_Detail" })
		UIController.SetText(parts.Bind_Label, option.label)
		UIController.SetText(parts.Bind_Detail, option.detail)
		local labelText = parts.Bind_Label :: TextLabel
		labelText.TextColor3 = if option.locked
			then Theme.Dim
			elseif option.selected then Theme.GoldBright
			else Theme.Text
		local stroke = row:FindFirstChild("Bind_Stroke") :: UIStroke
		stroke.Color = if option.selected then Theme.Gold else Theme.GoldDim
		stroke.Thickness = if option.selected then 2 else 1
		row.Activated:Connect(function()
			pick(option.id, option.locked)
		end)
		row.Parent = list
	end

	local showSwatches = HEAD_STEPS[step] == true or step == "Body"
	bound.Bind_SwatchPanel.Visible = showSwatches
	if showSwatches then
		renderSwatches()
	end

	local detail = detailFor(inspected[step] or selectedId())
	UIController.SetText(bound.Bind_DetailTitle, detail.title)
	UIController.SetText(bound.Bind_DetailSubtitle, detail.subtitle)
	UIController.SetText(bound.Bind_DetailBody, detail.body)
	UIController.SetText(bound.Bind_Name, creation.name)
end

-- Open and close ------------------------------------------------------------------------------

local function hud(enabled: boolean)
	local hudScreen = player:WaitForChild("PlayerGui"):FindFirstChild("Hud")
	if hudScreen and hudScreen:IsA("ScreenGui") then
		hudScreen.Enabled = enabled
	end
end

local function open()
	if isOpen then
		return
	end
	isOpen = true
	submitting = false
	creation = Avatar.DefaultCreation()
	nameIndex = 1
	step = "Race"
	inspected = {}
	yaw = 0
	hud(false)
	UIController.SetText(bound.Bind_Status, "")
	UIController.Open("Creator")
	UIController.SetLocked("Creator")
	task.spawn(function()
		local pedestal = CollectionService:GetTagged("CreatorStage")[1]
			or CollectionService:GetInstanceAddedSignal("CreatorStage"):Wait()
		stage = pedestal.Parent :: Model
		if isOpen then
			frameCamera(true)
			refreshPreview()
			-- The default camera takes the camera back whenever a character spawns; keep it on the stage.
			RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, function()
				if workspace.CurrentCamera.CameraType ~= Enum.CameraType.Scriptable then
					frameCamera(true)
				end
			end)
		end
	end)
	render()
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	previewToken += 1
	if preview then
		preview:Destroy()
		preview = nil
	end
	RunService:UnbindFromRenderStep(CAMERA_STEP)
	UIController.SetLocked(nil)
	UIController.Close("Creator")
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	hud(true)
end

local function submit()
	if submitting then
		return
	end
	submitting = true
	UIController.SetText(bound.Bind_Status, "Entering Midgard…")
	NetClient.Fire("CreateCharacter", table.clone(creation))
	task.delay(3, function()
		submitting = false
	end)
end

function CreatorController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
end

function CreatorController.Start()
	screen = UIController.GetScreen("Creator")
	local bindings = {
		"Bind_Steps",
		"Bind_ListTitle",
		"Bind_Options",
		"Bind_SwatchPanel",
		"Bind_SwatchLabel",
		"Bind_Swatches",
		"Bind_DetailTitle",
		"Bind_DetailSubtitle",
		"Bind_DetailBody",
		"Bind_Turntable",
		"Bind_Name",
		"Bind_NamePrev",
		"Bind_NameNext",
		"Bind_NameRandom",
		"Bind_Confirm",
		"Bind_Status",
	}
	for _, name in STEPS do
		table.insert(bindings, `Bind_Step{name}`)
	end
	bound = UIController.Bind(screen, bindings)

	for _, name in STEPS do
		(bound[`Bind_Step{name}`] :: TextButton).Activated:Connect(function()
			setStep(name)
		end)
	end
	(bound.Bind_NamePrev :: TextButton).Activated:Connect(function()
		setName(nameIndex - 1)
	end);
	(bound.Bind_NameNext :: TextButton).Activated:Connect(function()
		setName(nameIndex + 1)
	end);
	(bound.Bind_NameRandom :: TextButton).Activated:Connect(function()
		setName(math.random(1, #names()))
	end);
	(bound.Bind_Confirm :: TextButton).Activated:Connect(submit)

	bound.Bind_Turntable.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if dragging and (kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch) then
			yaw += input.Delta.X * TURN_SPEED
			placePreview()
		end
	end)

	NetClient.Connect("Notify", function(key: string)
		if isOpen then
			submitting = false
			UIController.SetText(bound.Bind_Status, (Strings :: any)[key] or key)
		end
	end)
	ProfileController.Changed:Connect(function(snapshot: { [string]: any })
		if snapshot.created then
			close()
		else
			open()
		end
	end)
	local snapshot = ProfileController.Get()
	if snapshot and not snapshot.created then
		open()
	end
end

return CreatorController
