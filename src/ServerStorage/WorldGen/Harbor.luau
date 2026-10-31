--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Continent = require(script.Parent.Continent)
local villageManifest = require(script.Parent.VillageManifest) :: any

local VILLAGE_KIT = "VillageKit" -- ServerStorage folder of village-kit templates (tools/blender/village_kit.py)
local FANTASY_KIT = "FantasyKit" -- ServerStorage folder of fantasy-kit templates (WorldGen/FantasyKit.luau)
local ROOT_NAME = "Harbor"
local GROUND_TOP = 200

--[=[
	Studio builder for the Harbor mock (docs/systems/world-generation.md, Harbor): an inn, a guild hall
	with the quest board, the Pylon, a plaza and a dock, all under `Workspace.Harbor`. Run it in Edit
	mode: `require(game.ServerStorage.WorldGen.Harbor).Build()`. Layout is in studs, the Harbor
	village at 0, 0, the sea to the south. Gameplay anchors the server finds by tag:
	`QuestBoard` (board part), `Pylon` (model, with an `Arrival` part), and the Map's spawns
	(`RespawnPoint` at the inn, `ArrivalSpawn` at the dock end) and its vendor. Art can change freely
	as long as those tags stay.
]=]
local Harbor = {}

local DECK_Y = 1.5
local PIER_START = 150
local PIER_END = 330
local PIER_WIDTH = 12
local HEAD_WIDTH = 44
local HEAD_DEPTH = 30

local WOOD = Color3.fromRGB(122, 92, 62)
local WOOD_DARK = Color3.fromRGB(86, 64, 44)
local STONE = Color3.fromRGB(128, 128, 134)
local GLOW = Color3.fromRGB(90, 200, 255)

local terrainParams = RaycastParams.new()
terrainParams.FilterType = Enum.RaycastFilterType.Include

local function groundAt(x: number, z: number): number
	terrainParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, GROUND_TOP, z), Vector3.new(0, -GROUND_TOP * 2, 0), terrainParams)
	return if hit then hit.Position.Y else 0.2
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A kit model on the ground at (x, z), turned by `yaw` radians (front is -Z at 0).
local function kit(parent: Instance, asset: string, x: number, z: number, yaw: number): Model?
	local library = ServerStorage:FindFirstChild(VILLAGE_KIT)
	local template = library and library:FindFirstChild(asset)
	if not template or not template:IsA("Model") then
		warn(`Harbor: village kit has no {asset}`)
		return nil
	end
	local model = template:Clone()
	model:SetAttribute("KitAsset", asset)
	model:PivotTo(CFrame.new(x, groundAt(x, z), z) * CFrame.Angles(0, yaw, 0))
	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundAt(x, z) - bottom, 0))
	model.Parent = parent
	return model
end

local function fantasyTemplate(asset: string): Model?
	local library = ServerStorage:FindFirstChild(FANTASY_KIT)
	local template = library and library:FindFirstChild(asset)
	if not template or not template:IsA("Model") then
		warn(`Harbor: fantasy kit has no {asset}`)
		return nil
	end
	return template:Clone()
end

-- A fantasy-kit prop standing on the ground at (x, z).
local function prop(parent: Instance, asset: string, x: number, z: number, yaw: number): Model?
	local model = fantasyTemplate(asset)
	if not model then
		return nil
	end
	model:PivotTo(CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0))
	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, groundAt(x, z) - bottom, 0))
	model.Parent = parent
	return model
end

-- A fantasy-kit fitting on a building's front wall: `x` along the wall from its centre, `y` above the
-- ground. Fittings stick out along the building's front (-Z) at 0 `turn`.
local function fitting(parent: Instance, asset: string, building: Model?, x: number, y: number, turn: number): Model?
	local model = fantasyTemplate(asset)
	if not model or not building then
		return nil
	end
	local depth = villageManifest.assets[building:GetAttribute("KitAsset") :: string].footprint[2]
	local box, size = building:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	local wall = -depth / 2 * Continent.kitScale
	local pivot = building:GetPivot()
	model:PivotTo(
		CFrame.new(pivot.Position.X, bottom, pivot.Position.Z)
			* pivot.Rotation
			* CFrame.new(x, y, wall)
			* CFrame.Angles(0, turn, 0)
	)
	model.Parent = parent
	return model
