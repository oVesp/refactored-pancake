--!strict

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Continent = require(script.Parent.Continent)
local manifest = require(script.Parent.FantasyManifest) :: any

local LIBRARY = "FantasyKit"

-- Thin or hanging pieces nobody should bump into.
local WALK_THROUGH = { Banner_1 = true, Banner_Vertical_1 = true, Lantern_Wall = true, Parchment = true, Rope_1 = true }

--[=[
	Studio importer for the Fantasy Props MegaKit library (tools/blender/fantasy_kit.py,
	content/world/fantasy.json). Run it in Edit mode: `require(game.ServerStorage.WorldGen.FantasyKit).Import()`.
	Fills `ServerStorage.FantasyKit` with one Model per asset at `kitScale` studs per kit metre, one
	MeshPart per material, the pivot at the kit's origin. Returns the assets it made.
]=]
local FantasyKit = {}

function FantasyKit.Import(): number
	assert(not RunService:IsRunning(), "FantasyKit.Import runs in Edit mode")
	local asset = InsertService:LoadAsset(tonumber(manifest.assetId) :: number)
	local groups: { [string]: { MeshPart } } = {}
	for _, node in asset:GetDescendants() do
		local name, material = string.match(node.Name, "^(.-)__(.-)_Node$")
		if not (name and material and node:IsA("Model")) then
			continue
		end
		for _, descendant in node:GetDescendants() do
			if descendant:IsA("MeshPart") then
				local part = descendant:Clone()
				part.Name = material
				groups[name] = groups[name] or {}
				table.insert(groups[name], part)
			end
		end
	end
	asset:Destroy()

	local old = ServerStorage:FindFirstChild(LIBRARY)
	if old then
		old:Destroy()
	end
	local library = Instance.new("Folder")
	library.Name = LIBRARY
	local count = 0
	for name, parts in groups do
		local meta = manifest.assets[name]
		assert(meta, `fantasy kit asset {name} is not in the manifest`)
		local model = Instance.new("Model")
		model.Name = name
		for _, part in parts do
			local info = manifest.materials[part.Name] or {}
			local surface = part:FindFirstChildOfClass("SurfaceAppearance")
			part.Anchored = true
			part.CanTouch = false
			part.CanCollide = not WALK_THROUGH[name]
			part.CanQuery = part.CanCollide
			if surface and info.tint then
				surface.Color = Color3.fromRGB(info.tint[1], info.tint[2], info.tint[3])
			end
			part.Parent = model
		end
		-- The upload keeps metres as studs; the kit origin is the bounds centre minus the manifest's.
		local box = model:GetBoundingBox()
		local centre = Vector3.new(
			(meta.min[1] + meta.max[1]) / 2,
			(meta.min[2] + meta.max[2]) / 2,
			(meta.min[3] + meta.max[3]) / 2
		)
		model.WorldPivot = CFrame.new(box.Position - centre)
		model:PivotTo(CFrame.identity)
		model:ScaleTo(Continent.kitScale)
		model.Parent = library
		count += 1
	end
	library.Parent = ServerStorage
	return count
end

return FantasyKit
