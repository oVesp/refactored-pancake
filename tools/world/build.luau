--!strict

-- Generates the M0.5 greybox world, NPC templates and held weapon models as Rojo model files.
-- Run from the repo root: `lune run tools/world/build`. Output is deterministic; commit it.
-- Gameplay objects only: zones, spawn, NPCs, dev yard and the creation stage. Village,
-- farmland, orchard and camp dressing comes from the world generator (docs/systems/world-generation.md).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local Assets = require("../../src/ReplicatedStorage/Content/Assets")

-- Ground level of the gameplay areas; the world generator holds the pads at this height.
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

-- Fantasy Props MegaKit pieces (tools/blender/fantasy_kit.py): per Assets.Meshes key, its size and
-- centre in studs around the kit origin at the kit scale, as measured on `ServerStorage.FantasyKit`.
-- Lune cannot read them from the import, like the Goblin's ids.
local KIT_SCALE = 3.2
local KIT_PIECES: { [string]: { { key: string, size: any, centre: any } } } = {
	Sword = {
		{ key = "FantasySwordSteel", size = Vector3.new(0.853, 3.6229, 0.2093), centre = Vector3.new(0, 1.1456, 0) },
	},
	Shield = {
		{ key = "FantasyShieldStrap", size = Vector3.new(0.1175, 1.0013, 0.1438), centre = Vector3.new(0, 0, -0.073) },
		{ key = "FantasyShieldMetal", size = Vector3.new(1.9666, 1.9869, 0.511), centre = Vector3.new(0, 0, -0.3179) },
		{
			key = "FantasyShieldWood",
			size = Vector3.new(1.8037, 1.8082, 0.3575),
			centre = Vector3.new(0.0026, 0.0024, -0.2703),
		},
	},
	Dummy = {
		{
			key = "FantasyDummyMetal",
			size = Vector3.new(1.4339, 0.5988, 1.4339),
			centre = Vector3.new(0.0007, 0.4967, -0.0009),
		},
		{
			key = "FantasyDummyCloth",
			size = Vector3.new(2.5872, 3.3658, 1.1413),
			centre = Vector3.new(0, 4.2686, -0.0028),
		},
		{
			key = "FantasyDummyWood",
			size = Vector3.new(1.8707, 5.1834, 1.8707),
			centre = Vector3.new(0, 2.5826, -0.0016),
		},
	},
	Stand = {
		{
			key = "FantasyCandleStandMetal",
			size = Vector3.new(2.3433, 3.8559, 2.3401),
			centre = Vector3.new(0.0016, 1.9031, 0),
		},
		{
			key = "FantasyCandleStandWax",
			size = Vector3.new(2.1977, 1.1098, 2.1876),
			centre = Vector3.new(-0.0018, 3.6203, 0.003),
		},
	},
}

-- Places a kit piece with its origin at `origin`, `scale` times its kit-scale size. Cosmetic:
-- colliders and hit targets stay plain parts.
local function kitPiece(parent: any, piece: string, origin: any, scale: number)
	for _, entry in KIT_PIECES[piece] do
		local asset = Assets.Meshes[entry.key]
		assert(asset, `Assets.Meshes.{entry.key} missing`)
		local mesh = make("MeshPart", {
			Name = entry.key,
			MeshId = asset.id,
			InitialSize = entry.size / KIT_SCALE,
			Size = entry.size * scale,
			CFrame = origin * CFrame.new(entry.centre * scale),
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		}, parent)
		make("SurfaceAppearance", {
			Name = "SurfaceAppearance",
			ColorMap = asset.texture,
			NormalMap = asset.normal,
			MetalnessMap = asset.metalness,
			RoughnessMap = asset.roughness,
		}, mesh)
	end
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
	stone = rgb(150, 150, 145),
	wood = rgb(120, 85, 55),
	darkWood = rgb(80, 58, 40),
	devLine = rgb(230, 200, 60),
}