end

local function folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function buildings(root: Folder)
	local group = folder(root, "Buildings")
	-- Inn east of the plaza, door facing west; guild hall west, door facing east.
	local inn = kit(group, "House06", 68, 8, math.rad(90))
	if inn then
		inn.Name = "Inn"
	end
	local hall = kit(group, "Barn01", -62, -5, math.rad(-90))
	if hall then
		hall.Name = "GuildHall"
	end
	-- Dressing: houses around the plaza and along the road to the dock, a warehouse by the pier.
	local houses: { { asset: string, x: number, z: number, turn: number } } = {
		{ asset = "House03", x = -70, z = 58, turn = -90 },
		{ asset = "House01", x = 68, z = 62, turn = 90 },
		{ asset = "House04", x = -64, z = 104, turn = -90 },
		{ asset = "House08", x = 64, z = 108, turn = 90 },
		{ asset = "House02", x = -40, z = 150, turn = 180 },
		{ asset = "Barn02", x = 50, z = 150, turn = 180 },
	}
	for _, spec in houses do
		kit(group, spec.asset, spec.x, spec.z, math.rad(spec.turn))
	end
	-- Plaza fittings.
	kit(group, "Well", 14, 62, 0)
	-- Inn and hall frontage: the pub sign and lanterns at the inn door, banners and lanterns at the hall's.
	local fittings = folder(group, "Fittings")
	local function lantern(building: Model?, x: number)
		local model = fitting(fittings, "Lantern_Wall", building, x, 7, 0)
		local glass = model and model:FindFirstChildWhichIsA("BasePart")
		if glass then
			-- The kit tints this iron darker with its shader.
			local surface = glass:FindFirstChildOfClass("SurfaceAppearance")
			if surface then
				surface.Color = Color3.fromRGB(95, 90, 88)
			end
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 190, 120)
			light.Range = 18
			light.Brightness = 0.8
			light.Parent = glass
		end
	end
	-- Inn door at wall x -3.2, hall door at wall x 9.6 (content/world/village.json).
	fitting(fittings, "Sign_Pub", inn, -11.5, 13.5, -math.pi / 2)
	lantern(inn, 2)
	lantern(inn, -8.4)
	fitting(fittings, "Banner_Vertical_1", hall, 1, 3, 0)
	fitting(fittings, "Banner_Vertical_1", hall, 18.2, 3, 0)
	lantern(hall, 4)
	lantern(hall, 15.2)
end

-- Market and street furniture around the plaza and the road to the dock.
local function dressing(root: Folder)
	local group = folder(root, "Dressing")
	local spots: { { asset: string, x: number, z: number, turn: number } } = {
		-- Market stalls along the road, open to it.
		{ asset = "Stall_Empty", x = -38, z = 34, turn = -90 },
		{ asset = "Stall_Empty", x = -38, z = 46, turn = -90 },
		{ asset = "Stall_Cart_Empty", x = 36, z = 48, turn = 90 },
		-- Benches facing the Pylon.
		{ asset = "Bench", x = -20, z = 78, turn = 90 },
		{ asset = "Bench", x = 20, z = 84, turn = -90 },
		-- A table in the shade of the houses.
		{ asset = "Table_Large", x = 36, z = 72, turn = 90 },
		{ asset = "Stool", x = 31, z = 69, turn = 23 },
		{ asset = "Stool", x = 31, z = 75, turn = 75 },
		{ asset = "Stool", x = 41, z = 72, turn = 126 },
		-- Barrels at the inn's side, by the warehouse, a bucket at the well.
		{ asset = "Barrel", x = 50, z = -10, turn = 29 },
		{ asset = "Barrel", x = 47, z = -7, turn = 115 },
		{ asset = "Barrel", x = 51, z = -5, turn = 195 },
		{ asset = "Barrel", x = 32, z = 136, turn = 57 },
		{ asset = "Barrel", x = 35, z = 140, turn = 229 },
		{ asset = "Bucket_Wooden_1", x = 20, z = 58, turn = 46 },
	}
	for _, spot in spots do
		prop(group, spot.asset, spot.x, spot.z, math.rad(spot.turn))
	end
