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
	ReplicatedStorage.Weapons onto the character's hands whenever its `Weapon` or `Shield`
	attribute changes (StatService.Recompute sets them from the equipment). Cosmetic only; the
	models never collide or take hits.
]=]
local LoadoutService = {}

-- Name of the folder in the character that holds the held models.
local HELD_FOLDER = "Held"

local function attach(character: Model, modelName: string, hand: string): Model?
	local source = ReplicatedStorage:FindFirstChild("Weapons")
	local template = source and source:FindFirstChild(modelName)
	local handPart = character:FindFirstChild(hand .. "Hand")
	local handGrip = handPart and handPart:FindFirstChild(hand .. "GripAttachment")
	if not (template and template:IsA("Model")) or not (handGrip and handGrip:IsA("Attachment")) then
		log:Warn("Cannot hold %s in %s hand", modelName, hand)
		return nil
	end
	local model = template:Clone()
	local handle = model:FindFirstChild("Handle")
	local grip = handle and handle:FindFirstChild("Grip")
	if not (handle and handle:IsA("BasePart")) or not (grip and grip:IsA("Attachment")) then
		log:Warn("Weapon model %s needs a Handle part with a Grip attachment", modelName)
		model:Destroy()
		return nil
	end
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
	local folder = Instance.new("Folder")
	folder.Name = HELD_FOLDER

	local weapon = Weapons.ById[character:GetAttribute("Weapon") :: any]
	if weapon and weapon.model then
		local model = attach(character, weapon.model, weapon.hand or "Right")
		if model then
			model.Parent = folder
		end
	end
	local shieldItem = Items.ById[character:GetAttribute("Shield") :: any]
	if shieldItem and shieldItem.shield then
		local model = attach(character, shieldItem.shield.model, "Left")
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
