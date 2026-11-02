--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Maid = require(ReplicatedStorage.Shared.Maid)

local Attributes = Constants.Attributes

--[=[
	Enemy and dummy nameplates from the Nameplate template: name, level, HP and, for devs with the
	debug overlay on, the AI state. Reads replicated attributes only.
]=]
local NameplateController = {}

local UIController: any

local maids: { [Instance]: Maid.Maid } = {}
local debugVisible = false

local function attach(model: Instance)
	if not model:IsA("Model") or maids[model] then
		return
	end
	local root = model:FindFirstChild("Head") or model.PrimaryPart
	if not root or not root:IsA("BasePart") then
		return
	end
	local maid = Maid.new()
	maids[model] = maid

	local plate = UIController.Clone("Nameplate") :: BillboardGui
	local parts = UIController.Bind(plate, { "Bind_Name", "Bind_HpFill", "Bind_Info" })
	local nameLabel = parts.Bind_Name :: TextLabel
	local info = parts.Bind_Info :: TextLabel
	plate.Adornee = root
	plate.StudsOffset = Vector3.new(0, 2.2, 0)
	plate.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	maid:Give(plate)

	local function render()
		local level = model:GetAttribute("Level")
		local name = model:GetAttribute("DisplayName") or model.Name
		local elite = if model:GetAttribute("Elite") == true then " ★" else ""
		nameLabel.Text = string.format("%s  Lv %s%s", tostring(name), tostring(level or "?"), elite)
		local hp = model:GetAttribute(Attributes.Hp)
		local maxHp = model:GetAttribute(Attributes.MaxHp)
		if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
			parts.Bind_HpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		end
		local casting = model:GetAttribute("Casting")
		local lines = {}
		if type(casting) == "string" then
			table.insert(lines, "Casting " .. casting)
		end
		if debugVisible then
			table.insert(lines, tostring(model:GetAttribute("AiState") or ""))
		end
		info.Text = table.concat(lines, " · ")
	end

	for _, name in { Attributes.Hp, Attributes.MaxHp, "Level", "Casting", "AiState", "DisplayName" } do
		maid:Give(model:GetAttributeChangedSignal(name):Connect(render))
	end
	maid:Give(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			maid:Clean()
			maids[model] = nil
		end
	end))
	render()
end

local function detach(model: Instance)
	local maid = maids[model]
	if maid then
		maid:Clean()
		maids[model] = nil
	end
end

--[=[ Shows or hides AI state lines (dev debug overlay). ]=]
function NameplateController.SetDebug(visible: boolean)
	debugVisible = visible
end

function NameplateController.Init(deps: { [string]: any })
	UIController = deps.UIController
end

function NameplateController.Start()
	for _, tag in { "Enemy", "TrainingDummy" } do
		for _, model in CollectionService:GetTagged(tag) do
			task.spawn(attach, model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(attach)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(detach)
	end
end

return NameplateController