end

local function questBoard(root: Folder)
	local model = Instance.new("Model")
	model.Name = "QuestBoard"
	local x, z = -29, 4
	local y = groundAt(x, z)
	for _, dz in { -3, 3 } do
		part(model, "Post", Vector3.new(0.9, 9, 0.9), CFrame.new(x, y + 4.5, z + dz), WOOD_DARK, Enum.Material.Wood)
	end
	local board =
		part(model, "Board", Vector3.new(0.6, 5.5, 7.4), CFrame.new(x, y + 6, z), WOOD, Enum.Material.WoodPlanks)
	part(model, "Roof", Vector3.new(2.6, 0.5, 8.6), CFrame.new(x, y + 9.3, z), WOOD_DARK, Enum.Material.Wood)
	-- Pinned notices: kit parchment on the east face, stood up from lying flat.
	for index, dz in { -2.4, 0, 2.4 } do
		local notice = fantasyTemplate("Parchment")
		if notice then
			notice.Name = `Notice{index}`
			notice:ScaleTo(notice:GetScale() * 2.2)
			for _, surface in notice:GetDescendants() do
				if surface:IsA("SurfaceAppearance") then
					surface.Color = Color3.fromRGB(222, 208, 170)
				end
			end
			notice:PivotTo(
				CFrame.new(x + 0.32, y + 6.2 + (index % 2) * 0.6, z + dz) * CFrame.Angles(0, 0, -math.pi / 2)
			)
			notice.Parent = model
		end
	end
	board:AddTag("QuestBoard")
	model.PrimaryPart = board
	model.Parent = root
end

local function pylon(root: Folder)
	local model = Instance.new("Model")
	model.Name = "Pylon"
	local x, z = 0, 78
	local y = groundAt(x, z)
	local base = part(
		model,
		"Base",
		Vector3.new(1.6, 14, 14),
		CFrame.new(x, y + 0.8, z) * CFrame.Angles(0, 0, math.rad(90)),
		STONE,
		Enum.Material.Cobblestone
	)
	base.Shape = Enum.PartType.Cylinder
	local step = part(
		model,
		"Step",
		Vector3.new(1.6, 9.6, 9.6),
		CFrame.new(x, y + 2.4, z) * CFrame.Angles(0, 0, math.rad(90)),
		STONE,
		Enum.Material.Slate
	)
	step.Shape = Enum.PartType.Cylinder
	for i = 0, 3 do
		local angle = i * math.pi / 2 + math.pi / 4
		part(
			model,
			"Pillar",
			Vector3.new(1.4, 9, 1.4),
			CFrame.new(x + math.cos(angle) * 4, y + 7.2, z + math.sin(angle) * 4) * CFrame.Angles(0, -angle, 0),
			STONE,
			Enum.Material.Slate
		)
	end
	local core = part(
		model,
		"Core",
		Vector3.new(2.4, 13, 2.4),
		CFrame.new(x, y + 9.5, z) * CFrame.Angles(0, math.rad(45), 0),
		GLOW,
		Enum.Material.Neon
	)
	core.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = GLOW
	light.Range = 28
	light.Brightness = 2
	light.Parent = core
	local arrival =
		part(model, "Arrival", Vector3.new(4, 0.2, 4), CFrame.new(x, y + 0.1, z + 13), STONE, Enum.Material.Slate)
	arrival.Transparency = 1
	arrival.CanCollide = false
	arrival.CanQuery = false
	arrival.CanTouch = false
	model.PrimaryPart = base
	model:AddTag("Pylon")
	model.Parent = root
end

