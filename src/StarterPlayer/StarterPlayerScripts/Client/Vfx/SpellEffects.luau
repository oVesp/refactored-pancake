--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skills = require(ReplicatedStorage.Content.Skills)

local Particles = require(script.Parent.Particles)

export type ResolveInfo = {
	caster: Model?,
	skillId: string,
	origin: Vector3,
	aim: Vector3,
	target: Model?,
}

export type Recipe = {
	--[=[ Charge-up on the caster while a cast time runs. Returns the instance to cancel it. ]=]
	cast: ((root: BasePart, duration: number) -> Instance)?,
	--[=[ Dresses the invisible projectile anchor the controller moves along the flight path. ]=]
	projectile: ((body: BasePart) -> ())?,
	--[=[ Projectile hit at a world position. ]=]
	impact: ((position: Vector3) -> ())?,
	--[=[ Instant (non-projectile) skill resolved on the server. ]=]
	resolve: ((info: ResolveInfo) -> ())?,
	--[=[ Melee swing; also used as the local player's prediction. ]=]
	swing: ((origin: Vector3, aim: Vector3, range: number, angle: number) -> ())?,
}

local N = Particles.Numbers
local C = Particles.Colors
local R = NumberRange.new

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function rootOf(model: Model?): BasePart?
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	return if root and root:IsA("BasePart") then root else nil
end

-- Particles that spawn on a shell around the hand and pull inward while a spell charges.
local function charge(root: BasePart, duration: number, specs: { Particles.EmitterSpec }, light: Color3): Instance
	local anchor = Particles.Anchor(root.CFrame, Vector3.one * 4)
	Particles.Attach(anchor, specs)
	Particles.Light(anchor, light, 8, 1.5)
	Particles.Follow(anchor, root, CFrame.new(0.8, 0.4, -1.6), duration, 0.5)
	return anchor
end

local function inward(texture: string, color: ColorSequence, size: NumberSequence, rate: number): Particles.EmitterSpec
	return {
		texture = texture,
		color = color,
		size = size,
		lifetime = R(0.35, 0.45),
		speed = R(4, 6),
		rate = rate,
		shape = Enum.ParticleEmitterShape.Sphere,
		shapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		shapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		transparency = N(1, 0.2, 0),
		rotSpeed = R(-90, 90),
	}
end

local FIRE = C(rgb(255, 240, 170), rgb(255, 150, 40), rgb(200, 50, 15), rgb(60, 20, 10))
local FROST = C(rgb(240, 252, 255), rgb(150, 220, 255), rgb(70, 140, 230))
local STORM = C(rgb(255, 255, 235), rgb(255, 235, 110), rgb(180, 150, 255))
local HOLY = C(rgb(255, 255, 240), rgb(255, 225, 140), rgb(255, 170, 70))
local LIFE = C(rgb(235, 255, 220), rgb(140, 255, 150), rgb(255, 245, 170))
local STEEL = C(rgb(255, 255, 255), rgb(205, 220, 240), rgb(150, 170, 200))
local RAGE = C(rgb(255, 220, 160), rgb(255, 100, 40), rgb(150, 20, 10))
local DUST = C(rgb(170, 150, 125), rgb(120, 105, 90))
-- Darker, normal-blended tints for shapes that must read on bright daylight ground.
local ICE = C(rgb(200, 235, 255), rgb(90, 160, 235), rgb(40, 90, 190))
local BOLT = C(rgb(255, 250, 210), rgb(255, 205, 60), rgb(200, 150, 255))
local ARCANE = C(rgb(245, 230, 255), rgb(185, 130, 255), rgb(95, 55, 210))
local WARD = C(rgb(240, 250, 255), rgb(150, 200, 255), rgb(90, 130, 255))
local GROWTH = C(rgb(200, 255, 160), rgb(80, 210, 90), rgb(30, 130, 60))
local SHIELD = C(rgb(190, 225, 255), rgb(80, 140, 255), rgb(60, 70, 200))
local VENOM = C(rgb(220, 255, 170), rgb(120, 210, 60), rgb(40, 90, 30))
local TOXIC = C(rgb(170, 235, 90), rgb(90, 160, 40), rgb(45, 90, 25))
local HEX = C(rgb(230, 190, 255), rgb(130, 60, 190), rgb(40, 15, 60))

--[=[
	Visual recipes per skill id, for class spells and enemy attacks. Skills without a recipe
	keep the controller's placeholder visuals. Hitboxes are not drawn here; shapes come from
	textures, so the look is free to differ from the server's hit volume.
]=]
local SpellEffects: { [string]: Recipe } = {}

SpellEffects.firebolt = {
	cast = function(root, duration)
		return charge(root, duration, { inward("Fire", FIRE, N(0.6, 1.2), 40) }, rgb(255, 140, 50))
	end,
	projectile = function(body)
		Particles.Attach(body, {
			{
				texture = "SoftGlow",
				color = C(rgb(255, 200, 110)),
				size = N(2.6),
				transparency = N(0.2),
				lifetime = R(0.1),
				rate = 40,
				locked = true,
			},
			{
				texture = "Fire",
				color = FIRE,
				size = N(1.8),
				transparency = N(0, 1),
				lifetime = R(0.12),
				rate = 40,
				locked = true,
			},
			{
				texture = "Fire",
				color = FIRE,
				size = N(1.8, 1.2, 0.3),
				lifetime = R(0.2, 0.35),
				speed = R(0.5, 2),
				spread = Vector2.new(180, 180),
				rotSpeed = R(-200, 200),
				rate = 160,
			},
			{
				texture = "Flame",
				color = FIRE,
				size = N(1.2, 2.4),
				transparency = N(0.3, 1),
				lifetime = R(0.4, 0.6),
				speed = R(0.5, 1.5),
				spread = Vector2.new(180, 180),
				rotSpeed = R(-120, 120),
				rate = 25,
			},
			{
				texture = "Smoke",
				color = C(rgb(80, 60, 50), rgb(40, 35, 35)),
				size = N(1, 3),
				transparency = N(0.6, 1),
				lifetime = R(0.6, 1),
				acceleration = Vector3.new(0, 3, 0),
				rotSpeed = R(-40, 40),
				emission = 0,
				rate = 15,
			},
		})
		Particles.Trail(body, { color = FIRE, width = 0.9, lifetime = 0.2, texture = "TrailStreak" })
		Particles.Light(body, rgb(255, 140, 50), 12, 2)
	end,
	impact = function(position)
		Particles.Burst(CFrame.new(position), {
			{
				texture = "Scorch",
				color = FIRE,
				size = N(1, 7),
				transparency = N(0, 1),
				lifetime = R(0.25),
				count = 1,
			},
			{
				texture = "Fire",
				color = FIRE,
				size = N(2, 0.5),
				lifetime = R(0.3, 0.6),
				speed = R(6, 14),
				spread = Vector2.new(180, 180),
				drag = 6,
				rotSpeed = R(-200, 200),
				count = 18,
			},
			{
				texture = "Smoke",
				color = C(rgb(90, 70, 60), rgb(40, 35, 35)),
				size = N(2, 5),
				transparency = N(0.5, 1),
				lifetime = R(1, 1.6),
				speed = R(2, 5),
				spread = Vector2.new(180, 180),
				acceleration = Vector3.new(0, 2, 0),
				emission = 0,
				count = 8,
			},
			{
				texture = "Streak",
				color = FIRE,
				size = N(0.4, 0),
				lifetime = R(0.25, 0.4),
				speed = R(20, 35),
				spread = Vector2.new(180, 180),
				drag = 4,
				acceleration = Vector3.new(0, -30, 0),
				orientation = Enum.ParticleOrientation.VelocityParallel,
				rotation = R(90),
				count = 12,
			},
		})
		Particles.Flash(position, rgb(255, 140, 50), 16, 0.35)
	end,
}

SpellEffects.frost_shard = {
	projectile = function(body)
		Particles.Attach(body, {
			{
				texture = "StarBurst",
				color = FROST,
				size = N(1.8),
				transparency = N(0.1, 1),
				lifetime = R(0.1),
				rate = 30,
				locked = true,
			},
			{
				texture = "Glint",
				color = FROST,
				size = N(0.6, 0),
				lifetime = R(0.3, 0.5),
				speed = R(0.5, 2),
				spread = Vector2.new(180, 180),
				rotSpeed = R(-90, 90),
				rate = 40,
			},
			{
				texture = "Smoke",
				color = C(rgb(220, 240, 255)),
				size = N(1, 2.2),
				transparency = N(0.7, 1),
				lifetime = R(0.5, 0.8),
				rotSpeed = R(-30, 30),
				emission = 0.3,
				rate = 20,
			},
		})
		Particles.Trail(body, { color = FROST, width = 0.5, lifetime = 0.25, texture = "TrailStreak" })
		Particles.Light(body, rgb(150, 220, 255), 10, 1.5)
	end,
	impact = function(position)
		Particles.Burst(CFrame.new(position), {
			{
				texture = "Streak",
				color = FROST,
				size = N(1.4, 0.2),
				lifetime = R(0.25, 0.4),
				speed = R(18, 30),
				spread = Vector2.new(180, 180),
				drag = 5,
				orientation = Enum.ParticleOrientation.VelocityParallel,
				rotation = R(90),
				count = 14,
			},
			{
				texture = "Glint",
				color = FROST,
				size = N(1, 0),
				lifetime = R(0.4, 0.7),
				speed = R(4, 10),
				spread = Vector2.new(180, 180),
				drag = 3,
				count = 10,
			},
			{
				texture = "Smoke",
				color = C(rgb(225, 245, 255)),
				size = N(2, 4.5),
				transparency = N(0.5, 1),
				lifetime = R(0.8, 1.2),
				speed = R(1, 3),
				spread = Vector2.new(180, 180),
				emission = 0.3,
				count = 6,
			},
		})
		Particles.Flash(position, rgb(150, 220, 255), 14, 0.3)
	end,
}

SpellEffects.spark = {
	projectile = function(body)
		Particles.Attach(body, {
			{
				texture = "Crackle",
				color = STORM,
				size = N(2),
				lifetime = R(0.06, 0.12),
				rate = 40,
				locked = true,
			},
			{
				texture = "Glint",
				color = STORM,
				size = N(1.3),
				lifetime = R(0.08),
				rate = 30,
				locked = true,
			},
		})
		Particles.Trail(body, { color = STORM, width = 0.3, lifetime = 0.12, texture = "TrailStreak" })
		Particles.Light(body, rgb(255, 240, 140), 10, 2)
	end,
	impact = function(position)
		Particles.Burst(CFrame.new(position), {
			{
				texture = "Crackle",
				color = STORM,
				size = N(3.5),
				transparency = N(0, 0.3, 1),
				lifetime = R(0.1, 0.2),
				count = 6,
				locked = true,
			},
			{
				texture = "Glint",
				color = STORM,
				size = N(2, 0),
				lifetime = R(0.15, 0.25),
				count = 3,
			},
			{
				texture = "Streak",
				color = STORM,
				size = N(0.4, 0),
				lifetime = R(0.2, 0.35),
				speed = R(18, 30),
				spread = Vector2.new(180, 180),
				drag = 4,
				acceleration = Vector3.new(0, -25, 0),
				orientation = Enum.ParticleOrientation.VelocityParallel,
				rotation = R(90),
				count = 10,
			},
		})
		Particles.Flash(position, rgb(255, 240, 140), 14, 0.15)
	end,
}

SpellEffects.smite = {
	projectile = function(body)
		Particles.Attach(body, {
			{
				texture = "StarBurst",
				color = HOLY,
				size = N(2.2),
				transparency = N(0, 1),
				lifetime = R(0.15),
				rate = 25,
				locked = true,
			},
			{
				texture = "Glint",
				color = HOLY,
				size = N(0.5, 0),
				lifetime = R(0.4, 0.7),
				speed = R(0.5, 1.5),
				spread = Vector2.new(180, 180),
				rate = 30,
			},
		})
		Particles.Trail(body, { color = HOLY, width = 0.6, lifetime = 0.25, texture = "TrailStreak" })
		Particles.Light(body, rgb(255, 225, 150), 12, 2)
	end,
	impact = function(position)
		Particles.Burst(CFrame.new(position), {
			{
				texture = "RingWave",
				color = HOLY,
				size = N(0.5, 6),
				transparency = N(0, 1),
				lifetime = R(0.35),
				count = 1,
			},
			{
				texture = "StarBurst",
				color = HOLY,
				size = N(5, 2),
				lifetime = R(0.2),
				count = 1,
			},
			{
				texture = "Glint",
				color = HOLY,
				size = N(0.8, 0),
				lifetime = R(0.6, 1),
				speed = R(2, 6),
				spread = Vector2.new(180, 180),
				acceleration = Vector3.new(0, 6, 0),
				drag = 2,
				count = 14,
			},
		})
		Particles.Flash(position, rgb(255, 225, 150), 14, 0.3)
	end,
}

local function cleaveSwing(origin: Vector3, aim: Vector3, range: number, angle: number)
	local center = origin + Vector3.new(0, 0.5, 0)
	Particles.Sweep(center, aim - origin, 1.5, range * 0.75, angle, 0.16, {
		color = STEEL,
		transparency = N(0.05, 0.5, 1),
		lifetime = 0.22,
		texture = "TrailStreak",
	})
	local feet = Particles.Ground(origin)
	Particles.Burst(CFrame.new(feet + Vector3.new(0, 0.3, 0)), {
		{
			texture = "Smoke",
			color = DUST,
			size = N(1.5, 3.5),
			transparency = N(0.55, 1),
			lifetime = R(0.5, 0.8),
			speed = R(6, 10),
			spread = Vector2.new(80, 80),
			drag = 5,
			emission = 0,
			count = 6,
		},
	})
end

SpellEffects.cleave = {
	swing = cleaveSwing,
}

SpellEffects.war_cry = {
	resolve = function(info)
		local feet = Particles.Ground(info.origin)
		Particles.GroundWave(feet, RAGE, N(1, 22), 0.5)
		Particles.GroundWave(feet, RAGE, N(1, 14), 0.75)
		Particles.Burst(CFrame.new(feet + Vector3.new(0, 0.5, 0)), {
			{
				texture = "Twirl",
				color = RAGE,
				size = N(2, 5),
				transparency = N(0.2, 1),
				lifetime = R(0.5, 0.8),
				speed = R(4, 8),
				spread = Vector2.new(25, 25),
				rotSpeed = R(200, 320),
				count = 10,
			},
			{
				texture = "Smoke",
				color = DUST,
				size = N(2, 5),
				transparency = N(0.4, 1),
				lifetime = R(0.8, 1.2),
				speed = R(10, 16),
				spread = Vector2.new(85, 85),
				drag = 4,
				acceleration = Vector3.new(0, -2, 0),
				emission = 0,
				count = 14,
			},
			{
				texture = "Debris",
				color = DUST,
				size = N(1.2, 0.8),
				transparency = N(0, 0, 1),
				lifetime = R(0.6, 0.9),
				speed = R(12, 20),
				spread = Vector2.new(60, 60),
				acceleration = Vector3.new(0, -50, 0),
				rotSpeed = R(-180, 180),
				emission = 0,
				count = 10,
			},
		}, Vector3.new(3, 0.2, 3))
		Particles.Flash(feet + Vector3.new(0, 3, 0), rgb(255, 90, 40), 20, 0.5)
	end,
}

SpellEffects.rebuke = {
	resolve = function(info)
		local feet = Particles.Ground(info.origin)
		Particles.GroundWave(feet, HOLY, N(1, 20), 0.4)
		Particles.GroundWave(feet, HOLY, N(1, 12), 0.6)
		Particles.Burst(CFrame.new(info.origin + Vector3.new(0, 1, 0)), {
			{
				texture = "StarBurst",
				color = HOLY,
				size = N(8, 3),
				lifetime = R(0.25),
				count = 1,
			},
			{
				texture = "Glint",
				color = HOLY,
				size = N(0.9, 0),
				lifetime = R(0.5, 0.9),
				speed = R(10, 18),
				spread = Vector2.new(180, 180),
				drag = 5,
				count = 24,
			},
		})
		Particles.Burst(CFrame.new(feet + Vector3.new(0, 0.3, 0)), {
			{
				texture = "Streak",
				color = HOLY,
				size = N(1.6, 0.4),
				lifetime = R(0.4, 0.6),
				speed = R(8, 14),
				orientation = Enum.ParticleOrientation.VelocityParallel,
				rotation = R(90),
				count = 12,
			},
		}, Vector3.new(10, 0.2, 10))
		Particles.Flash(info.origin + Vector3.new(0, 3, 0), rgb(255, 225, 150), 20, 0.4)
	end,
}

SpellEffects.mend = {
	cast = function(root, duration)
		return charge(root, duration, {
			inward("Glint", LIFE, N(0.5, 0.9), 30),
			{
				texture = "SoftGlow",
				color = LIFE,
				size = N(1.2, 1.8, 1.2),
				transparency = N(0.4),
				lifetime = R(0.2),
				rate = 10,
				locked = true,
			},
		}, rgb(140, 255, 150))
	end,
	resolve = function(info)
		local root = rootOf(info.target) or rootOf(info.caster)
		if not root then
			return
		end
		local feet = Particles.Ground(root.Position)
		Particles.GroundWave(feet, LIFE, N(1, 8), 0.5)
		local motes = Particles.Anchor(CFrame.new(feet + Vector3.new(0, 0.3, 0)), Vector3.new(4, 0.2, 4))
		Particles.Attach(motes, {
			{
				texture = "SoftGlow",
				color = LIFE,
				size = N(0.6, 0),
				transparency = N(0.2, 1),
				lifetime = R(0.8, 1.2),
				speed = R(3, 6),
				count = 18,
				rate = 25,
			},
			{
				texture = "Glint",
				color = LIFE,
				size = N(0.7, 0),
				lifetime = R(0.6, 1),
				speed = R(4, 7),
				count = 10,
			},
		})
		Particles.Follow(motes, root, CFrame.new(0, feet.Y - root.Position.Y + 0.3, 0), 0.6, 1.3)
		Particles.Burst(root.CFrame, {
			{
				texture = "StarBurst",
				color = LIFE,
				size = N(4, 1),
				lifetime = R(0.3),
				count = 1,
			},
		})
		Particles.Flash(root.Position, rgb(140, 255, 150), 14, 0.5)
	end,
}

-- Ground deliveries hit at the aim point clamped to the skill's range, as the server does.
local function groundTarget(info: ResolveInfo): Vector3
	local skill = Skills.ById[info.skillId]
	local offset = Vector3.new(info.aim.X - info.origin.X, 0, info.aim.Z - info.origin.Z)
	local range = skill and skill.range or offset.Magnitude
	local center = if offset.Magnitude > range then info.origin + offset.Unit * range else info.aim
	return Particles.Ground(center)
end

local function flatLook(origin: Vector3, aim: Vector3): Vector3?
	local look = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	return if look.Magnitude > 1e-3 then look.Unit else nil
end

local function scatter(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * radius
	return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Ground eruption: frost spikes burst out of the floor at staggered points across the area.
SpellEffects.ice_patch = {
	cast = function(root, duration)
		return charge(root, duration, {
			inward("Glint", FROST, N(0.7, 0.2), 35),
			inward("Smoke", C(rgb(220, 240, 255)), N(1.2, 0.4), 12),
		}, rgb(150, 220, 255))
	end,
	resolve = function(info)
		local center = groundTarget(info)
		Particles.GroundWave(center, FROST, N(2, 18), 0.6)
		for i = 1, 8 do
			local point = if i == 1 then center else scatter(center, 6)
			task.delay((i - 1) * 0.045, function()
				Particles.Burst(CFrame.new(Particles.Ground(point)), {
					{
						texture = "Streak",
						color = ICE,
						size = N(5, 3.5, 0),
						transparency = N(0, 0.1, 1),
						lifetime = R(0.5, 0.7),
						speed = R(14, 24),
						spread = Vector2.new(18, 18),
						drag = 9,
						orientation = Enum.ParticleOrientation.VelocityParallel,
						rotation = R(90),
						emission = 0.15,
						count = 5,
					},
					{
						texture = "Glint",
						color = FROST,
						size = N(1.1, 0),
						lifetime = R(0.4, 0.7),
						speed = R(5, 10),
						spread = Vector2.new(70, 70),
						drag = 3,
						acceleration = Vector3.new(0, -12, 0),
						count = 3,
					},
				})
			end)
		end
		Particles.Burst(CFrame.new(center + Vector3.new(0, 0.4, 0)), {
			{
				texture = "Smoke",
				color = C(rgb(230, 245, 255), rgb(170, 210, 255)),
				size = N(2.5, 6),
				transparency = N(1, 0.55, 1),
				lifetime = R(1.4, 2),
				speed = R(0.5, 1.5),
				rotSpeed = R(-20, 20),
				emission = 0.4,
				count = 14,
			},
		}, Vector3.new(12, 0.3, 12))
		Particles.Flash(center + Vector3.new(0, 2, 0), rgb(150, 220, 255), 18, 0.6)
	end,
}

-- Fire breath: a short stream of flame jets fanning out from the hands.
SpellEffects.flame_fan = {
	swing = function(origin, aim, range, angle)
		local look = flatLook(origin, aim)
		if not look then
			return
		end
		local start = origin + Vector3.new(0, 0.6, 0) + look * 1.5
		local nozzle = Particles.Anchor(CFrame.lookAt(start, start + look))
		local speed = range / 0.45
		Particles.Attach(nozzle, {
			{
				texture = "Fire",
				color = FIRE,
				size = N(0.8, 3, 4.5),
				transparency = N(0.1, 0.3, 1),
				lifetime = R(0.45, 0.6),
				speed = R(speed * 0.8, speed),
				spread = Vector2.new(8, angle / 2),
				drag = 1.2,
				rotSpeed = R(-180, 180),
				direction = Enum.NormalId.Front,
				rate = 140,
			},
			{
				texture = "Jet",
				color = FIRE,
				size = N(1.2, 2.5),
				transparency = N(0, 1),
				lifetime = R(0.15, 0.25),
				speed = R(speed * 0.6, speed * 0.8),
				spread = Vector2.new(5, angle / 3),
				orientation = Enum.ParticleOrientation.VelocityParallel,
				rotation = R(90),
				direction = Enum.NormalId.Front,
				rate = 60,
			},
			{
				texture = "Smoke",
				color = C(rgb(90, 70, 60), rgb(40, 35, 35)),
				size = N(2, 5),
				transparency = N(0.6, 1),
				lifetime = R(0.8, 1.2),
				speed = R(speed * 0.4, speed * 0.6),
				spread = Vector2.new(10, angle / 2),
				drag = 3,
				acceleration = Vector3.new(0, 4, 0),
				emission = 0,
				direction = Enum.NormalId.Front,
				rate = 25,
			},
		})
		Particles.Light(nozzle, rgb(255, 140, 50), 16, 2.5)
		task.delay(0.35, Particles.Release, nozzle, 1.3)
	end,
}

-- Overhead blow that cracks the ground in front of the warrior.
SpellEffects.heavy_strike = {
	swing = function(origin, aim, range)
		local look = flatLook(origin, aim)
		if not look then
			return
		end
		local spot = Particles.Ground(origin + look * range * 0.6)
		Particles.Burst(CFrame.new(spot + Vector3.new(0, 2.5, 0)), {
			{
				texture = "Slash",
				color = C(rgb(170, 195, 240), rgb(70, 95, 150)),
				size = N(7, 9),
				transparency = N(0, 0.1, 1),
				lifetime = R(0.25),
				rotation = R(160, 200),
				emission = 0,
				count = 1,
			},
			{
				texture = "Slash",
				color = STEEL,
				size = N(7.5, 9.5),
				transparency = N(0.3, 1),
				lifetime = R(0.2),
				rotation = R(170, 190),
				zOffset = 0.5,
				count = 1,
			},
		})
		Particles.GroundWave(spot, DUST, N(1, 10), 0.4)
		Particles.Burst(CFrame.new(spot + Vector3.new(0, 0.3, 0)), {
			{
				texture = "Rubble",
				color = DUST,
				size = N(1.4, 1),
				transparency = N(0, 0, 1),
				lifetime = R(0.6, 0.9),
				speed = R(10, 18),
				spread = Vector2.new(40, 40),
				acceleration = Vector3.new(0, -50, 0),
				rotSpeed = R(-200, 200),
				emission = 0,
				count = 8,
			},
			{
				texture = "Smoke",
				color = DUST,
				size = N(2, 4.5),
				transparency = N(0.45, 1),
				lifetime = R(0.7, 1),
				speed = R(5, 9),
				spread = Vector2.new(85, 85),
				drag = 4,
				emission = 0,
				count = 8,
			},
			{
				texture = "Streak",
				color = STEEL,
				size = N(0.5, 0),
				lifetime = R(0.2, 0.35),
				speed = R(20, 30),
				spread = Vector2.new(60, 60),
				drag = 4,
				acceleration = Vector3.new(0, -30, 0),
				orientation = Enum.ParticleOrientation.VelocityParallel,
				rotation = R(90),
				count = 8,
			},
		}, Vector3.new(2, 0.2, 2))
		Particles.Flash(spot + Vector3.new(0, 2, 0), rgb(255, 235, 200), 12, 0.25)
	end,
}

-- Dash: a blurred streak along the path, kicked-up dust at the start, a crunch on arrival.
local function dashStreak(from: Vector3, to: Vector3, color: ColorSequence, width: number)
	local anchor = Particles.Anchor(CFrame.new(from))
	Particles.Trail(anchor, {
		color = color,
		width = width,
		lifetime = 0.3,
		texture = "TrailStreak",
		transparency = N(0, 1),
		emission = 0.3,
	})
	Particles.Attach(anchor, {
		{
			texture = "Smoke",
			color = DUST,
			size = N(2, 4.5),
			transparency = N(0.3, 1),
			lifetime = R(0.5, 0.8),
			speed = R(1, 3),
			spread = Vector2.new(180, 180),
			emission = 0,
			rate = 60,
		},
	})
	Particles.Travel(anchor, from, to, 0.14, 0.8)
end

local function chargeResolve(color: ColorSequence): (ResolveInfo) -> ()
	return function(info)
		local root = rootOf(info.caster)
		if not root or (root.Position - info.origin).Magnitude < 2 then
			return
		end
		dashStreak(info.origin, root.Position, color, 3)
		local feet = Particles.Ground(info.origin)
		Particles.Burst(CFrame.new(feet + Vector3.new(0, 0.3, 0)), {
			{
				texture = "Smoke",
				color = DUST,
				size = N(2, 5),
				transparency = N(0.25, 1),
				lifetime = R(0.6, 0.9),
				speed = R(6, 10),
				spread = Vector2.new(80, 80),
				drag = 5,
				emission = 0,
				count = 8,
			},
		})
		task.delay(0.12, function()
			local hit = root.Position + root.CFrame.LookVector * 2.5
			Particles.Burst(CFrame.new(hit), {
				{
					texture = "StarBurst",
					color = color,
					size = N(5, 1.5),
					lifetime = R(0.18),
					count = 1,
				},
				{
					texture = "Streak",
					color = color,
					size = N(0.6, 0),
					lifetime = R(0.2, 0.3),
					speed = R(18, 28),
					spread = Vector2.new(180, 180),
					drag = 4,
					orientation = Enum.ParticleOrientation.VelocityParallel,
					rotation = R(90),
					count = 10,
				},
			})
			Particles.Flash(hit, rgb(255, 230, 190), 12, 0.2)
		end)
	end
end

SpellEffects.charge = { resolve = chargeResolve(C(rgb(235, 240, 255), rgb(130, 150, 190))) }
SpellEffects.wolf_charge = { resolve = chargeResolve(DUST) }

-- Blink: the mage folds into a swirl of arcane light and unfolds at the destination.
local function blinkPuff(position: Vector3, closing: boolean)
	Particles.Burst(CFrame.new(position), {
		{
			texture = "Twirl",
			color = ARCANE,
			size = if closing then N(5, 0.5) else N(0.5, 5),
			transparency = N(0.1, 1),
			lifetime = R(0.35),
			rotSpeed = R(400, 500),
			count = 2,
		},
		{
			texture = "Glint",
			color = ARCANE,
			size = N(0.8, 0),
			lifetime = R(0.4, 0.7),
			speed = R(6, 12),
			spread = Vector2.new(180, 180),
			drag = 4,
			count = 14,
		},
		{
			texture = "Smoke",
			color = C(rgb(150, 110, 220), rgb(60, 40, 110)),
			size = N(2, 4),
			transparency = N(0.5, 1),
			lifetime = R(0.6, 0.9),
			speed = R(1, 3),
			spread = Vector2.new(180, 180),
			emission = 0.3,
			count = 5,
		},
	})
	Particles.Flash(position, rgb(185, 130, 255), 14, 0.3)
end

SpellEffects.blink = {
	resolve = function(info)
		local root = rootOf(info.caster)
		if not root then
			return
		end
		blinkPuff(info.origin + Vector3.new(0, 0.5, 0), true)
		if (root.Position - info.origin).Magnitude > 2 then
			Particles.Beam(info.origin + Vector3.new(0, 0.5, 0), root.Position, {
				texture = "SoftGlow",
				color = ARCANE,
				width = 2.5,
				lifetime = 0.3,
			})
		end
		blinkPuff(root.Position, false)
		Particles.GroundWave(root.Position, ARCANE, N(1, 9), 0.4)
	end,
}

-- Falling strike: a column of light drops onto the ally and splashes across the ground.
SpellEffects.lay_on_hands = {
	resolve = function(info)
		local root = rootOf(info.target) or rootOf(info.caster)
		if not root then
			return
		end
		local feet = Particles.Ground(root.Position)
		local sky = feet + Vector3.new(0, 40, 0)
		-- The glow tapers at both ends, so the lower end sinks below ground to keep the column on the ally.
		Particles.Beam(
			sky,
			feet - Vector3.new(0, 14, 0),
			{ texture = "SoftGlow", color = HOLY, width = 7, lifetime = 0.8 }
		)
		Particles.Burst(CFrame.new(sky), {
			{
				texture = "Ray",
				color = HOLY,
				size = N(4, 3),
				transparency = N(0.2, 0.6),
				lifetime = R(0.4),
				speed = R(100),
				orientation = Enum.ParticleOrientation.VelocityParallel,
				rotation = R(90),
				direction = Enum.NormalId.Bottom,
				count = 6,
			},
		}, Vector3.new(3, 0.5, 3))
		task.delay(0.15, function()
			Particles.GroundWave(feet, HOLY, N(2, 20), 0.6)
			Particles.Burst(CFrame.new(feet + Vector3.new(0, 1, 0)), {
				{
					texture = "StarBurst",
					color = HOLY,
					size = N(9, 3),
					lifetime = R(0.3),
					count = 1,
				},
				{
					texture = "Glint",
					color = HOLY,
					size = N(0.9, 0),
					lifetime = R(0.9, 1.4),
					speed = R(3, 7),
					spread = Vector2.new(40, 40),
					acceleration = Vector3.new(0, 4, 0),
					drag = 1.5,
					count = 24,
				},
			}, Vector3.new(4, 0.3, 4))
			Particles.Flash(feet + Vector3.new(0, 3, 0), rgb(255, 225, 150), 24, 0.7)
		end)
	end,
}

-- Aura: a shell of arcane swirls that clings to the mage for a moment.
SpellEffects.arcane_shield = {
	resolve = function(info)
		local root = rootOf(info.caster)
		if not root then
			return
		end
		local aura = Particles.Anchor(root.CFrame)
		Particles.Attach(aura, {
			{
				texture = "Twirl",
				color = SHIELD,
				size = N(6, 7),
				transparency = N(1, 0, 1),
				lifetime = R(0.5, 0.7),
				rotSpeed = R(-260, 260),
				emission = 0.2,
				zOffset = 2,
				locked = true,
				rate = 16,
			},
			{
				texture = "SoftGlow",
				color = WARD,
				size = N(6),
				transparency = N(1, 0.75, 1),
				lifetime = R(0.6),
				zOffset = 2,
				locked = true,
				rate = 3,
			},
			{
				texture = "Glint",
				color = WARD,
				size = N(0.7, 0),
				lifetime = R(0.5, 0.8),
				speed = R(2, 4),
				spread = Vector2.new(180, 180),
				rotSpeed = R(-90, 90),
				rate = 25,
			},
		})
		Particles.Light(aura, rgb(150, 200, 255), 10, 1.5)
		Particles.Follow(aura, root, CFrame.identity, 2.2, 0.8)
		Particles.GroundWave(root.Position, WARD, N(1, 10), 0.45)
		Particles.Burst(root.CFrame, {
			{
				texture = "StarBurst",
				color = WARD,
				size = N(7, 2),
				lifetime = R(0.25),
				count = 1,
			},
		})
	end,
}

-- Lingering aura: green motes spiral up from the ally's feet while the regen settles in.
SpellEffects.renew = {
	resolve = function(info)
		local root = rootOf(info.target) or rootOf(info.caster)
		if not root then
			return
		end
		local feet = Particles.Ground(root.Position)
		local offset = CFrame.new(0, feet.Y - root.Position.Y + 0.2, 0)
		local motes = Particles.Anchor(root.CFrame * offset, Vector3.new(3.5, 0.2, 3.5))
		Particles.Attach(motes, {
			{
				texture = "SoftGlow",
				color = GROWTH,
				size = N(0.9, 1.2, 0),
				transparency = N(0.1, 1),
				lifetime = R(1.2, 1.8),
				speed = R(2, 4),
				acceleration = Vector3.new(0, 1.5, 0),
				emission = 0.5,
				rate = 30,
			},
			{
				texture = "Twirl",
				color = GROWTH,
				size = N(4, 5),
				transparency = N(1, 0.2, 1),
				emission = 0.4,
				lifetime = R(0.8),
				speed = R(0.01),
				rotSpeed = R(150, 200),
				orientation = Enum.ParticleOrientation.VelocityPerpendicular,
				locked = true,
				rate = 2,
			},
			{
				texture = "Glint",
				color = LIFE,
				size = N(1, 0),
				lifetime = R(0.8, 1.2),
				speed = R(3, 6),
				rate = 8,
			},
		})
		Particles.Follow(motes, root, offset, 3, 1.8)
		Particles.Flash(root.Position, rgb(140, 255, 150), 12, 0.6)
	end,
}

-- Beam: a ribbon of light links healer and ally, then a ward shimmers around the ally.
SpellEffects.shelter = {
	resolve = function(info)
		local target = rootOf(info.target) or rootOf(info.caster)
		if not target then
			return
		end
		local caster = rootOf(info.caster)
		if caster and caster ~= target then
			Particles.Beam(caster.Position + Vector3.new(0, 0.5, 0), target, {
				texture = "SoftGlow",
				color = WARD,
				width = 2.2,
				lifetime = 0.5,
				curve = 3,
				speed = 4,
				segments = 20,
			})
		end
		task.delay(0.1, function()
			Particles.Burst(target.CFrame, {
				{
					texture = "Twirl",
					color = WARD,
					size = N(3, 7),
					transparency = N(0.3, 1),
					lifetime = R(0.5),
					rotSpeed = R(250, 350),
					count = 2,
				},
				{
					texture = "Glint",
					color = WARD,
					size = N(0.7, 0),
					lifetime = R(0.5, 0.8),
					speed = R(2, 4),
					spread = Vector2.new(180, 180),
					count = 16,
				},
			}, Vector3.new(4, 5, 4))
			Particles.Flash(target.Position, rgb(150, 200, 255), 12, 0.4)
		end)
	end,
}

-- Chains: lightning forks from the mage into the ground around them.
SpellEffects.overcharge = {
	resolve = function(info)
		local root = rootOf(info.caster)
		if not root then
			return
		end
		for i = 1, 4 do
			task.delay((i - 1) * 0.07, function()
				local strike = Particles.Ground(scatter(root.Position, 5))
				Particles.Beam(root.Position + Vector3.new(0, 1, 0), strike, {
					texture = "Arc",
					color = BOLT,
					width = 3.5,
					lifetime = 0.2,
					emission = 0.4,
				})
				Particles.Burst(CFrame.new(strike + Vector3.new(0, 0.3, 0)), {
					{
						texture = "Crackle",
						color = STORM,
						size = N(2.5),
						transparency = N(0, 1),
						lifetime = R(0.15),
						count = 2,
					},
					{
						texture = "Streak",
						color = STORM,
						size = N(0.3, 0),
						lifetime = R(0.2, 0.3),
						speed = R(12, 20),
						spread = Vector2.new(70, 70),
						acceleration = Vector3.new(0, -30, 0),
						orientation = Enum.ParticleOrientation.VelocityParallel,
						rotation = R(90),
						count = 5,
					},
				})
			end)
		end
		local aura = Particles.Anchor(root.CFrame, Vector3.new(2, 4, 2))
		Particles.Attach(aura, {
			{
				texture = "Arc",
				color = BOLT,
				size = N(4),
				transparency = N(0, 1),
				lifetime = R(0.08, 0.14),
				emission = 0.4,
				rotation = R(-25, 25),
				locked = true,
				rate = 14,
			},
		})
		Particles.Light(aura, rgb(255, 240, 140), 12, 2)
		Particles.Follow(aura, root, CFrame.identity, 1.2, 0.3)
	end,
}

-- Nova: the ground buckles outward from a heavy stomp.
local function quakeResolve(info: ResolveInfo)
	local skill = Skills.ById[info.skillId]
	local radius = skill and skill.radius or 10
	local feet = Particles.Ground(info.origin)
	Particles.GroundWave(feet, DUST, N(2, radius * 2.2), 0.55)
	Particles.GroundWave(feet, RAGE, N(1, radius * 1.4), 0.4)
	Particles.Burst(CFrame.new(feet + Vector3.new(0, 0.3, 0)), {
		{
			texture = "Rubble",
			color = DUST,
			size = N(1.8, 1.2),
			transparency = N(0, 0, 1),
			lifetime = R(0.7, 1),
			speed = R(14, 24),
			spread = Vector2.new(55, 55),
			acceleration = Vector3.new(0, -55, 0),
			rotSpeed = R(-200, 200),
			emission = 0,
			count = 16,
		},
		{
			texture = "Smoke",
			color = DUST,
			size = N(3, 7),
			transparency = N(0.4, 1),
			lifetime = R(1, 1.5),
			speed = R(radius * 1.2, radius * 1.8),
			spread = Vector2.new(88, 88),
			drag = 3,
			emission = 0,
			count = 20,
		},
	}, Vector3.new(4, 0.2, 4))
	Particles.Flash(feet + Vector3.new(0, 2, 0), rgb(255, 180, 110), 20, 0.4)
end

SpellEffects.brute_slam = { resolve = quakeResolve }
SpellEffects.chief_stomp = { resolve = quakeResolve }

-- Falling strike: a volley of arrows rains down across the target area.
local ARROW = C(rgb(110, 85, 60), rgb(70, 55, 40))

local function arrow(landing: Vector3)
	Particles.Burst(CFrame.new(landing + Vector3.new(0, 30, 0)), {
		{
			texture = "Streak",
			color = ARROW,
			size = N(3),
			transparency = N(0),
			lifetime = R(0.3),
			speed = R(100),
			orientation = Enum.ParticleOrientation.VelocityParallel,
			rotation = R(90),
			direction = Enum.NormalId.Bottom,
			emission = 0,
			count = 1,
		},
		{
			texture = "Streak",
			color = C(rgb(255, 250, 235)),
			size = N(6),
			transparency = N(0.55, 1),
			lifetime = R(0.3),
			speed = R(96),
			orientation = Enum.ParticleOrientation.VelocityParallel,
			rotation = R(90),
			direction = Enum.NormalId.Bottom,
			count = 1,
		},
	})
	task.delay(0.3, function()
		Particles.Burst(CFrame.new(landing + Vector3.new(0, 0.2, 0)), {
			{
				texture = "Smoke",
				color = DUST,
				size = N(0.8, 2),
				transparency = N(0.4, 1),
				lifetime = R(0.4, 0.6),
				speed = R(3, 5),
				spread = Vector2.new(70, 70),
				drag = 4,
				emission = 0,
				count = 3,
			},
		})
	end)
end

SpellEffects.archer_volley = {
	resolve = function(info)
		local center = groundTarget(info)
		local skill = Skills.ById[info.skillId]
		local radius = skill and skill.radius or 8
		for _ = 1, 14 do
			task.delay(math.random() * 0.35, function()
				arrow(Particles.Ground(scatter(center, radius)))
			end)
		end
	end,
}

-- Ground eruption: toxic bubbles boil up from a spreading pool of fumes.
SpellEffects.poison_snare = {
	resolve = function(info)
		local center = groundTarget(info)
		local pool = Particles.Anchor(CFrame.new(center + Vector3.new(0, 0.3, 0)), Vector3.new(10, 0.3, 10))
		Particles.Attach(pool, {
			{
				texture = "Smoke",
				color = TOXIC,
				size = N(3, 6),
				transparency = N(1, 0.1, 1),
				lifetime = R(1, 1.6),
				speed = R(0.5, 1.5),
				rotSpeed = R(-30, 30),
				emission = 0,
				rate = 22,
			},
			{
				texture = "Wisp",
				color = TOXIC,
				size = N(1.2, 2.6),
				transparency = N(0.1, 1),
				lifetime = R(0.6, 0.9),
				speed = R(3, 6),
				rotSpeed = R(-90, 90),
				emission = 0.2,
				rate = 16,
			},
			{
				texture = "SoftGlow",
				color = VENOM,
				size = N(0.2, 0.7, 0),
				transparency = N(0.2, 0.5),
				lifetime = R(0.5, 0.8),
				speed = R(2, 4),
				rate = 25,
			},
		})
		Particles.GroundWave(center, VENOM, N(2, 13), 0.5)
		Particles.Light(pool, rgb(120, 210, 60), 14, 1.2)
		task.delay(1.8, Particles.Release, pool, 1.6)
	end,
}

local DARK_SMOKE = C(rgb(40, 25, 50), rgb(15, 10, 20))

local function hexMissile(color: ColorSequence, light: Color3): Recipe
	return {
		cast = function(root, duration)
			return charge(root, duration, { inward("Wisp", color, N(1, 0.4), 30) }, light)
		end,
		projectile = function(body)
			Particles.Attach(body, {
				{
					texture = "Wisp",
					color = color,
					size = N(2.6),
					transparency = N(0, 1),
					lifetime = R(0.15),
					rotSpeed = R(-300, 300),
					emission = 0.4,
					locked = true,
					rate = 40,
				},
				{
					texture = "Smoke",
					color = DARK_SMOKE,
					size = N(1, 2.5),
					transparency = N(0.4, 1),
					lifetime = R(0.5, 0.8),
					rotSpeed = R(-40, 40),
					emission = 0,
					rate = 25,
				},
				{
					texture = "Glint",
					color = color,
					size = N(0.5, 0),
					lifetime = R(0.3, 0.5),
					speed = R(1, 3),
					spread = Vector2.new(180, 180),
					rate = 20,
				},
			})
			Particles.Trail(body, { color = color, width = 0.6, lifetime = 0.3, texture = "TrailStreak" })
			Particles.Light(body, light, 10, 1.5)
		end,
		impact = function(position)
			Particles.Burst(CFrame.new(position), {
				{
					texture = "Wisp",
					color = color,
					size = N(1.5, 4),
					transparency = N(0.1, 1),
					lifetime = R(0.4, 0.6),
					speed = R(4, 8),
					spread = Vector2.new(180, 180),
					drag = 4,
					rotSpeed = R(-200, 200),
					count = 8,
				},
				{
					texture = "Smoke",
					color = DARK_SMOKE,
					size = N(2, 4),
					transparency = N(0.4, 1),
					lifetime = R(0.8, 1.2),
					speed = R(2, 4),
					spread = Vector2.new(180, 180),
					emission = 0,
					count = 6,
				},
			})
			Particles.Flash(position, light, 12, 0.3)
		end,
	}
end

SpellEffects.hex_bolt = hexMissile(VENOM, rgb(120, 210, 60))
SpellEffects.hex_curse = hexMissile(HEX, rgb(150, 80, 220))
SpellEffects.shaman_heal = SpellEffects.mend

return table.freeze(SpellEffects)
