--!strict

--[=[
	Studio builder for the continent, one region at a time (docs/systems/world-generation.md,
	region builds). Edit mode only; run from the command bar or Studio MCP:

	```lua
	local Regions = require(game.ServerStorage.WorldGen.Regions)
	Regions.Build("verdant")        -- terrain, sea, roads, props and site markers; runs in the background
	Regions.Status("verdant")       -- "terrain 120/310", ..., "done in 95s"
	Regions.View("verdant", 1)      -- camera position and target over the region, 1-4 from N/E/S/W, 5 overhead
	```

	A region writes only the terrain columns it owns: each 256-stud block is read, its columns are
	replaced, and the block is written back, so neighbours stay untouched. Parts go to
	`Workspace.World/<region>`. An approved region (`Continent.approved`) is refused unless
	`Build(id, true)`.

	The command bar caches `require` per session. After Rojo syncs a change, require a clone:
	`local c = game.ServerStorage.WorldGen:Clone(); local R = require(c.Regions)`.
]=]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local Continent = require(script.Parent.Gen.Continent)
local Region = require(script.Parent.Gen.Region)
local Template = require(script.Parent.Continent)

local log = Logger.new("WorldGen")

local VOXEL = 4
-- Studio draws a solid terrain surface half a voxel above the height a linear occupancy encodes,
-- so ground is written this much lower to land the surface on the generated height. Water renders
-- where it is written and is not shifted.
local SURFACE_OFFSET = VOXEL / 2
local BLOCK = 64 -- voxel columns per terrain read/write block (256 studs)
local FLOOR_Y = -96 -- terrain is filled down to here
local FLUSH = 400 -- parts parented per frame
local ROOT = "World"
local LIBRARY = "WorldProps" -- ServerStorage folder of prop templates (tools/blender/world_props.py)

local Regions = {}

local cached: Region.Context? = nil
local function context(): Region.Context
	if not cached then
		cached = Region.context(Template)
	end
	return cached :: Region.Context
end

local function assertEditMode()
	assert(RunService:IsStudio() and not RunService:IsRunning(), "WorldGen runs in Studio edit mode only")
end

local function root(): Folder
	local folder = workspace:FindFirstChild(ROOT)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ROOT
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function setStatus(id: string, text: string)
	root():SetAttribute("Build_" .. id, text)
end

local function setMaterialColors()
	for name, rgb in Template.materialColors do
		workspace.Terrain:SetMaterialColor((Enum.Material :: any)[name], Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
	end
end

-- Blocks whose 80-stud grid cells come near the region; the rest cannot hold an owned column.
local function blocksOf(ctx: Region.Context, index: number, bounds: { number }): { { number } }
	local map = ctx.map
	local near: { [number]: boolean } = {}
	local reach = math.ceil(Template.offshoreMargin / (Template.size / map.res)) + 1
	for k = 1, map.res * map.res do
		if map.region[k] == index then
			local i, j = (k - 1) % map.res, (k - 1) // map.res
			for dj = -reach, reach do
				for di = -reach, reach do
					local ni, nj = i + di, j + dj
					if ni >= 0 and nj >= 0 and ni < map.res and nj < map.res then
						near[Continent.index(map.res, ni, nj)] = true
					end
				end
			end
		end
	end
	local blockStuds = BLOCK * VOXEL
	local out: { { number } } = {}
	for bz = math.floor(bounds[2] / blockStuds), math.floor(bounds[4] / blockStuds) do
		for bx = math.floor(bounds[1] / blockStuds), math.floor(bounds[3] / blockStuds) do
			local hit = false
			for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0.5 } } do
				local u, v = Continent.toUnit(Template, (bx + corner[1]) * blockStuds, (bz + corner[2]) * blockStuds)
				local i = math.clamp(math.floor(u * map.res), 0, map.res - 1)
				local j = math.clamp(math.floor(v * map.res), 0, map.res - 1)
				if near[Continent.index(map.res, i, j)] then
					hit = true
					break
				end
			end
			if hit then
				table.insert(out, { bx, bz })
			end
		end
	end
	return out
end