local function dock(root: Folder)
	local group = folder(root, "Dock")
	local length = PIER_END - PIER_START
	local centre = (PIER_START + PIER_END) / 2
	part(
		group,
		"Deck",
		Vector3.new(PIER_WIDTH, 1, length),
		CFrame.new(0, DECK_Y, centre),
		WOOD,
		Enum.Material.WoodPlanks
	)
	part(
		group,
		"Head",
		Vector3.new(HEAD_WIDTH, 1, HEAD_DEPTH),
		CFrame.new(0, DECK_Y, PIER_END - HEAD_DEPTH / 2 + 2),
		WOOD,
		Enum.Material.WoodPlanks
	)
	-- Piles down to the seabed, both edges every 12 studs, and under the head.
	local function pile(x: number, z: number)
		local p = part(
			group,
			"Pile",
			Vector3.new(46, 1.8, 1.8),
			CFrame.new(x, DECK_Y + 2.5 - 23, z) * CFrame.Angles(0, 0, math.rad(90)),
			WOOD_DARK,
			Enum.Material.Wood
		)
		p.Shape = Enum.PartType.Cylinder
	end
	for z = PIER_START + 6, PIER_END - 6, 12 do
		pile(-PIER_WIDTH / 2 + 0.9, z)
		pile(PIER_WIDTH / 2 - 0.9, z)
	end
	for _, x in { -HEAD_WIDTH / 2 + 2, HEAD_WIDTH / 2 - 2 } do
		for _, z in { PIER_END - HEAD_DEPTH + 4, PIER_END + 1 } do
			pile(x, z)
		end
	end
	-- Rails along the pier, open at the head.
	for _, side in { -1, 1 } do
		part(
			group,
			"Rail",
			Vector3.new(0.5, 0.5, PIER_END - PIER_START - HEAD_DEPTH),
			CFrame.new(
				side * (PIER_WIDTH / 2 - 0.4),
				DECK_Y + 3.2,
				PIER_START + (PIER_END - PIER_START - HEAD_DEPTH) / 2
			),
			WOOD_DARK,
			Enum.Material.Wood
		)
		for z = PIER_START + 4, PIER_END - HEAD_DEPTH, 12 do
			part(
				group,
				"RailPost",
				Vector3.new(0.7, 3.4, 0.7),
				CFrame.new(side * (PIER_WIDTH / 2 - 0.4), DECK_Y + 1.7, z),
				WOOD_DARK,
				Enum.Material.Wood
			)
		end
	end
	-- Cargo on the head.
	for index, spot in { { -14, 318 }, { -11, 322 }, { 15, 320 }, { 13, 326 } } do
		kit(group, "Crate", spot[1], spot[2], index * 0.7)
	end
	kit(group, "Wagon", -16, 334, math.rad(90))
	for index, spot in { { 18, 310 }, { 15, 307 }, { 19, 306 } } do
		prop(group, "Barrel", spot[1], spot[2], index * 1.3)
	end
	prop(group, "Rope_1", 5, 326, 0)
	prop(group, "Rope_1", -7, 309, 2)
end

-- Lifts kit models placed on the deck: they were set on the ground, the deck is higher.
local function liftDockKit(root: Folder)
	local group = root:FindFirstChild("Dock")
	if not group then
		return
	end
	for _, child in group:GetChildren() do
		if child:IsA("Model") then
			local box, size = child:GetBoundingBox()
			local bottom = box.Position.Y - size.Y / 2
			child:PivotTo(child:GetPivot() + Vector3.new(0, DECK_Y + 0.5 - bottom, 0))
		end
	end
end

--[=[ Rebuilds `Workspace.Harbor`. Edit mode only. Returns the number of instances it made. ]=]
function Harbor.Build(): number
	assert(not RunService:IsRunning(), "Harbor.Build runs in Edit mode")
	local old = workspace:FindFirstChild(ROOT_NAME)
	if old then
		old:Destroy()
	end
	-- The region builder's placeholder pillar for this site stands on the plaza.
	local world = workspace:FindFirstChild("World")
	local pillar = world and world:FindFirstChild("harbor", true)
	if pillar and pillar:IsA("BasePart") and pillar:GetAttribute("SiteKind") == "harbor" then
		pillar:Destroy()
	end

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	buildings(root)
	dressing(root)
	questBoard(root)
	pylon(root)
	dock(root)
	liftDockKit(root)
	root.Parent = workspace
	return #root:GetDescendants()
end

return Harbor
