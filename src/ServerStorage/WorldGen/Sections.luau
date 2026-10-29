--!strict

--[=[
	Studio builder for the zone-graph world (docs/systems/world-generation.md, section loop).
	Edit mode only; run from the command bar or Studio MCP:

	```lua
	local Sections = require(game.ServerStorage.WorldGen.Sections)
	Sections.Reset()               -- once: clears old terrain, parks the old Nature props
	Sections.Build()               -- every zone in the realm's sections
	Sections.Build("orchard")      -- one zone: its terrain, cliffs and props
	Sections.Build("orchard", true) -- the zone and its neighbours (after moving a border)
	Sections.View("orchard", 1)    -- camera bookmark: from the site, facing N/E/S/W (1-4)
	```

	A zone writes only the terrain columns it owns: each 256-stud block is read, the zone's columns
	are replaced, and the block is written back, so neighbours stay untouched. Parts go to
	`Workspace.World/<zone>/<Kind>`. Locked zones build from `Baked/<zone>` instead of generating.

	The command bar caches `require` per session. After Rojo syncs a change, require a clone:
	`local c = game.ServerStorage.WorldGen:Clone(); local S = require(c.Sections)`.
]=]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Logger = require(ReplicatedStorage.Shared.Logger)

local Bake = require(script.Parent.Gen.Bake)
local Cliffs = require(script.Parent.Gen.Cliffs)
local Field = require(script.Parent.Gen.Field)
local Graph = require(script.Parent.Gen.Graph)
local Anchors = require(script.Parent.Gen.Anchors)
local Props = require(script.Parent.Gen.Props)
local Realm = require(script.Parent.Midgard)

local log = Logger.new("WorldGen")

local VOXEL = 4
-- Studio draws a solid terrain surface half a voxel above the height a linear occupancy encodes
-- (measured: occupancy for h = 0.2 renders at 2.19, for every h tested), so ground heights are
-- written this much lower to land the surface on the generated height. Water renders where it is
-- written and is not shifted.
local SURFACE_OFFSET = VOXEL / 2
local BLOCK = 64 -- voxel columns per terrain read/write block (256 studs)
local MARGIN = 48 -- studs of samples around a zone, for cliff tops and neighbour checks
local FLUSH = 400 -- parts parented per frame
local ROOT = "World"
local LIBRARY = "WorldProps" -- ServerStorage folder of prop templates (tools/blender/world_props.py)
local VILLAGE_KIT = "VillageKit" -- ServerStorage folder of village templates (tools/blender/village_kit.py)
local WORLD_TAG = "WorldTag" -- template attribute naming the tag a placed copy receives

local Sections = {}

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