local map = model(nil, "Map")
local zoneFolder = folder(map, "Zones")
local npcFolder = folder(map, "Npcs")
local propFolder = folder(map, "Props")

-- Areas: id, zone id, center X/Z, size X/Z. The ground under them is terrain (src/ServerStorage/WorldGen).
local AREAS = {
	{ "VillageCore", "village_core", 0, 0, 180, 180 },
	{ "DevYard", "dev_yard", -165, 0, 150, 180 },
	{ "WheatFields", "wheat_fields", 0, -205, 220, 230 },
	{ "OrchardEdge", "orchard_edge", 0, -440, 220, 240 },
	{ "GoblinCamp", "goblin_camp", 0, -660, 200, 200 },
}

for _, area in AREAS do
	local name, zoneId, x, z, sx, sz = table.unpack(area)
	part(zoneFolder, name, Vector3.new(sx, 80, sz), at(x, G + 40, z), Color3.new(1, 1, 1), Enum.Material.ForceField, {
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Tags = { "Zone" },
		Attributes = { ZoneId = zoneId },
	})
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

-- Village Core: the Map keeps the spawn and the NPCs; the village dressing comes from the world
-- generator once the continent's regions are built.
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
trainer(
	npcFolder,
	"Fighter Trainer",
	-24,
	30,
	rgb(150, 60, 50),
	{ TrainerType = "Class", ClassId = "fighter" },
	"Train Fighter"
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
-- The kit dummy, 5.96 studs at the kit scale, stands 8 studs. It is the look; the invisible parts
-- stay the collider, hit target and nameplate anchor.
local DUMMY_SCALE = 8 / 5.96
local DUMMY_HITBOX = { Transparency = 1, CastShadow = false }
for _, entry in DUMMIES do
	local name, x, z, attributes = entry[1], entry[2], entry[3], entry[4]
	local m = model(dev, name)
	part(m, "Post", Vector3.new(0.8, 3, 0.8), at(x, G + 1.5, z), COLORS.darkWood, Enum.Material.Wood, DUMMY_HITBOX)
	local body = part(
		m,
		"Body",
		Vector3.new(2.2, 3.4, 1.4),
		at(x, G + 4.7, z),
		rgb(190, 160, 110),
		Enum.Material.Fabric,
		DUMMY_HITBOX
	)
	part(
		m,
		"Head",
		Vector3.new(1.6, 1.6, 1.6),
		at(x, G + 7.2, z),
		rgb(190, 160, 110),
		Enum.Material.Fabric,
		DUMMY_HITBOX
	)
	kitPiece(m, "Dummy", at(x, G, z), DUMMY_SCALE)
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
	local body = part(
		m,
		"Body",
		Vector3.new(2.2, 5, 1.4),
		at(-220, G + 2.5, 20),
		rgb(200, 120, 90),
		Enum.Material.Fabric,
		DUMMY_HITBOX
	)
	part(
		m,
		"Head",
		Vector3.new(1.6, 1.6, 1.6),
		at(-220, G + 7.2, 20),
		rgb(200, 120, 90),
		Enum.Material.Fabric,
		DUMMY_HITBOX
	)
	kitPiece(m, "Dummy", at(-220, G, 20), DUMMY_SCALE)
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

-- Wheat Fields, Orchard Edge and Goblin Camp dressing is generated with the settlements.

-- Character creation stage (docs/systems/character-creation.md): a closed, torch-lit hall high
-- above the village, inside the streaming radius. The creator previews the character on the
-- pedestal; `CameraFull`/`CameraHead` are the camera's framings, looking at `FocusFull`/`FocusHead`.
local STAGE_Y = G + 400
local STAGE_Z = 20
local stageColor = rgb(52, 46, 42)
local stage = model(map, "CreationStage")
stage.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
part(stage, "Floor", Vector3.new(44, 1, 44), at(0, STAGE_Y - 0.5, STAGE_Z), stageColor, Enum.Material.Slate)
part(stage, "Ceiling", Vector3.new(44, 1, 44), at(0, STAGE_Y + 22.5, STAGE_Z), stageColor, Enum.Material.Slate)
for i = 0, 7 do
	local angle = math.rad(i * 45)
	local wallAt = Vector3.new(math.sin(angle) * 20, STAGE_Y + 11, STAGE_Z + math.cos(angle) * 20)
	part(
		stage,
		`Wall{i + 1}`,
		Vector3.new(17, 22, 1),
		CFrame.lookAt(wallAt, Vector3.new(0, STAGE_Y + 11, STAGE_Z)),
		stageColor,
		Enum.Material.Cobblestone
	)
end
local pedestal = part(
	stage,
	"Pedestal",
	Vector3.new(1, 7, 7),
	at(0, STAGE_Y + 0.5, STAGE_Z) * CFrame.Angles(0, 0, math.rad(90)),
	COLORS.stone,
	Enum.Material.Marble,
	{ Shape = Enum.PartType.Cylinder, Tags = { "CreatorStage" } }
)
make("PointLight", { Name = "Key", Range = 14, Brightness = 0.8, Color = rgb(255, 236, 214) }, pedestal)
local marker = { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false }
-- The preview stands on the pedestal facing +Z, toward the camera.
part(stage, "FocusFull", Vector3.one, at(0, STAGE_Y + 3.3, STAGE_Z), Color3.new(1, 1, 1), Enum.Material.Air, marker)
part(
	stage,
	"CameraFull",
	Vector3.one,
	at(-1, STAGE_Y + 4, STAGE_Z + 9.5),
	Color3.new(1, 1, 1),
	Enum.Material.Air,
	marker
)
part(stage, "FocusHead", Vector3.one, at(0, STAGE_Y + 5.1, STAGE_Z), Color3.new(1, 1, 1), Enum.Material.Air, marker)
part(
	stage,
	"CameraHead",
	Vector3.one,
	at(-0.8, STAGE_Y + 5.6, STAGE_Z + 6.5),
	Color3.new(1, 1, 1),
	Enum.Material.Air,
	marker
)
for i, x in { -9, 9 } do
	-- A kit candle stand, 6 studs tall; the invisible part at its candle ring carries the flame.
	local flame = part(
		stage,
		`Torch{i}`,
		Vector3.one,
		at(x, STAGE_Y + 5.6, STAGE_Z - 6),
		COLORS.darkWood,
		Enum.Material.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false }
	)
	make("Fire", { Name = "Flame", Size = 3, Heat = 4 }, flame)
	make("PointLight", { Name = "Glow", Range = 18, Brightness = 0.9, Color = rgb(255, 170, 100) }, flame)
	kitPiece(stage, "Stand", at(x, STAGE_Y, STAGE_Z - 6), 6 / 4.2)