local function writeBlock(ctx: Region.Context, index: number, bx: number, bz: number)
	local terrain = workspace.Terrain
	local blockStuds = BLOCK * VOXEL
	local wx0, wz0 = bx * blockStuds, bz * blockStuds
	-- Samples with a one-column border, for slopes.
	local n = BLOCK + 2
	local points: { Continent.Sample } = table.create(n * n)
	for iz = 0, n - 1 do
		for ix = 0, n - 1 do
			local x = wx0 + (ix - 1) * VOXEL + VOXEL / 2
			local z = wz0 + (iz - 1) * VOXEL + VOXEL / 2
			points[iz * n + ix + 1] = ctx.sample(Continent.toUnit(Template, x, z))
		end
	end
	local columns: { Region.Column } = table.create(BLOCK * BLOCK)
	local top = -math.huge
	local mine = 0
	for iz = 0, BLOCK - 1 do
		for ix = 0, BLOCK - 1 do
			local k = (iz + 1) * n + ix + 2
			local p = points[k]
			local slope = math.max(
				math.abs(points[k - 1].height - p.height),
				math.abs(points[k + 1].height - p.height),
				math.abs(points[k - n].height - p.height),
				math.abs(points[k + n].height - p.height)
			)
			local x = wx0 + ix * VOXEL + VOXEL / 2
			local z = wz0 + iz * VOXEL + VOXEL / 2
			local column = Region.column(ctx, index, x, z, p, slope)
			columns[iz * BLOCK + ix + 1] = column
			if column.owned then
				mine += 1
				top = math.max(top, column.height, column.water or -math.huge)
			end
		end
	end
	if mine == 0 then
		return
	end

	local world = root()
	local key = `Top_{bx}_{bz}`
	local previous = world:GetAttribute(key)
	local roof = math.max(top, if type(previous) == "number" then previous else -math.huge)
	world:SetAttribute(key, roof)
	local layers = math.ceil((roof + 8 - FLOOR_Y) / VOXEL)
	local region = Region3.new(
		Vector3.new(wx0, FLOOR_Y, wz0),
		Vector3.new(wx0 + blockStuds, FLOOR_Y + layers * VOXEL, wz0 + blockStuds)
	)
	local read = terrain:ReadVoxelChannels(region, VOXEL, { "SolidMaterial", "SolidOccupancy", "LiquidOccupancy" })
	local materials = read.SolidMaterial
	local solids = read.SolidOccupancy
	local liquids = read.LiquidOccupancy
	local air = Enum.Material.Air
	local rock = Enum.Material.Rock
	for iz = 0, BLOCK - 1 do
		for ix = 0, BLOCK - 1 do
			local column = columns[iz * BLOCK + ix + 1]
			if not column.owned then
				continue
			end
			local h = column.height - SURFACE_OFFSET
			local w = column.water
			local surface = (Enum.Material :: any)[column.material]
			for iy = 1, layers do
				local bottom = FLOOR_Y + (iy - 1) * VOXEL
				local solid = math.clamp((h - bottom) / VOXEL, 0, 1)
				local depth = h - (bottom + VOXEL / 2)
				materials[ix + 1][iy][iz + 1] = if solid > 0 then (if depth < 8 then surface else rock) else air
				solids[ix + 1][iy][iz + 1] = solid
				liquids[ix + 1][iy][iz + 1] = if solid < 1 and w then math.clamp((w - bottom) / VOXEL, 0, 1) else 0
			end
		end
	end
	terrain:WriteVoxelChannels(region, VOXEL, {
		SolidMaterial = materials,
		SolidOccupancy = solids,
		LiquidOccupancy = liquids,
	})
end

local missingWarned: { [string]: boolean } = {}

local function placeProps(folder: Folder, specs: { Region.PropSpec })
	local library = ServerStorage:FindFirstChild(LIBRARY)
	if not library then
		log:Warn("ServerStorage.%s is missing; region builds bare", LIBRARY)
		return
	end
	local group = Instance.new("Folder")
	group.Name = "Props"
	group.Parent = folder
	local pending: { BasePart } = {}
	local function flush()
		for _, part in pending do
			part.Parent = group
		end
		table.clear(pending)
		task.wait()
	end
	for _, spec in specs do
		local template = library:FindFirstChild(spec.asset)
		if not template or not template:IsA("Model") then
			if not missingWarned[spec.asset] then
				missingWarned[spec.asset] = true
				log:Warn("prop template %s missing from ServerStorage.%s", spec.asset, LIBRARY)
			end
			continue
		end
		local pivot = template:GetPivot()
		local target = CFrame.new(spec.x, spec.y, spec.z) * CFrame.Angles(0, spec.yaw, 0)
		for _, source in template:GetChildren() do
			if source:IsA("BasePart") then
				local offset = pivot:ToObjectSpace(source.CFrame)
				local part = source:Clone()
				part.Size = source.Size * spec.scale
				part.CFrame = target * CFrame.new(offset.Position * spec.scale) * offset.Rotation
				table.insert(pending, part)
				if #pending >= FLUSH then
					flush()
				end
			end
		end
	end
	flush()