local function setMaterialColors()
	local terrain = workspace.Terrain
	for name, rgb in Realm.materialColors do
		terrain:SetMaterialColor((Enum.Material :: any)[name], Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
	end
end

--[=[
	Writes the zone's terrain columns from a column table (Bake.Columns). Each world-aligned
	256-stud block the zone touches is read, its columns replaced where the zone owns them, and
	written back.
]=]
local function writeTerrain(zone: Graph.Node, columns: Bake.Columns)
	local terrain = workspace.Terrain
	local world = root()
	local biome = Realm.biomes[zone.biome]
	local floorY = Realm.floorY
	local air = Enum.Material.Air
	local rock = Enum.Material.Rock
	local blockStuds = BLOCK * VOXEL
	local bx0 = math.floor(columns.x0 / blockStuds)
	local bz0 = math.floor(columns.z0 / blockStuds)
	local bx1 = math.floor((columns.x0 + (columns.nx - 1) * VOXEL) / blockStuds)
	local bz1 = math.floor((columns.z0 + (columns.nz - 1) * VOXEL) / blockStuds)
	local deep = (Enum.Material :: any)[biome.rock]

	for bz = bz0, bz1 do
		for bx = bx0, bx1 do
			local wx0, wz0 = bx * blockStuds, bz * blockStuds
			-- Columns of this zone inside the block, and the height range they need.
			local top = -math.huge
			local mine = 0
			for iz = 0, BLOCK - 1 do
				for ix = 0, BLOCK - 1 do
					local k = Bake.columnIndex(columns, wx0 + ix * VOXEL, wz0 + iz * VOXEL)
					if k and columns.assign[k] == zone.index then
						mine += 1
						top = math.max(top, columns.height[k], columns.water[k])
					end
				end
			end
			if mine == 0 then
				continue
			end
			local key = `Top_{bx}_{bz}`
			local previous = world:GetAttribute(key)
			local roof = math.max(top, if type(previous) == "number" then previous else -math.huge)
			world:SetAttribute(key, roof)
			local layers = math.ceil((roof + 8 - floorY) / VOXEL)
			local region = Region3.new(
				Vector3.new(wx0, floorY, wz0),
				Vector3.new(wx0 + blockStuds, floorY + layers * VOXEL, wz0 + blockStuds)
			)
			local read =
				terrain:ReadVoxelChannels(region, VOXEL, { "SolidMaterial", "SolidOccupancy", "LiquidOccupancy" })
			local materials = read.SolidMaterial
			local solids = read.SolidOccupancy
			local liquids = read.LiquidOccupancy
			for iz = 0, BLOCK - 1 do
				for ix = 0, BLOCK - 1 do
					local k = Bake.columnIndex(columns, wx0 + ix * VOXEL, wz0 + iz * VOXEL)
					if not (k and columns.assign[k] == zone.index) then
						continue
					end
					local h = columns.height[k] - SURFACE_OFFSET
					local w = columns.water[k]
					local surface = (Enum.Material :: any)[columns.material[k]]
					for iy = 1, layers do
						local bottom = floorY + (iy - 1) * VOXEL
						local solid = math.clamp((h - bottom) / VOXEL, 0, 1)
						local depth = h - (bottom + VOXEL / 2)
						local material = air
						if solid > 0 then
							material = if depth < 6 then surface elseif depth < 20 then deep else rock
						end
						materials[ix + 1][iy][iz + 1] = material
						solids[ix + 1][iy][iz + 1] = solid
						liquids[ix + 1][iy][iz + 1] = if solid < 1 and w ~= 0
							then math.clamp((w - bottom) / VOXEL, 0, 1)
							else 0
					end
				end
			end
			terrain:WriteVoxelChannels(region, VOXEL, {
				SolidMaterial = materials,
				SolidOccupancy = solids,
				LiquidOccupancy = liquids,
			})
			task.wait()
		end
	end
end

local function makePart(spec: Cliffs.PartSpec): Part
	local part = Instance.new("Part")
	part.Name = spec.kind
	part.Anchored = true
	part.Size = Vector3.new(spec.sx, spec.sy, spec.sz)
	part.CFrame = CFrame.new(spec.x, spec.y, spec.z) * CFrame.fromEulerAnglesYXZ(spec.pitch, spec.yaw, spec.roll)
	part.Material = (Enum.Material :: any)[spec.material]
	part.Color = Color3.fromRGB(spec.color[1], spec.color[2], spec.color[3])
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if spec.kind == "Cap" then
		part.CastShadow = false
	end
	return part
end

local function placeParts(folder: Folder, specs: { Cliffs.PartSpec })
	local groups: { [string]: Folder } = {}
	local pending: { { part: Part, parent: Folder } } = {}
	local function flush()
		for _, item in pending do
			item.part.Parent = item.parent
		end
		table.clear(pending)
		task.wait()
	end
	for _, spec in specs do
		local group = groups[spec.kind]
		if not group then
			local created = Instance.new("Folder")
			created.Name = spec.kind
			created.Parent = folder
			groups[spec.kind] = created
			group = created
		end
		table.insert(pending, { part = makePart(spec), parent = group })
		if #pending >= FLUSH then
			flush()
		end
	end
	flush()
end

--[=[
	Places props as bare parts: every part of the variant's template is cloned, scaled about the
	template pivot and moved into place. No Model wraps them, so a tree costs its two parts.
]=]
local missingWarned: { [string]: boolean } = {}
local function placeProps(folder: Folder, specs: { Props.PropSpec })
	if #specs == 0 then
		return
	end
	local library = ServerStorage:FindFirstChild(LIBRARY)
	local kit = ServerStorage:FindFirstChild(VILLAGE_KIT)
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
		local template = (library and library:FindFirstChild(spec.asset)) or (kit and kit:FindFirstChild(spec.asset))
		if not template or not template:IsA("Model") then
			if not missingWarned[spec.asset] then
				missingWarned[spec.asset] = true
				log:Warn("prop template %s missing from ServerStorage.%s and .%s", spec.asset, LIBRARY, VILLAGE_KIT)
			end
			continue
		end
		local pivot = template:GetPivot()
		local target = CFrame.new(spec.x, spec.y, spec.z) * CFrame.Angles(0, spec.yaw, 0)
		for _, source in template:GetChildren() do
			if source:IsA("BasePart") then
				local offset = pivot:ToObjectSpace(source.CFrame)
				local part = source:Clone()
				local tag = part:GetAttribute(WORLD_TAG)
				if type(tag) == "string" then
					part:AddTag(tag)
				end
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

type Context = {
	graph: Graph.Graph,
	field: Field.Field,
	extents: { [number]: Bake.Extent },
	settlement: Bake.SettlementInput?,
}

local function context(): Context
	local graph = Graph.build(Realm)
	local field = Field.new(graph)
	-- Settlements need the village kit and the Map's anchors; without either, zones build bare.
	local settlement: Bake.SettlementInput? = nil
	local map = workspace:FindFirstChild("Map")
	if script.Parent:FindFirstChild("VillageManifest") and map and ServerStorage:FindFirstChild(VILLAGE_KIT) then
		settlement = { manifest = require(script.Parent.VillageManifest) :: any, anchors = Anchors.fromMap(map) }
	else
		log:Warn("settlements skipped: run Sections.ImportVillage() first")
	end
	return { graph = graph, field = field, extents = Bake.extents(field), settlement = settlement }
end

local function buildZone(ctx: Context, node: Graph.Node)
	local started = os.clock()
	local extent = ctx.extents[node.index]
	if not extent then
		log:Warn("%s owns no ground inside a section; skipped", node.id)
		return
	end
	local folder = root():FindFirstChild(node.id)
	if folder then
		folder:Destroy()
	end
	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = node.id
	zoneFolder:SetAttribute("Seed", node.seed)
	zoneFolder:SetAttribute("Tier", node.tier)
	zoneFolder:SetAttribute("Band", node.band)

	local result: Bake.Result
	local baked = script.Parent:FindFirstChild("Baked")
	local bakedModule = baked and baked:FindFirstChild(node.id)
	if node.locked and bakedModule then
		result = Bake.decode(require(bakedModule :: ModuleScript) :: any, node.index)
		zoneFolder:SetAttribute("Baked", true)
	else
		if node.locked then
			log:Warn("%s is locked but has no baked data; generating", node.id)
		end
		result = Bake.generate(ctx.field, node, extent, MARGIN, ctx.settlement)
	end
	zoneFolder.Parent = root()

	writeTerrain(node, result.columns)
	placeParts(zoneFolder, result.parts)
	placeProps(zoneFolder, result.props)
	log:Info("%s: %d parts, %d props in %.1fs", node.id, #result.parts, #result.props, os.clock() - started)
end

--[=[
	Builds one zone (`id`), the zone and its graph neighbours (`withNeighbours`), or every zone
	(`id` nil).
]=]
function Sections.Build(id: string?, withNeighbours: boolean?)
	assertEditMode()
	setMaterialColors()
	local ctx = context()
	local targets: { Graph.Node } = {}
	if id == nil then
		targets = ctx.graph.nodes
	else
		local node = ctx.graph.byId[id]
		assert(node, `unknown zone {id}`)
		table.insert(targets, node)
		if withNeighbours then
			-- Neighbours by shared ground, not by edges: rim and cliff neighbours have no edge.
			local touching = Bake.neighbours(ctx.field, MARGIN)[node.index]
			local others = {}
			if touching then
				for index in touching do
					table.insert(others, index)
				end
			end
			table.sort(others)
			for _, index in others do
				table.insert(targets, ctx.graph.nodes[index])
			end
		end
	end
	for _, node in targets do
		buildZone(ctx, node)
	end
end

--[=[ Removes one zone's parts and props (its terrain stays until the next build). ]=]
function Sections.Clear(id: string)
	assertEditMode()
	local folder = root():FindFirstChild(id)
	if folder then
		folder:Destroy()
	end
end

--[=[
	Starts the realm from empty: clears all terrain and the `World` folder, and moves the props of
	the old eroded-terrain pipeline (`Workspace.Nature`) to `ServerStorage.RetiredNature`, where
	they stay until the owner deletes them.
]=]
function Sections.Reset()
	assertEditMode()
	workspace.Terrain:Clear()
	local world = workspace:FindFirstChild(ROOT)
	if world then
		world:Destroy()
	end
	local nature = workspace:FindFirstChild("Nature")
	if nature then
		nature.Name = "RetiredNature"
		nature.Parent = ServerStorage
	end
end

-- Part settings per part name: material, collision and query.
local PART_RULES = {
	Trunk = { material = Enum.Material.Wood, collide = true, query = true },
	Canopy = { material = Enum.Material.Grass, collide = false, query = false },
	Rock = { material = Enum.Material.Slate, collide = true, query = true },
	Fruit = { material = Enum.Material.SmoothPlastic, collide = false, query = false },
	Bale = { material = Enum.Material.Grass, collide = true, query = true },
}

--[=[
	Imports the uploaded prop library (asset id from `PropsManifest`, written by
	tools/worldgen/props.py) into `ServerStorage.WorldProps`: one Model per variant holding its
	`Trunk`, `Canopy` or `Rock` MeshPart, pivoted at the base centre and scaled to the species
	height. Replaces any previous library. Rebuild zones afterwards to place the props.
]=]
function Sections.ImportProps(assetId: number?)
	assertEditMode()
	local id = assetId or tonumber((require(script.Parent:WaitForChild("PropsManifest")) :: any).assetId)
	assert(id, "no prop asset id; run tools/worldgen/props.py upload")
	local asset = InsertService:LoadAsset(id)

	local defs: { [string]: any } = {}
	for _, def in Realm.props.species :: { [string]: any } do
		defs[def.prefix] = def
	end
	defs[Realm.props.bushes.prefix] = Realm.props.bushes
	defs[Realm.props.boulders.prefix] = Realm.props.boulders
	for _, def in Realm.props.crops :: { [string]: any } do
		defs[def.prefix] = def
	end

	local variants: { [string]: Model } = {}
	for _, d in asset:GetDescendants() do
		if not d:IsA("MeshPart") then
			continue
		end
		local variant, partName = string.match(d.Name, "^(%a+%d%d)_(%a+)$")
		local prefix = variant and string.match(variant, "^%a+")
		local def = prefix and defs[prefix]
		local rule = partName and PART_RULES[partName]
		if not (variant and def and rule) then
			log:Warn("prop import: unexpected part %s", d.Name)
			continue
		end
		local model = variants[variant]
		if not model then
			local created = Instance.new("Model")
			created.Name = variant
			variants[variant] = created
			model = created
		end
		local part = d:Clone()
		part.Name = partName
		part.Anchored = true
		part.Material = rule.material
		local rgb = def.colors[partName]
		if rgb then
			part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		end
		part.CanCollide = rule.collide
		part.CanQuery = rule.query
		part.CanTouch = false
		part.CastShadow = true
		-- Fidelity is plugin-level; the command bar and Studio MCP may set it, plain scripts may not.
		local meshPart: any = part
		pcall(function()
			meshPart.CollisionFidelity = if rule.collide
				then Enum.CollisionFidelity.Hull
				else Enum.CollisionFidelity.Box
			meshPart.RenderFidelity = Enum.RenderFidelity.Automatic
		end)
		part.Parent = model
	end
	asset:Destroy()

	local old = ServerStorage:FindFirstChild(LIBRARY)
	if old then
		old:Destroy()
	end
	local library = Instance.new("Folder")
	library.Name = LIBRARY
	local count = 0
	for variant, model in variants do
		local def = defs[string.match(variant, "^%a+") :: string]
		local box, size = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(box.Position.X, box.Position.Y - size.Y / 2, box.Position.Z)
		model:ScaleTo(def.height / size.Y)
		model:PivotTo(CFrame.new())
		model.Parent = library
		count += 1
	end
	library.Parent = ServerStorage
	log:Info("imported %d prop variants from asset %d", count, id)
end

-- Gameplay parts added to village-kit templates at their manifest anchors. The tags, attributes
-- and effects are what SkillService looks for (Kindle and Purify spells). Templates carry the tag
-- as a `WORLD_TAG` attribute and only placed copies get the CollectionService tag, so a template
-- in ServerStorage is never a spell target.
local FUNCTIONAL: { [string]: (anchor: Vector3, radius: number) -> BasePart } = {
	water = function(anchor: Vector3, radius: number): BasePart
		local water = Instance.new("Part")
		water.Name = "Water"
		water.Shape = Enum.PartType.Cylinder
		water.Size = Vector3.new(0.4, radius * 2, radius * 2)
		water.CFrame = CFrame.new(anchor) * CFrame.Angles(0, 0, math.rad(90))
		water.Material = Enum.Material.Glass
		water.Color = Color3.fromRGB(60, 90, 70)
		water.Transparency = 0.2
		water.CanCollide = false
		water:SetAttribute(WORLD_TAG, "Purifiable")
		water:SetAttribute("Purified", false)
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Sparkle"
		sparkle.Enabled = false
		sparkle.Rate = 12
		sparkle.Lifetime = NumberRange.new(1, 2)
		sparkle.Speed = NumberRange.new(1, 2)
		sparkle.Parent = water
		local glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Enabled = false
		glow.Range = 12
		glow.Color = Color3.fromRGB(160, 220, 255)
		glow.Parent = water
		return water
	end,
	bowl = function(anchor: Vector3, radius: number): BasePart
		local bowl = Instance.new("Part")
		bowl.Name = "Bowl"
		bowl.Size = Vector3.new(radius * 2, 0.4, radius * 2)
		bowl.CFrame = CFrame.new(anchor)
		bowl.Transparency = 1
		bowl.CanCollide = false
		bowl:SetAttribute(WORLD_TAG, "Kindleable")
		bowl:SetAttribute("Lit", false)
		local flame = Instance.new("Fire")
		flame.Name = "Flame"
		flame.Enabled = false
		flame.Size = 4
		flame.Heat = 6
		flame.Parent = bowl
		local glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Enabled = false
		glow.Range = 18
		glow.Brightness = 2
		glow.Color = Color3.fromRGB(255, 170, 90)
		glow.Parent = bowl
		return bowl
	end,
}

-- Village-kit assets that are only decoration underfoot: no collision.
local WALK_THROUGH = { Border = true, BorderCorner = true }

--[=[
	Imports the uploaded village kit (asset id from `VillageManifest`, written by
	tools/worldgen/props.py) into `ServerStorage.VillageKit`. The upload arrives as one
	`<Asset>__<Material>_Node` model per asset and material, in metres; each asset becomes one Model
	of MeshParts named by material, pivoted at the asset origin (footprint centre on the ground,
	front towards the manifest's `front`) and scaled by `settlements.scale`. Materials without textures get the manifest colour
	and Roblox material; the well and braziers get their gameplay parts. Rebuild zones afterwards.
]=]
function Sections.ImportVillage(assetId: number?)
	assertEditMode()
	local manifest = require(script.Parent:WaitForChild("VillageManifest")) :: any
	local id = assetId or tonumber(manifest.assetId)
	assert(id, "no village asset id; run tools/worldgen/props.py upload --library village")
	local asset = InsertService:LoadAsset(id)
	local scale = Realm.settlements.scale

	local groups: { [string]: { BasePart } } = {}
	for _, node in asset:GetDescendants() do
		local name, material = string.match(node.Name, "^(.-)__(.-)_Node$")
		if not (name and material and node:IsA("Model")) then
			continue
		end
		for _, d in node:GetDescendants() do
			if d:IsA("MeshPart") then
				local part = d:Clone()
				part.Name = material
				groups[name] = groups[name] or {}
				table.insert(groups[name], part)
			end
		end
	end
	asset:Destroy()

	local old = ServerStorage:FindFirstChild(VILLAGE_KIT)
	if old then
		old:Destroy()
	end
	local library = Instance.new("Folder")
	library.Name = VILLAGE_KIT
	local count = 0
	for name, parts in groups do
		local meta = manifest.assets[name]
		if not meta then
			log:Warn("village import: %s is not in the manifest", name)
			continue
		end
		local model = Instance.new("Model")
		model.Name = name
		for _, part in parts do
			local info = manifest.materials[part.Name] or {}
			part.Anchored = true
			part.CanTouch = false
			part.CanCollide = not WALK_THROUGH[name] and part.Name ~= "MI_Vine"
			part.CanQuery = part.CanCollide
			local surface = part:FindFirstChildOfClass("SurfaceAppearance")
			if not info.textured and surface then
				surface:Destroy()
				surface = nil
			end
			if info.material then
				part.Material = (Enum.Material :: any)[info.material]
			end
			if not info.textured or info.material then
				local rgb = info.color or { 200, 200, 200 }
				part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
			end
			part.Transparency = info.transparency or 0
			if surface and info.alphaMode then
				surface.AlphaMode = (Enum.AlphaMode :: any)[info.alphaMode]
			end
			if surface and info.tint then
				surface.Color = Color3.fromRGB(info.tint[1], info.tint[2], info.tint[3])
			end
			part.Parent = model
		end
		-- The upload keeps metres as studs; the asset origin is the bounds centre minus the
		-- manifest's bounds centre.
		local box = model:GetBoundingBox()
		local centre = Vector3.new(
			(meta.min[1] + meta.max[1]) / 2,
			(meta.min[2] + meta.max[2]) / 2,
			(meta.min[3] + meta.max[3]) / 2
		)
		model.WorldPivot = CFrame.new(box.Position - centre)
		model:ScaleTo(scale)
		model:PivotTo(CFrame.new())
		for key, value in meta.anchors do
			local make = FUNCTIONAL[key]
			if make and type(value) == "table" then
				local radius = (meta.anchors[key .. "Radius"] or 0.5) * scale
				local functional = make(Vector3.new(value[1], value[2], value[3]) * scale, radius)
				functional.Anchored = true
				functional.CanTouch = false
				functional.Parent = model
			end
		end
		model.Parent = library
		count += 1
	end
	library.Parent = ServerStorage
	log:Info("imported %d village-kit assets from asset %d", count, id)
end

local VIEW_HEIGHT = 28 -- studs above the ground at the zone's site
local VIEW_REACH = 220 -- studs to the look-at point

--[=[
	Points the edit camera across a zone towards north, east, south or west (`k` 1 to 4): from a
	point behind the site, `VIEW_HEIGHT` above the generated ground and clear of parts, with a
	slight downward tilt. Bookmarks follow the
	geometry, so they stay valid when a zone changes. Returns the camera position and target.
]=]
function Sections.View(id: string, k: number?): (Vector3, Vector3)
	local graph = Graph.build(Realm)
	local field = Field.new(graph)
	local node = graph.byId[id]
	assert(node, `unknown zone {id}`)
	local angle = ((k or 1) - 1) * math.pi / 2
	local dx, dz = math.sin(angle), -math.cos(angle)
	-- Stand back from the site, then rise until no part is within a few studs of the lens.
	local x, z = node.x - dx * node.r * 0.35, node.z - dz * node.r * 0.35
	local from = Vector3.new(x, field.height(x, z) + VIEW_HEIGHT, z)
	for _ = 1, 30 do
		if #workspace:GetPartBoundsInRadius(from, 8) == 0 then
			break
		end
		from += Vector3.new(0, 8, 0)
	end
	local tx, tz = node.x + dx * VIEW_REACH, node.z + dz * VIEW_REACH
	local to = Vector3.new(tx, from.Y - VIEW_HEIGHT * 0.6, tz)
	workspace.CurrentCamera.CFrame = CFrame.lookAt(from, to)
	return from, to
end

return Sections