end
local fill =
	part(stage, "Fill", Vector3.one, at(0, STAGE_Y + 8, STAGE_Z + 9), Color3.new(1, 1, 1), Enum.Material.Air, marker)
make("SpotLight", {
	Name = "Fill",
	Range = 24,
	Angle = 60,
	Brightness = 3,
	Face = Enum.NormalId.Front,
	Color = rgb(235, 238, 255),
}, fill)

fs.writeFile("src/Workspace/Map.rbxmx", roblox.serializeModel({ map }, true))

-- Goblin template: the Goblin Scout's Studio 3D import (tools/world/goblin_scout_import.rbxm) on a
-- Humanoid. The import's RootPart carries the bone tree at the feet and the skinned parts hang off it
-- by Motor6D; it becomes "Rig" under a new HumanoidRootPart. Lune cannot read the import's mesh and
-- SurfaceAppearance ids, so they come from Assets.Meshes.GoblinScout<Part>.
local scout = roblox.deserializeModel(fs.readFile("tools/world/goblin_scout_import.rbxm"))[1]
local scoutRig = scout:FindFirstChild("RootPart")
local scoutOrigin = scoutRig.CFrame.Position
-- Humanoid layout: root centre one stud above the hips, hips one stud above the ground.
local goblinHip = 1
local goblinRootHeight = goblinHip + 1
-- The skinned mesh renders this far below the import's RootPart (its bones sit under the static mesh
-- bounds), so the rig is raised by it to put the soles on the ground. Measured in Studio.
local goblinRigLift = 1.75

