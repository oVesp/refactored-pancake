--!strict

--[=[
	Studio applier for the generated Midgard world (docs/systems/world-generation.md). Reads the
	modules in `Data` written by `lune run tools/terrain/build` and writes terrain voxels and the
	prop scatter. Edit mode only; run from the command bar or Studio MCP:

	```lua
	require(game.ServerStorage.WorldGen.Apply).Apply()
	```

	Save a copy of the place first: Roblox does not guarantee undo for large terrain writes.
]=]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Logger = require(ReplicatedStorage.Shared.Logger)

local log = Logger.new("WorldGen")
local Data = script.Parent:WaitForChild("Data")

local PACK_NAME = "Nature MEGAPACK"
local ROOT_NAME = "Nature"
local TILE_COLUMNS = 64
local CHUNK_STUDS = 256
local VOXEL = 4

type Asset = {
	name: string,
	group: string,
	layer: string,
	collide: string,
	shadow: boolean,
	sink: number,
}

type Meta = {
	seed: number,
	originX: number,
	originZ: number,
	n: number,
	cell: number,
	floorY: number,
	chunkRows: number,
	chunks: number,
	materials: { string },
	materialColors: { [string]: { number } },
	assets: { Asset },
	layers: { { name: string, modules: { string }, count: number } },
	pois: { { name: string, x: number, y: number, z: number } },
}

local WorldGen = {}

local function assertEditMode()
	assert(RunService:IsStudio() and not RunService:IsRunning(), "WorldGen runs in Studio edit mode only")
end

local function meta(): Meta
	return require(Data:WaitForChild("Meta")) :: any
end

local DECODE: { [number]: number } = {}
do
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for k = 1, #alphabet do
		DECODE[string.byte(alphabet, k)] = k - 1
	end
end

local function decodeBase64(text: string, out: buffer, offset: number): number
	local o = offset
	for k = 1, #text, 4 do
		local a, b, c, d = string.byte(text, k, k + 3)
		local v = bit32.lshift(DECODE[a], 18) + bit32.lshift(DECODE[b], 12)
		buffer.writeu8(out, o, bit32.rshift(v, 16))
		o += 1
		if c ~= 61 then
			v += bit32.lshift(DECODE[c], 6)
			buffer.writeu8(out, o, bit32.band(bit32.rshift(v, 8), 0xFF))
			o += 1
			if d ~= 61 then
				v += DECODE[d]
				buffer.writeu8(out, o, bit32.band(v, 0xFF))
				o += 1
			end
		end
	end
	return o
end

local function decodeHeight(v: number): number
	return v / 16 - 128
end

local function hash01(a: number, b: number): number
	local h = bit32.bxor((a * 73856093) % 4294967296, (b * 19349663) % 4294967296)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1274126177) % 4294967296
	return bit32.bxor(h, bit32.rshift(h, 16)) % 65536 / 65536
end

