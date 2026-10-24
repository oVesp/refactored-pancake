--!strict

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

--[=[
	Visual recipes for the first batch of spells (Warrior, Mage, Healer). Skills without a recipe
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
				rotation = R(0),
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
				rotation = R(0),
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
				rotation = R(0),
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
				rotation = R(0),
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

return table.freeze(SpellEffects)