end

local MARKER_COLOR: { [string]: Color3 } = {
	capital = Color3.fromRGB(255, 214, 64),
	harbor = Color3.fromRGB(255, 214, 64),
	city = Color3.fromRGB(240, 240, 240),
	town = Color3.fromRGB(240, 240, 240),
	poi = Color3.fromRGB(60, 200, 230),
	dungeon = Color3.fromRGB(200, 40, 40),
	portal = Color3.fromRGB(190, 90, 255),
}

-- Placeholder pillars where the region's sites will be dressed.
local function placeMarkers(folder: Folder, markers: { Region.Marker })
	local group = Instance.new("Folder")
	group.Name = "Sites"
	for _, marker in markers do
		local part = Instance.new("Part")
		part.Name = marker.id
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.Material = Enum.Material.Neon
		part.Color = MARKER_COLOR[marker.kind] or Color3.new(1, 1, 1)
		part.Size = Vector3.new(6, 60, 6)
		part.CFrame = CFrame.new(marker.x, marker.y + 30, marker.z)
		part:SetAttribute("SiteKind", marker.kind)
		part:SetAttribute("SiteName", marker.name)
		part.Parent = group
	end
	group.Parent = folder
end

local function build(id: string): boolean
	local started = os.clock()
	local ctx = context()
	local index = Region.index(ctx, id)
	setMaterialColors()
	local bounds = Region.bounds(ctx, id)
	local blocks = blocksOf(ctx, index, bounds)
	for n, block in blocks do
		writeBlock(ctx, index, block[1], block[2])
		setStatus(id, `terrain {n}/{#blocks}`)
		task.wait()
	end

	local old = root():FindFirstChild(id)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = id
	folder.Parent = root()
	setStatus(id, "props")
	placeProps(folder, Region.props(ctx, id))
	placeMarkers(folder, Region.markers(ctx, id))
	local took = math.floor(os.clock() - started)
	setStatus(id, `done in {took}s`)
	log:Info("built region %s in %ds (%d blocks)", id, took, #blocks)
	return true
end

--[=[ Builds a region in the background; `Status` reports progress. ]=]
function Regions.Build(id: string, force: boolean?)
	assertEditMode()
	if Template.approved[id] and not force then
		error(`region {id} is approved; pass force to rebuild it`)
	end
	setStatus(id, "starting")
	task.spawn(function()
		local ok, err = pcall(build, id)
		if not ok then
			setStatus(id, `failed: {err}`)
			log:Error("region %s failed: %s", id, tostring(err))
		end
	end)
end

--[=[ Progress of the last build of a region. ]=]
function Regions.Status(id: string): string
	local status = root():GetAttribute("Build_" .. id)
	return if type(status) == "string" then status else "not built"
end

--[=[
	Camera over a region for screenshots: `k` 1-4 looks from the N/E/S/W edge toward the centre,
	5 from high above. Returns the camera position and target.
]=]
function Regions.View(id: string, k: number): (Vector3, Vector3)
	local ctx = context()
	local bounds = Region.bounds(ctx, id)
	local margin = Template.offshoreMargin
	local x0, z0, x1, z1 = bounds[1] + margin, bounds[2] + margin, bounds[3] - margin, bounds[4] - margin
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local u, v = Continent.toUnit(Template, cx, cz)
	local target = Vector3.new(cx, ctx.sample(u, v).height, cz)
	local half = math.max(x1 - x0, z1 - z0) / 2
	local from = ({
		Vector3.new(cx, 400, z0 - half * 0.2),
		Vector3.new(x1 + half * 0.2, 400, cz),
		Vector3.new(cx, 400, z1 + half * 0.2),
		Vector3.new(x0 - half * 0.2, 400, cz),
		Vector3.new(cx, half * 2.2, cz + half * 0.6),
	})[k]
	assert(from, "view is 1 to 5")
	local camera = workspace.CurrentCamera
	camera.CFrame = CFrame.lookAt(from, target)
	return from, target
end

return Regions