--[=[
	Writes the generated terrain, 64 x 64 voxel columns per call. The data grid (`cell` studs) is
	upsampled to 4-stud voxels: heights and water bilinearly, materials by a hashed pick among the
	four neighbouring cells so borders dither instead of stepping. Each block is filled from a
	little below its lowest column, not from `floorY`, to keep mountain writes small.
]=]
function WorldGen.ApplyTerrain()
	assertEditMode()
	local m = meta()
	local n = m.n
	local columns = buffer.create(n * n * 5)
	local offset = 0
	for c = 1, m.chunks do
		local text = require(Data:WaitForChild(string.format("Terrain%02d", c))) :: any
		offset = decodeBase64(text, columns, offset)
	end
	assert(offset == n * n * 5, "terrain data is incomplete; rerun tools/terrain/build")

	local terrain = workspace.Terrain
	for name, rgb in m.materialColors do
		terrain:SetMaterialColor((Enum.Material :: any)[name], Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
	end
	local palette: { Enum.Material } = {}
	for k, name in m.materials do
		palette[k] = (Enum.Material :: any)[name]
	end
	local air, ground, rock = Enum.Material.Air, Enum.Material.Ground, Enum.Material.Rock
	local keepDeep = {
		[Enum.Material.Rock] = true,
		[Enum.Material.Slate] = true,
		[Enum.Material.Sandstone] = true,
		[Enum.Material.Glacier] = true,
	}

	local function cellIndex(i: number, j: number): number
		return (math.clamp(i, 0, n - 1) + math.clamp(j, 0, n - 1) * n) * 5
	end
	local voxels = n * m.cell // VOXEL
	local perCell = m.cell / VOXEL
	local tiles = voxels // TILE_COLUMNS
	local hs = table.create(TILE_COLUMNS * TILE_COLUMNS)
	local ws = table.create(TILE_COLUMNS * TILE_COLUMNS)
	local ms = table.create(TILE_COLUMNS * TILE_COLUMNS)
	local started = os.clock()
	for tj = 0, tiles - 1 do
		for ti = 0, tiles - 1 do
			local top, low = -math.huge, math.huge
			for iz = 1, TILE_COLUMNS do
				local vz = tj * TILE_COLUMNS + iz - 1
				local fj = (vz + 0.5) / perCell - 0.5
				local j0 = math.floor(fj)
				local tz = fj - j0
				for ix = 1, TILE_COLUMNS do
					local vx = ti * TILE_COLUMNS + ix - 1
					local fi = (vx + 0.5) / perCell - 0.5
					local i0 = math.floor(fi)
					local tx = fi - i0
					local o00, o10 = cellIndex(i0, j0), cellIndex(i0 + 1, j0)
					local o01, o11 = cellIndex(i0, j0 + 1), cellIndex(i0 + 1, j0 + 1)
					local w00, w10 = (1 - tx) * (1 - tz), tx * (1 - tz)
					local w01, w11 = (1 - tx) * tz, tx * tz
					local h = decodeHeight(buffer.readu16(columns, o00)) * w00
						+ decodeHeight(buffer.readu16(columns, o10)) * w10
						+ decodeHeight(buffer.readu16(columns, o01)) * w01
						+ decodeHeight(buffer.readu16(columns, o11)) * w11
					-- Water: bilinear where all four cells are wet, else the highest wet neighbour
					-- (shore columns sit above it anyway).
					local r00, r10 = buffer.readu16(columns, o00 + 3), buffer.readu16(columns, o10 + 3)
					local r01, r11 = buffer.readu16(columns, o01 + 3), buffer.readu16(columns, o11 + 3)
					local w = -math.huge
					if r00 > 0 and r10 > 0 and r01 > 0 and r11 > 0 then
						w = decodeHeight(r00) * w00
							+ decodeHeight(r10) * w10
							+ decodeHeight(r01) * w01
							+ decodeHeight(r11) * w11
					elseif r00 > 0 or r10 > 0 or r01 > 0 or r11 > 0 then
						w = decodeHeight(math.max(r00, r10, r01, r11))
					end
					local roll = hash01(vx, vz)
					local pick = if roll < w00
						then o00
						elseif roll < w00 + w10 then o10
						elseif roll < w00 + w10 + w01 then o01
						else o11
					local k = ix + (iz - 1) * TILE_COLUMNS
					hs[k], ws[k], ms[k] = h, w, palette[buffer.readu8(columns, pick + 2)]
					top = math.max(top, h, w)
					low = math.min(low, h)
				end
			end
			local floorY = m.floorY + math.max(0, math.floor((low - 24 - m.floorY) / VOXEL)) * VOXEL
			local layers = math.ceil((top - floorY) / VOXEL) + 1
			local x0 = m.originX + ti * TILE_COLUMNS * VOXEL
			local z0 = m.originZ + tj * TILE_COLUMNS * VOXEL
			local region = Region3.new(
				Vector3.new(x0, floorY, z0),
				Vector3.new(x0 + TILE_COLUMNS * VOXEL, floorY + layers * VOXEL, z0 + TILE_COLUMNS * VOXEL)
			)
			local materials = table.create(TILE_COLUMNS)
			local solids = table.create(TILE_COLUMNS)
			local liquids = table.create(TILE_COLUMNS)
			for ix = 1, TILE_COLUMNS do
				local matX, solidX, liquidX = table.create(layers), table.create(layers), table.create(layers)
				for iy = 1, layers do
					matX[iy] = table.create(TILE_COLUMNS)
					solidX[iy] = table.create(TILE_COLUMNS)
					liquidX[iy] = table.create(TILE_COLUMNS)
				end
				materials[ix], solids[ix], liquids[ix] = matX, solidX, liquidX
			end
			for iz = 1, TILE_COLUMNS do
				for ix = 1, TILE_COLUMNS do
					local k = ix + (iz - 1) * TILE_COLUMNS
					local h, w, surface = hs[k], ws[k], ms[k]
					local deepMaterial = if keepDeep[surface] then surface else ground
					for iy = 1, layers do
						local bottom = floorY + (iy - 1) * VOXEL
						local solid = math.clamp((h - bottom) / VOXEL, 0, 1)
						local depth = h - (bottom + VOXEL / 2)
						local material = air
						if solid > 0 then
							material = if depth < 6 then surface elseif depth < 16 then deepMaterial else rock
						end
						materials[ix][iy][iz] = material
						solids[ix][iy][iz] = solid
						liquids[ix][iy][iz] = if solid < 1 then math.clamp((w - bottom) / VOXEL, 0, 1) else 0
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
		log:Info("terrain row %d/%d written", tj + 1, tiles)
	end
	log:Info("terrain applied in %.1fs", os.clock() - started)
end

local function prepareTemplate(source: Model, asset: Asset): Model
	local template = source:Clone()
	local boxCFrame, boxSize = template:GetBoundingBox()
	template.WorldPivot = CFrame.new(boxCFrame.Position - Vector3.new(0, boxSize.Y / 2, 0))
	local trunk: BasePart? = nil
	if asset.collide == "trunk" then
		-- The trunk is the part with the tallest height-to-width ratio.
		local best = 0
		for _, d in template:GetDescendants() do
			if d:IsA("BasePart") then
				local ratio = d.Size.Y / math.max(d.Size.X, d.Size.Z)
				if ratio > best then
					best = ratio
					trunk = d
				end
			end
		end
	end
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			local collides = asset.collide == "all" or d == trunk
			d.Anchored = true
			d.CanCollide = collides
			d.CanQuery = collides
			d.CanTouch = false
			d.CastShadow = asset.shadow
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	template:SetAttribute("Height", boxSize.Y)
	return template
end

type Box = { x0: number, z0: number, x1: number, z1: number }

local function protectedBoxes(root: Instance): { Box }
	local boxes: { Box } = {}
	local function add(instance: Instance)
		local cf: CFrame, size: Vector3
		if instance:IsA("Model") then
			cf, size = instance:GetBoundingBox()
		elseif instance:IsA("BasePart") then
			cf, size = instance.CFrame, instance.Size
		else
			return
		end
		local half = math.max(size.X, size.Z) / 2
		table.insert(boxes, { x0 = cf.X - half, z0 = cf.Z - half, x1 = cf.X + half, z1 = cf.Z + half })
	end
	for _, d in root:GetDescendants() do
		if d:GetAttribute("Locked") == true then
			add(d)
		end
	end
	for _, tagged in CollectionService:GetTagged("ScatterExclude") do
		add(tagged)
	end
	return boxes
end

local function parseLines(text: string): { { number } }
	local rows: { { number } } = {}
	for line in string.gmatch(text, "[^\n]+") do
		local a, x, y, z, yaw, ux, uz, s = string.match(line, "^(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)$")
		if a then
			table.insert(rows, {
				tonumber(a) :: number,
				tonumber(x) :: number,
				tonumber(y) :: number,
				tonumber(z) :: number,
				tonumber(yaw) :: number,
				tonumber(ux) :: number,
				tonumber(uz) :: number,
				tonumber(s) :: number,
			})
		end
	end
	return rows
end

--[=[
	Places the props under `Workspace.Nature/<Layer>/<chunk>`. Regenerating removes earlier
	generated props but keeps anything with the attribute `Locked = true` and skips placements
	that fall on locked items or parts tagged `ScatterExclude`.
]=]
function WorldGen.ApplyScatter(layerNames: { string }?)
	assertEditMode()
	local m = meta()
	local pack = ServerStorage:FindFirstChild(PACK_NAME)
	assert(pack, `ServerStorage.{PACK_NAME} is missing`)

	local root = workspace:FindFirstChild(ROOT_NAME)
	if not root then
		local folder = Instance.new("Folder")
		folder.Name = ROOT_NAME
		folder.Parent = workspace
		root = folder
	end
	assert(root, "WorldGen root folder missing")
	root:SetAttribute("WorldGenSeed", m.seed)
	local boxes = protectedBoxes(root)

	local templates: { [number]: Model } = {}
	local missing: { string } = {}
	for k, asset in m.assets do
		local source = pack:FindFirstChild(asset.name)
		if source and source:IsA("Model") and #source:GetChildren() > 0 then
			templates[k] = prepareTemplate(source, asset)
		else
			table.insert(missing, asset.name)
		end
	end
	if #missing > 0 then
		log:Warn("skipping %d assets missing from the pack: %s", #missing, table.concat(missing, ", "))
	end

	local started = os.clock()
	local placed, skipped = 0, 0
	for _, layer in m.layers do
		if layerNames == nil or table.find(layerNames, layer.name) then
			local layerFolder = root:FindFirstChild(layer.name)
			if layerFolder then
				for _, d in layerFolder:GetDescendants() do
					if d:IsA("Model") and d:GetAttribute("Locked") ~= true then
						d:Destroy()
					end
				end
			else
				local folder = Instance.new("Folder")
				folder.Name = layer.name
				folder.Parent = root
				layerFolder = folder
			end
			assert(layerFolder, "WorldGen layer folder missing")

			local byChunk: { [string]: { { number } } } = {}
			for _, module in layer.modules do
				for _, row in parseLines(require(Data:WaitForChild(module)) :: any) do
					local key = string.format("%d_%d", row[2] // CHUNK_STUDS, row[4] // CHUNK_STUDS)
					local list = byChunk[key]
					if not list then
						list = {}
						byChunk[key] = list
					end
					table.insert(list, row)
				end
			end
			local keys = {}
			for key in byChunk do
				table.insert(keys, key)
			end
			table.sort(keys)

			for _, key in keys do
				local chunk = layerFolder:FindFirstChild(key)
				local fresh = chunk == nil
				if not chunk then
					local folder = Instance.new("Folder")
					folder.Name = key
					chunk = folder
				end
				assert(chunk, "WorldGen chunk folder missing")
				for _, row in byChunk[key] do
					local template = templates[row[1]]
					local x, y, z = row[2], row[3], row[4]
					local blocked = false
					for _, b in boxes do
						if x >= b.x0 and x <= b.x1 and z >= b.z0 and z <= b.z1 then
							blocked = true
							break
						end
					end
					if template and not blocked then
						local asset = m.assets[row[1]]
						local scale = row[8]
						local up = Vector3.new(row[6], math.sqrt(math.max(0, 1 - row[6] ^ 2 - row[7] ^ 2)), row[7])
						local tilt = CFrame.identity
						local axis = Vector3.new(up.Z, 0, -up.X) -- yAxis x up
						if axis.Magnitude > 1e-4 then
							tilt = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(up.Y, -1, 1)))
						end
						local sink = (template:GetAttribute("Height") :: number) * scale * asset.sink
						local model = template:Clone()
						model:SetAttribute("Height", nil)
						if scale ~= 1 then
							model:ScaleTo(scale)
						end
						model:PivotTo(
							CFrame.new(x, y, z) * tilt * CFrame.new(0, -sink, 0) * CFrame.Angles(0, math.rad(row[5]), 0)
						)
						model.Parent = chunk
						placed += 1
					else
						skipped += 1
					end
				end
				if fresh then
					chunk.Parent = layerFolder
				end
				task.wait()
			end
			log:Info("layer %s placed", layer.name)
		end
	end
	for _, template in templates do
		template:Destroy()
	end
	log:Info("scatter: %d props placed, %d skipped in %.1fs", placed, skipped, os.clock() - started)
end

--[=[ Markers for the generated lookout sites, tagged `PoiSite` for later content. ]=]
function WorldGen.ApplyPois()
	assertEditMode()
	local m = meta()
	local root = workspace:FindFirstChild(ROOT_NAME) or Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = workspace
	local folder = root:FindFirstChild("PoiSites") or Instance.new("Folder")
	folder.Name = "PoiSites"
	folder:ClearAllChildren()
	for _, poi in m.pois do
		local marker = Instance.new("Part")
		marker.Name = poi.name
		marker.Size = Vector3.new(4, 1, 4)
		marker.CFrame = CFrame.new(poi.x, poi.y + 0.5, poi.z)
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CanTouch = false
		marker.Transparency = 1
		marker:AddTag("PoiSite")
		marker.Parent = folder
	end
	folder.Parent = root
end

--[=[ Terrain, props and markers in one go. ]=]
function WorldGen.Apply()
	WorldGen.ApplyTerrain()
	WorldGen.ApplyScatter()
	WorldGen.ApplyPois()
end

--[=[ Removes the generated terrain and every unlocked generated prop. ]=]
function WorldGen.Clear()
	assertEditMode()
	local m = meta()
	local step = TILE_COLUMNS * VOXEL
	for z0 = m.originZ, m.originZ + m.n * m.cell - step, step do
		for x0 = m.originX, m.originX + m.n * m.cell - step, step do
			local region =
				Region3.new(Vector3.new(x0, m.floorY, z0), Vector3.new(x0 + step, m.floorY + 1024, z0 + step))
			workspace.Terrain:FillRegion(region, VOXEL, Enum.Material.Air)
			task.wait()
		end
	end
	local root = workspace:FindFirstChild(ROOT_NAME)
	if root then
		for _, d in root:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("Locked") ~= true then
				d:Destroy()
			end
		end
	end
end

return WorldGen