local goblin = model(nil, "Goblin")
-- Streams in whole, so clients see the rig and Animator together with the Enemy tag.
goblin.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
goblin:SetAttribute("AnimSet", "Goblin")
-- The import stands about 3.75 studs; this brings a level-1 raider (scale 0.75) to about 4.4 studs.
goblin:SetAttribute("BaseScale", 1.575)
local root = part(
	goblin,
	"HumanoidRootPart",
	Vector3.new(2, 2, 1),
	at(0, goblinRootHeight, 0),
	Color3.new(1, 1, 1),
	Enum.Material.SmoothPlastic,
	{
		Transparency = 1,
		Anchored = false,
	}
)

scoutRig.Name = "Rig"
scoutRig.CFrame = at(0, goblinRigLift, 0)
scoutRig.Transparency = 1
scoutRig.Anchored = false
scoutRig.CanCollide = false
scoutRig.CanQuery = false
scoutRig.Massless = true
scoutRig.Parent = goblin
make("Motor6D", { Name = "Root", Part0 = root, Part1 = scoutRig, C0 = at(0, goblinRigLift - goblinRootHeight, 0) }, root)

for _, child in scout:GetChildren() do
	if child.ClassName ~= "MeshPart" then
		continue
	end
	local key = "GoblinScout" .. string.gsub(string.gsub(child.Name, "_low$", ""), " ", "")
	local asset = Assets.Meshes[key]
	assert(asset, `Assets.Meshes.{key} missing for import part {child.Name}`)
	local mesh = make("MeshPart", {
		Name = child.Name,
		MeshId = asset.id,
		-- Serialized flag the importer sets; without it the mesh renders unskinned.
		HasSkinnedMesh = true,
		InitialSize = child.InitialSize,
		Size = child.Size,
		CFrame = child.CFrame - scoutOrigin + Vector3.new(0, goblinRigLift, 0),
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
	}, goblin)
	make("SurfaceAppearance", {
		Name = "SurfaceAppearance",
		ColorMap = asset.texture,
		NormalMap = asset.normal,
		MetalnessMap = asset.metalness,
		RoughnessMap = asset.roughness,
		AlphaMode = Enum.AlphaMode.Overlay,
	}, mesh)
	local joint = child:FindFirstChildOfClass("Motor6D")
	make("Motor6D", { Name = joint.Name, Part0 = scoutRig, Part1 = mesh, C0 = joint.C0, C1 = joint.C1 }, mesh)
end

-- Invisible anchor at head height for nameplates and the target marker.
local head =
	part(goblin, "Head", Vector3.new(1, 1, 1), at(0, 3.4, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Transparency = 1,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		Massless = true,
	})
make("WeldConstraint", { Name = "Weld", Part0 = root, Part1 = head }, head)

local humanoid = make("Humanoid", {
	Name = "Humanoid",
	RigType = Enum.HumanoidRigType.R15,
	HipHeight = goblinHip,
	DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None,
	HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff,
	BreakJointsOnDeath = false,
}, goblin)
make("Animator", { Name = "Animator" }, humanoid)
goblin.PrimaryPart = root

fs.writeFile("src/ServerStorage/Templates/Goblin.rbxmx", roblox.serializeModel({ goblin }, true))

