--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Content.Items)
local Logger = require(ReplicatedStorage.Shared.Logger)
local Weapons = require(ReplicatedStorage.Content.Weapons)
local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity

local log = Logger.new("LoadoutService")

local EntityService: any

--[=[
	Shows what a player holds (docs/systems/weapons.md): clones the weapon and shield models from
	ReplicatedStorage.Weapons whenever its `Weapon`, `Shield` or `Drawn` attribute changes
	(StatService.Recompute sets the first two from the equipment, SkillService the last from combat
	mode). Drawn models sit in the hands; sheathed ones hang from the body sockets below. Cosmetic
	only; the models never collide or take hits.
]=]
local LoadoutService = {}

-- Name of the folder in the character that holds the held models.
local HELD_FOLDER = "Held"

-- Models held when an item's own model does not exist or cannot be held.
local BASE_WEAPON = "Sword"
local BASE_SHIELD = "Shield"

-- Where each model hangs while sheathed: body part and offset (the Handle's axes follow the
-- socket's: Y is the blade or shaft and a shield's face normal; a bow's limbs run along Z).
local SOCKETS: { [string]: { part: string, cframe: CFrame } } = {
	Sword = {
		part = "LowerTorso",
		cframe = CFrame.new(-0.95, -0.1, 0.1) * CFrame.Angles(math.rad(-15), 0, math.pi),
	},
	Wand = {
		part = "LowerTorso",
		cframe = CFrame.new(0.95, -0.1, 0.1) * CFrame.Angles(math.rad(-15), 0, math.pi),
	},
	Shield = {
		part = "UpperTorso",
		cframe = CFrame.new(0, 0, 0.15) * CFrame.Angles(math.rad(90), 0, 0),
	},
	Bow = {
		part = "UpperTorso",
		cframe = CFrame.new(-0.2, 0, 1) * CFrame.Angles(math.rad(90), 0, math.rad(15)),
	},
	Staff = {
		part = "UpperTorso",
		cframe = CFrame.new(0.3, -1.3, 0.8) * CFrame.Angles(0, 0, math.rad(15)),
	},
}
local SOCKET_NAME = "SheathSocket"

-- Models worn on the body while drawn instead of gripped in a hand. The shield straps to the outer
-- side of the forearm: its face (Handle Y) looks along the arm's -X, forward in the ShieldBlock and
-- sword idle clips, and the disc stands vertical in them.
local DRAWN_SOCKETS: { [string]: { part: string, cframe: CFrame } } = {
	Shield = {
		part = "LeftLowerArm",
		cframe = CFrame.fromMatrix(Vector3.new(-0.55, -0.1, 0), Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0)),
	},
}

-- The attachment a model hangs from: the hand's grip or drawn socket when drawn, else its body socket.
local function holder(character: Model, modelName: string, hand: string, drawn: boolean): Attachment?
	if drawn and not DRAWN_SOCKETS[modelName] then
		local handPart = character:FindFirstChild(hand .. "Hand")
		local grip = handPart and handPart:FindFirstChild(hand .. "GripAttachment")
		return if grip and grip:IsA("Attachment") then grip else nil
	end
	local socket = if drawn then DRAWN_SOCKETS[modelName] else SOCKETS[modelName]
	local part = socket and character:FindFirstChild(socket.part)
	if not socket or not part or not part:IsA("BasePart") then
		return nil
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = SOCKET_NAME
	attachment.CFrame = socket.cframe
	attachment.Parent = part
	return attachment
end

-- A model is holdable with a Handle part carrying a Grip attachment.
local function holdable(modelName: string): Model?
	local source = ReplicatedStorage:FindFirstChild("Weapons")
	local template = source and source:FindFirstChild(modelName)
	local handle = template and template:FindFirstChild("Handle")
	local grip = handle and handle:FindFirstChild("Grip")
	if template and template:IsA("Model") and handle and handle:IsA("BasePart") and grip and grip:IsA("Attachment") then
		return template
	end
	return nil
end

local function attach(character: Model, wanted: string, base: string, hand: string, drawn: boolean): Model?
	local modelName = wanted
	local template = holdable(wanted)
	if not template then
		log:Warn("Weapon model %s missing or lacks Handle and Grip; holding %s", wanted, base)
		modelName = base
		template = holdable(base)
	end
	local handGrip = holder(character, modelName, hand, drawn)
	if not template or not handGrip then
		log:Warn("Cannot hold %s (%s)", modelName, if drawn then hand .. " hand" else "sheathed")
		return nil
	end
	local model = template:Clone()
	local handle = model:FindFirstChild("Handle") :: BasePart
	local grip = handle:FindFirstChild("Grip") :: Attachment
	-- Template parts are positioned around the Handle; weld each one to it where it stands.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			if part ~= handle then
				local joint = Instance.new("WeldConstraint")
				joint.Part0 = handle
				joint.Part1 = part
				joint.Parent = part
			end
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
		end
	end
	-- Weld offsets are read when the model enters the world, and the grip constraint would already
	-- have moved the Handle by then, leaving the other parts behind: stand the model on its grip first.
	local delta = handGrip.WorldCFrame * grip.CFrame:Inverse() * handle.CFrame:Inverse()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = delta * part.CFrame
		end
	end
	local weld = Instance.new("RigidConstraint")
	weld.Name = "HoldWeld"
	weld.Attachment0 = handGrip
	weld.Attachment1 = grip
	weld.Parent = handle
	return model
end

local function refresh(character: Model)
	local previous = character:FindFirstChild(HELD_FOLDER)
	if previous then
		previous:Destroy()
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Attachment") and descendant.Name == SOCKET_NAME then
			descendant:Destroy()
		end
	end
	local drawn = character:GetAttribute("Drawn") == true
	local folder = Instance.new("Folder")
	folder.Name = HELD_FOLDER

	local weapon = Weapons.ById[character:GetAttribute("Weapon") :: any]
	if weapon and weapon.model then
		local model = attach(character, weapon.model, BASE_WEAPON, weapon.hand or "Right", drawn)
		if model then
			model.Parent = folder
		end
	end
	local shieldItem = Items.ById[character:GetAttribute("Shield") :: any]
	if shieldItem and shieldItem.shield then
		local model = attach(character, shieldItem.shield.model, BASE_SHIELD, "Left", drawn)
		if model then
			model.Parent = folder
		end
	end
	folder.Parent = character
end

local function watch(entity: Entity)
	if entity.kind ~= "Player" then
		return
	end
	local character = entity.model
	character:GetAttributeChangedSignal("Weapon"):Connect(function()
		refresh(character)
	end)
	character:GetAttributeChangedSignal("Shield"):Connect(function()
		refresh(character)
	end)
	character:GetAttributeChangedSignal("Drawn"):Connect(function()
		refresh(character)
	end)
	refresh(character)
end

function LoadoutService.Init(deps: { [string]: any })
	EntityService = deps.EntityService
end

function LoadoutService.Start()
	EntityService.Added:Connect(watch)
	for _, entity in EntityService.All() do
		watch(entity)
	end
end

return LoadoutService
