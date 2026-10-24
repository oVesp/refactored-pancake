--!strict

-- Generates the M0.5 greybox world and NPC templates as Rojo model files.
-- Run from the repo root: `lune run tools/world/build`. Output is deterministic; commit it.
-- Greybox uses Roblox materials only; Kenney meshes replace props once uploads are possible.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

-- Top of every ground slab; sits just above a default baseplate to avoid z-fighting.
local G = 0.2

type Props = { [string]: any }

local function make(className: string, props: Props, parent: any?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key == "Tags" then
			for _, tag in value do
				instance:AddTag(tag)
			end
		elseif key == "Attributes" then
			for name, attr in value do
				instance:SetAttribute(name, attr)
			end
		else
			instance[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function part(parent: any, name: string, size: any, cframe: any, color: any, material: any, extra: Props?): any
	local props: Props = {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material,
		Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
	for key, value in extra or {} do
		props[key] = value
	end
	return make("Part", props, parent)
end

local function folder(parent: any, name: string): any
	return make("Folder", { Name = name }, parent)
end

local function model(parent: any, name: string): any
	return make("Model", { Name = name }, parent)
end

local function at(x: number, y: number, z: number): any
	return CFrame.new(x, y, z)
end

local function rgb(r: number, g: number, b: number): any
	return Color3.fromRGB(r, g, b)
end

local COLORS = {
	grass = rgb(98, 140, 72),
	field = rgb(120, 150, 70),
	orchard = rgb(86, 128, 66),
	mud = rgb(110, 92, 70),
	dirt = rgb(130, 105, 75),
	stone = rgb(150, 150, 145),
	wood = rgb(120, 85, 55),
	darkWood = rgb(80, 58, 40),
	roof = rgb(150, 70, 50),
	thatch = rgb(190, 165, 95),
	wheat = rgb(215, 190, 100),
	leaf = rgb(70, 125, 55),
	canvas = rgb(150, 130, 100),
	devFloor = rgb(70, 75, 85),
	devLine = rgb(230, 200, 60),
}

local map = model(nil, "Map")
local groundFolder = folder(map, "Ground")
local zoneFolder = folder(map, "Zones")
local spawnerFolder = folder(map, "Spawners")
local npcFolder = folder(map, "Npcs")
local propFolder = folder(map, "Props")

-- Areas: id, zone id, center X/Z, size X/Z, color, material
local AREAS = {
	{ "VillageCore", "village_core", 0, 0, 180, 180, COLORS.grass, Enum.Material.Grass },
	{ "DevYard", "dev_yard", -165, 0, 150, 180, COLORS.devFloor, Enum.Material.SmoothPlastic },
	{ "WheatFields", "wheat_fields", 0, -205, 220, 230, COLORS.field, Enum.Material.Grass },
	{ "OrchardEdge", "orchard_edge", 0, -440, 220, 240, COLORS.orchard, Enum.Material.LeafyGrass },
	{ "GoblinCamp", "goblin_camp", 0, -660, 200, 200, COLORS.mud, Enum.Material.Mud },
}

for _, area in AREAS do
	local name, zoneId, x, z, sx, sz, color, material = table.unpack(area)
	part(groundFolder, name, Vector3.new(sx, 2, sz), at(x, G - 1, z), color, material)
	part(zoneFolder, name, Vector3.new(sx, 80, sz), at(x, G + 40, z), Color3.new(1, 1, 1), Enum.Material.ForceField, {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Tags = { "Zone" },
		Attributes = { ZoneId = zoneId },
	})
end

-- North road from the village to the camp gate
part(groundFolder, "Road", Vector3.new(12, 2, 670), at(0, G - 0.95, -425), COLORS.dirt, Enum.Material.Ground)

local function house(parent: any, name: string, x: number, z: number, rotation: number)
	local m = model(parent, name)
	local base = CFrame.new(x, G, z) * CFrame.Angles(0, math.rad(rotation), 0)
	part(m, "Walls", Vector3.new(16, 10, 12), base * CFrame.new(0, 5, 0), COLORS.wood, Enum.Material.WoodPlanks)
	part(m, "Door", Vector3.new(4, 7, 0.4), base * CFrame.new(0, 3.5, 6.1), COLORS.darkWood, Enum.Material.Wood)
	local roofProps = { Color = COLORS.roof, Material = Enum.Material.Slate }
	make("WedgePart", {
		Name = "RoofFront",
		Size = Vector3.new(17, 5, 7),
		CFrame = base * CFrame.new(0, 12.5, 3.5),
		Anchored = true,
		Color = roofProps.Color,
		Material = roofProps.Material,
	}, m)
	make("WedgePart", {
		Name = "RoofBack",
		Size = Vector3.new(17, 5, 7),
		CFrame = base * CFrame.new(0, 12.5, -3.5) * CFrame.Angles(0, math.rad(180), 0),
		Anchored = true,
		Color = roofProps.Color,
		Material = roofProps.Material,
	}, m)
end

local function fenceLine(parent: any, name: string, x1: number, z1: number, x2: number, z2: number)
	local m = model(parent, name)
	local dx, dz = x2 - x1, z2 - z1
	local length = math.sqrt(dx * dx + dz * dz)
	local center = CFrame.new((x1 + x2) / 2, G, (z1 + z2) / 2) * CFrame.Angles(0, math.atan2(-dx, -dz), 0)
	part(m, "RailTop", Vector3.new(0.4, 0.4, length), center * CFrame.new(0, 3, 0), COLORS.wood, Enum.Material.Wood)
	part(m, "RailLow", Vector3.new(0.4, 0.4, length), center * CFrame.new(0, 1.5, 0), COLORS.wood, Enum.Material.Wood)
	local posts = math.max(2, math.floor(length / 8) + 1)
	for i = 0, posts - 1 do
		local offset = -length / 2 + i * length / (posts - 1)
		part(
			m,
			"Post",
			Vector3.new(0.6, 4, 0.6),
			center * CFrame.new(0, 2, offset),
			COLORS.darkWood,
			Enum.Material.Wood
		)
	end
end

local function tree(parent: any, x: number, z: number, height: number)
	local m = model(parent, "Tree")
	part(
		m,
		"Trunk",
		Vector3.new(height, 1.6, 1.6),
		CFrame.new(x, G + height / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
		COLORS.darkWood,
		Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder }
	)
	part(
		m,
		"Canopy",
		Vector3.new(9, 9, 9),
		at(x, G + height + 2.5, z),
		COLORS.leaf,
		Enum.Material.Grass,
		{ Shape = Enum.PartType.Ball }
	)
end

local function brazier(parent: any, name: string, x: number, z: number)
	local m = model(parent, name)
	part(m, "Stand", Vector3.new(1, 3, 1), at(x, G + 1.5, z), COLORS.stone, Enum.Material.Slate)
	local bowl = part(m, "Bowl", Vector3.new(3, 1, 3), at(x, G + 3.5, z), COLORS.stone, Enum.Material.Slate, {
		Tags = { "Kindleable" },
		Attributes = { Lit = false },
	})
	make("Fire", { Name = "Flame", Enabled = false, Size = 4, Heat = 6 }, bowl)
	make("PointLight", { Name = "Glow", Enabled = false, Range = 18, Brightness = 2, Color = rgb(255, 170, 90) }, bowl)
end

local function well(parent: any, name: string, x: number, z: number)
	local m = model(parent, name)
	part(
		m,
		"Ring",
		Vector3.new(3, 8, 8),
		CFrame.new(x, G + 1.5, z) * CFrame.Angles(0, 0, math.rad(90)),
		COLORS.stone,
		Enum.Material.Cobblestone,
		{ Shape = Enum.PartType.Cylinder }
	)
	local water = part(
		m,
		"Water",
		Vector3.new(0.4, 6.5, 6.5),
		CFrame.new(x, G + 2.8, z) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(60, 90, 70),
		Enum.Material.Glass,
		{
			Shape = Enum.PartType.Cylinder,
			Transparency = 0.2,
			Tags = { "Purifiable" },
			Attributes = { Purified = false },
		}
	)
	make("ParticleEmitter", {
		Name = "Sparkle",
		Enabled = false,
		Rate = 12,
		Lifetime = roblox.NumberRange.new(1, 2),
		Speed = roblox.NumberRange.new(1, 2),
	}, water)
	make("PointLight", { Name = "Glow", Enabled = false, Range = 12, Color = rgb(160, 220, 255) }, water)
	part(m, "PostA", Vector3.new(0.6, 7, 0.6), at(x - 3.5, G + 3.5, z), COLORS.darkWood, Enum.Material.Wood)
	part(m, "PostB", Vector3.new(0.6, 7, 0.6), at(x + 3.5, G + 3.5, z), COLORS.darkWood, Enum.Material.Wood)
	part(m, "Beam", Vector3.new(8, 0.6, 0.6), at(x, G + 7, z), COLORS.darkWood, Enum.Material.Wood)
end

local function trainer(
	parent: any,
	name: string,
	x: number,
	z: number,
	color: any,
	attributes: { [string]: any },
	action: string
)
	local m = model(parent, name)
	part(m, "Body", Vector3.new(2, 4, 1.2), at(x, G + 3, z), color, Enum.Material.SmoothPlastic)
	part(m, "Head", Vector3.new(1.4, 1.4, 1.4), at(x, G + 5.7, z), rgb(234, 190, 150), Enum.Material.SmoothPlastic)
	part(m, "Plinth", Vector3.new(4, 1, 4), at(x, G + 0.5, z), COLORS.stone, Enum.Material.Slate)
	local body = m:FindFirstChild("Body")
	body:AddTag("Trainer")
	for key, value in attributes do
		body:SetAttribute(key, value)
	end
	make("ProximityPrompt", {
		Name = "TrainPrompt",
		ActionText = action,
		ObjectText = name,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
		HoldDuration = 0.3,
	}, body)
end

-- Village Core
local village = folder(propFolder, "Village")
make("SpawnLocation", {
	Name = "VillageSpawn",
	Size = Vector3.new(8, 1, 8),
	CFrame = at(0, G + 0.5, 20),
	Anchored = true,
	Neutral = true,
	Duration = 0,
	Color = COLORS.stone,
	Material = Enum.Material.Slate,
	Tags = { "RespawnPoint" },
}, map)
part(village, "Plaza", Vector3.new(60, 0.4, 60), at(0, G + 0.2, 0), COLORS.stone, Enum.Material.Cobblestone)
well(village, "VillageWell", 0, -6)
brazier(village, "VillageBrazierWest", -14, 8)
brazier(village, "VillageBrazierEast", 14, 8)
house(village, "HouseA", -55, -50, 0)
house(village, "HouseB", 55, -50, 0)
house(village, "HouseC", -60, 30, 90)
house(village, "HouseD", 60, 30, -90)
house(village, "HouseE", -30, 60, 180)
house(village, "HouseF", 30, 60, 180)
part(village, "Barn", Vector3.new(24, 14, 18), at(65, G + 7, 70), rgb(140, 50, 40), Enum.Material.WoodPlanks)
part(village, "HayBale", Vector3.new(4, 3, 3), at(50, G + 1.5, 75), COLORS.thatch, Enum.Material.Fabric)
fenceLine(village, "FenceSouth", -88, 88, 88, 88)
fenceLine(village, "FenceEast", 88, 88, 88, -88)
fenceLine(village, "FenceNorthWest", -88, -88, -10, -88)
fenceLine(village, "FenceNorthEast", 10, -88, 88, -88)

trainer(
	npcFolder,
	"Warrior Trainer",
	-24,
	30,
	rgb(150, 60, 50),
	{ TrainerType = "Class", ClassId = "warrior" },
	"Train Warrior"
)
trainer(npcFolder, "Mage Trainer", 0, 38, rgb(60, 80, 160), { TrainerType = "Class", ClassId = "mage" }, "Train Mage")
trainer(
	npcFolder,
	"Healer Trainer",
	24,
	30,
	rgb(230, 230, 210),
	{ TrainerType = "Class", ClassId = "healer" },
	"Train Healer"
)
trainer(
	npcFolder,
	"Discipline Trainer",
	-30,
	-20,
	rgb(120, 110, 80),
	{ TrainerType = "Discipline" },
	"Learn Disciplines"
)
trainer(npcFolder, "Vendor", 30, -20, rgb(170, 140, 60), { TrainerType = "Vendor" }, "Browse (not in M0.5)")

-- Dev Yard
local dev = folder(propFolder, "DevYard")
local DUMMIES = {
	{ "Dummy Plain", -200, -60, { Level = 1 } },
	{ "Dummy Level 5", -185, -60, { Level = 5 } },
	{ "Dummy Level 10", -170, -60, { Level = 10 } },
	{ "Dummy Resist Physical", -155, -60, { Level = 1, Resist = "physical" } },
	{ "Dummy Vulnerable Holy", -140, -60, { Level = 1, Vulnerable = "holy" } },
	{ "Dummy Immune Fire", -125, -60, { Level = 1, Immune = "fire" } },
}
for _, entry in DUMMIES do
	local name, x, z, attributes = entry[1], entry[2], entry[3], entry[4]
	local m = model(dev, name)
	part(m, "Post", Vector3.new(0.8, 3, 0.8), at(x, G + 1.5, z), COLORS.darkWood, Enum.Material.Wood)
	local body =
		part(m, "Body", Vector3.new(2.2, 3.4, 1.4), at(x, G + 4.7, z), rgb(190, 160, 110), Enum.Material.Fabric)
	part(m, "Head", Vector3.new(1.6, 1.6, 1.6), at(x, G + 7.2, z), rgb(190, 160, 110), Enum.Material.Fabric)
	m.PrimaryPart = body
	m:AddTag("TrainingDummy")
	for key, value in attributes do
		m:SetAttribute(key, value)
	end
end
-- Lag test lane: a dummy that slides back and forth along the lane
part(dev, "LagLane", Vector3.new(8, 0.3, 80), at(-220, G + 0.15, 20), COLORS.devLine, Enum.Material.SmoothPlastic)
for i = 0, 8 do
	part(
		dev,
		"LaneMark",
		Vector3.new(8.4, 0.35, 0.6),
		at(-220, G + 0.18, -20 + i * 10),
		rgb(30, 30, 30),
		Enum.Material.SmoothPlastic
	)
end
do
	local m = model(dev, "Dummy Moving")
	local body =
		part(m, "Body", Vector3.new(2.2, 5, 1.4), at(-220, G + 2.5, 20), rgb(200, 120, 90), Enum.Material.Fabric)
	m.PrimaryPart = body
	m:AddTag("TrainingDummy")
	m:SetAttribute("Level", 1)
	m:SetAttribute("LaneLength", 70)
	m:SetAttribute("LaneSpeed", 12)
end
for i, x in { -150, -130, -110 } do
	part(dev, "SpawnPad" .. i, Vector3.new(10, 0.4, 10), at(x, G + 0.2, 50), rgb(90, 40, 120), Enum.Material.Neon, {
		Tags = { "DevSpawnPad" },
	})
end

-- Wheat Fields
local fields = folder(propFolder, "WheatFields")
for row = 0, 11 do
	for _, side in { -1, 1 } do
		local x = side * (25 + row * 7)
		part(
			fields,
			"WheatRow",
			Vector3.new(3, 2.5, 60),
			at(x, G + 1.25, -170),
			COLORS.wheat,
			Enum.Material.Grass,
			{ CanCollide = false }
		)
		part(
			fields,
			"WheatRow",
			Vector3.new(3, 2.5, 60),
			at(x, G + 1.25, -250),
			COLORS.wheat,
			Enum.Material.Grass,
			{ CanCollide = false }
		)
	end
end
for i, pos in { { -40, -210 }, { 45, -150 }, { 60, -280 } } do
	local m = model(fields, "Scarecrow" .. i)
	part(m, "Pole", Vector3.new(0.6, 8, 0.6), at(pos[1], G + 4, pos[2]), COLORS.darkWood, Enum.Material.Wood)
	part(m, "Arms", Vector3.new(6, 0.5, 0.5), at(pos[1], G + 6, pos[2]), COLORS.darkWood, Enum.Material.Wood)
	part(m, "Sack", Vector3.new(2.5, 3, 1.5), at(pos[1], G + 5, pos[2]), COLORS.thatch, Enum.Material.Fabric)
end
fenceLine(fields, "FieldFenceWest", -108, -100, -108, -315)
fenceLine(fields, "FieldFenceEast", 108, -100, 108, -315)

-- Orchard Edge
local orchard = folder(propFolder, "Orchard")
for row = 0, 5 do
	for col = 0, 7 do
		local x = -84 + col * 24 + (row % 2) * 12
		local z = -350 - row * 32
		if math.abs(x) > 10 then
			tree(orchard, x, z, 8 + (row + col) % 3)
		end
	end
end

-- Goblin Camp: palisade with a south gate facing the village
local camp = folder(propFolder, "GoblinCamp")
local function wall(name: string, size: any, cframe: any)
	part(camp, name, size, cframe, COLORS.darkWood, Enum.Material.WoodPlanks)
end
wall("PalisadeNorth", Vector3.new(180, 12, 2), at(0, G + 6, -750))
wall("PalisadeWest", Vector3.new(2, 12, 180), at(-90, G + 6, -660))
wall("PalisadeEast", Vector3.new(2, 12, 180), at(90, G + 6, -660))
wall("PalisadeSouthWest", Vector3.new(80, 12, 2), at(-50, G + 6, -570))
wall("PalisadeSouthEast", Vector3.new(80, 12, 2), at(50, G + 6, -570))
wall("GateTowerWest", Vector3.new(6, 18, 6), at(-12, G + 9, -570))
wall("GateTowerEast", Vector3.new(6, 18, 6), at(12, G + 9, -570))
for i, pos in { { -55, -610 }, { 55, -610 }, { -60, -690 }, { 60, -690 }, { -25, -640 }, { 30, -660 } } do
	local m = model(camp, "Tent" .. i)
	local base = CFrame.new(pos[1], G, pos[2])
	make("WedgePart", {
		Name = "Left",
		Size = Vector3.new(10, 7, 5),
		CFrame = base * CFrame.new(0, 3.5, 2.5),
		Anchored = true,
		Color = COLORS.canvas,
		Material = Enum.Material.Fabric,
	}, m)
	make("WedgePart", {
		Name = "Right",
		Size = Vector3.new(10, 7, 5),
		CFrame = base * CFrame.new(0, 3.5, -2.5) * CFrame.Angles(0, math.rad(180), 0),
		Anchored = true,
		Color = COLORS.canvas,
		Material = Enum.Material.Fabric,
	}, m)
end
brazier(camp, "CampFire", 0, -650)
part(camp, "ChieftainDais", Vector3.new(24, 1.5, 16), at(0, G + 0.75, -725), COLORS.stone, Enum.Material.Cobblestone)

-- Spawners: EnemyId, Count, LevelMin, LevelMax, RespawnSeconds, Radius
local SPAWNERS = {
	{ "goblin_raider", 3, 1, 2, 20, 12, 40, -160 },
	{ "goblin_raider", 3, 1, 2, 20, 12, -45, -190 },
	{ "goblin_raider", 2, 2, 3, 20, 10, 30, -260 },
	{ "goblin_slinger", 2, 2, 3, 25, 10, -60, -265 },
	{ "goblin_slinger", 2, 2, 3, 25, 10, 70, -225 },
	{ "goblin_raider", 3, 3, 3, 25, 12, -50, -390 },
	{ "goblin_slinger", 2, 3, 4, 25, 10, 55, -410 },
	{ "goblin_trapper", 2, 3, 4, 30, 10, -40, -470 },
	{ "goblin_trapper", 2, 3, 4, 30, 10, 50, -500 },
	{ "goblin_raider", 2, 3, 3, 25, 10, 15, -520 },
	{ "goblin_raider", 3, 4, 4, 30, 10, -50, -620 },
	{ "goblin_slinger", 2, 4, 4, 30, 10, 50, -630 },
	{ "goblin_trapper", 2, 4, 4, 30, 10, -55, -680 },
	{ "goblin_brute", 1, 4, 5, 45, 6, 40, -690 },
	{ "goblin_brute", 1, 4, 5, 45, 6, -30, -700 },
	{ "goblin_chieftain", 1, 6, 6, 120, 4, 0, -725 },
}
for i, s in SPAWNERS do
	part(
		spawnerFolder,
		"Spawner" .. i,
		Vector3.new(2, 1, 2),
		at(s[7], G + 0.5, s[8]),
		rgb(255, 0, 0),
		Enum.Material.Neon,
		{
			Transparency = 1,
			CanCollide = false,
			CanTouch = false,
			CanQuery = false,
			Tags = { "Spawner" },
			Attributes = {
				EnemyId = s[1],
				Count = s[2],
				LevelMin = s[3],
				LevelMax = s[4],
				RespawnSeconds = s[5],
				Radius = s[6],
			},
		}
	)
end

-- Lighting fill so the greybox reads
make("PointLight", { Name = "PlazaLight", Range = 40, Brightness = 0.5 }, village:FindFirstChild("Plaza"))

fs.writeFile("src/Workspace/Map.rbxmx", roblox.serializeModel({ map }, true))

-- Goblin template: part rig driven by a Humanoid. Scaled and tinted per enemy at spawn.
local goblin = model(nil, "Goblin")
local root = part(
	goblin,
	"HumanoidRootPart",
	Vector3.new(2, 2, 1),
	at(0, 3.4, 0),
	Color3.new(1, 1, 1),
	Enum.Material.SmoothPlastic,
	{
		Transparency = 1,
		Anchored = false,
	}
)
local function limb(name: string, size: any, cframe: any, color: any)
	local p = part(goblin, name, size, cframe, color, Enum.Material.SmoothPlastic, {
		Anchored = false,
		CanCollide = false,
		Massless = true,
	})
	make("WeldConstraint", { Name = "Weld", Part0 = root, Part1 = p }, p)
	return p
end
local skin = rgb(110, 150, 70)
limb("Torso", Vector3.new(1.8, 1.8, 1.1), at(0, 3.4, 0), rgb(110, 85, 60))
limb("Head", Vector3.new(1.5, 1.3, 1.3), at(0, 4.95, 0), skin)
limb("EarLeft", Vector3.new(0.9, 0.3, 0.3), at(-1.1, 5.1, 0), skin)
limb("EarRight", Vector3.new(0.9, 0.3, 0.3), at(1.1, 5.1, 0), skin)
limb("LegLeft", Vector3.new(0.6, 1.4, 0.6), at(-0.45, 1.6, 0), skin)
limb("LegRight", Vector3.new(0.6, 1.4, 0.6), at(0.45, 1.6, 0), skin)
limb("ArmLeft", Vector3.new(0.5, 1.5, 0.5), at(-1.2, 3.3, 0), skin)
limb("ArmRight", Vector3.new(0.5, 1.5, 0.5), at(1.2, 3.3, 0), skin)
limb("Weapon", Vector3.new(0.3, 0.3, 2.2), at(1.2, 2.7, -1), rgb(140, 140, 140))
make("Humanoid", {
	Name = "Humanoid",
	HipHeight = 2.4,
	DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None,
	HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff,
	BreakJointsOnDeath = false,
}, goblin)
goblin.PrimaryPart = root

fs.writeFile("src/ServerStorage/Templates/Goblin.rbxmx", roblox.serializeModel({ goblin }, true))
print("World and templates written.")