-- Skeleton template: the Studio 3D import (tools/world/skeleton_import.rbxm) rebuilt on the goblin's
-- Humanoid layout. The import supplies the bones and mesh size; the mesh id comes from Assets.
local imported = roblox.deserializeModel(fs.readFile("tools/world/skeleton_import.rbxm"))[1]
local importedMesh = imported:FindFirstChild("GEO_Skeleton")
local skeletonHeight = importedMesh.Size.Y / 2
local skeleton = model(nil, "Skeleton")
skeleton.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
skeleton:SetAttribute("AnimSet", "Skeleton")
-- The import stands 5.5 studs; this brings a scale-1 skeleton to about 5 studs.
skeleton:SetAttribute("BaseScale", 0.9)
local skeletonRoot = part(
	skeleton,
	"HumanoidRootPart",
	Vector3.new(2, 2, 1),
	at(0, skeletonHeight, 0),
	Color3.new(1, 1, 1),
	Enum.Material.SmoothPlastic,
	{
		Transparency = 1,
		Anchored = false,
	}
)
local skeletonBody = make("MeshPart", {
	Name = "Body",
	MeshId = Assets.Meshes.Skeleton.id,
	HasSkinnedMesh = true,
	InitialSize = importedMesh.InitialSize,
	Size = importedMesh.Size,
	CFrame = at(0, skeletonHeight, 0),
	Color = importedMesh.Color,
	Material = importedMesh.Material,
	Anchored = false,
	CanCollide = false,
	CanQuery = false,
	Massless = true,
}, skeleton)
make("Motor6D", { Name = "Root", Part0 = skeletonRoot, Part1 = skeletonBody }, skeletonRoot)
for _, bone in importedMesh:GetChildren() do
	if bone.ClassName == "Bone" then
		bone.Parent = skeletonBody
	end
end

local skeletonHead = part(
	skeleton,
	"Head",
	Vector3.new(1, 1, 1),
	at(0, skeletonHeight * 2 - 0.6, 0),
	Color3.new(1, 1, 1),
	Enum.Material.SmoothPlastic,
	{
		Transparency = 1,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		Massless = true,
	}
)
make("WeldConstraint", { Name = "Weld", Part0 = skeletonRoot, Part1 = skeletonHead }, skeletonHead)

local skeletonHumanoid = make("Humanoid", {
	Name = "Humanoid",
	RigType = Enum.HumanoidRigType.R15,
	HipHeight = skeletonHeight - 1,
	DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None,
	HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff,
	BreakJointsOnDeath = false,
}, skeleton)
make("Animator", { Name = "Animator" }, skeletonHumanoid)
skeleton.PrimaryPart = skeletonRoot

fs.writeFile("src/ServerStorage/Templates/Skeleton.rbxmx", roblox.serializeModel({ skeleton }, true))
print("World and templates written.")

-- Held models: an invisible Handle at the grip (LoadoutService welds it to the hand) and the kit mesh
-- around it, sized and turned to fit the clips and the sheath sockets in LoadoutService.
local function heldModel(name: string, handleSize: any, scale: number, offset: any)
	local held = make("Model", { Name = name })
	local handle = part(held, "Handle", handleSize, CFrame.new(), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, {
		Transparency = 1,
		CanCollide = false,
		CastShadow = false,
	})
	make("Attachment", { Name = "Grip" }, handle)
	kitPiece(held, name, offset, scale)
	held.PrimaryPart = handle
	fs.writeFile(`src/ReplicatedStorage/Weapons/{name}.rbxmx`, roblox.serializeModel({ held }, true))
end

-- 4.5 studs from pommel to tip. The kit's edge lies along X; turned to Z, it leads the swing. The
-- offset centres the kit's grip on the Handle.
heldModel("Sword", Vector3.new(0.25, 1, 0.25), 1.25, CFrame.new(0, 0.14, 0) * CFrame.Angles(0, math.pi / 2, 0))
-- 3.2 studs across; the kit's face looks along -Z, a held shield's along +Y (LoadoutService sockets).
heldModel("Shield", Vector3.new(0.2, 0.2, 0.2), 1.6, CFrame.new(0, 0.1, 0) * CFrame.Angles(math.pi / 2, 0, 0))
