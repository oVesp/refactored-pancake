--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Skills = require(ReplicatedStorage.Content.Skills)

local Effects = require(script.Parent.Effects)
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
	cast: ((root: BasePart, duration: number) -> Instance?)?,
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

local function isLocal(model: Model?): boolean
	return model ~= nil and model == Players.LocalPlayer.Character
end

local function rootOf(model: Model?): BasePart?
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	return if root and root:IsA("BasePart") then root else nil
end

local function flatLook(origin: Vector3, aim: Vector3): Vector3?
	local look = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	return if look.Magnitude > 1e-3 then look.Unit else nil
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

local HOLY = C(rgb(255, 255, 240), rgb(255, 225, 140), rgb(255, 170, 70))
local LIFE = C(rgb(235, 255, 220), rgb(140, 255, 150), rgb(255, 245, 170))
local RAGE = C(rgb(255, 220, 160), rgb(255, 100, 40), rgb(150, 20, 10))
local DUST = C(rgb(170, 150, 125), rgb(120, 105, 90))
-- Darker, normal-blended tints for shapes that must read on bright daylight ground.
local WARD = C(rgb(240, 250, 255), rgb(150, 200, 255), rgb(90, 130, 255))
local GROWTH = C(rgb(200, 255, 160), rgb(80, 210, 90), rgb(30, 130, 60))
local VENOM = C(rgb(220, 255, 170), rgb(120, 210, 60), rgb(40, 90, 30))
local TOXIC = C(rgb(170, 235, 90), rgb(90, 160, 40), rgb(45, 90, 25))
local HEX = C(rgb(230, 190, 255), rgb(130, 60, 190), rgb(40, 15, 60))

--[=[
	Visual recipes per skill id, for class spells and enemy attacks. Skills without a recipe
	keep the controller's placeholder visuals. Hitboxes are not drawn here; shapes come from
	textures, so the look is free to differ from the server's hit volume.
]=]
local SpellEffects: { [string]: Recipe } = {}

-- Plays a flat ground template under a mid-air hit when the ground is close enough to be touched.
local function groundMark(name: string, position: Vector3, reach: number)
	local ground = Particles.Ground(position)
	if (position - ground).Magnitude <= reach then
		local yaw = CFrame.Angles(0, math.random() * math.pi * 2, 0)
		-- Lifted clear of tall grass, like the other ground layers.
		Effects.Play(name, CFrame.new(ground + Vector3.new(0, 0.6, 0)) * yaw)
	end
end

SpellEffects.firebolt = {
	cast = function(root, duration)
		return Effects.Charge("FireCharge", root, duration)
	end,
	projectile = function(body)
		Effects.Attach("FireboltBody", body)
	end,
	impact = function(position)
		Effects.Play("FireboltBurst", CFrame.new(position))
		groundMark("Scorch", position, 5)
	end,
}

SpellEffects.frost_shard = {
	projectile = function(body)
		Effects.Attach("FrostShardBody", body)
	end,
	impact = function(position)
		Effects.Play("FrostBurst", CFrame.new(position))
		groundMark("FrostSplash", position, 5)
	end,
}

SpellEffects.spark = {
	projectile = function(body)
		Effects.Attach("SparkBody", body)
	end,
	impact = function(position)
		Effects.Play("SparkBurst", CFrame.new(position))
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

-- Wide sweep: two level blades fanned around the front of the warrior at waist height.
local function cleaveSwing(origin: Vector3, aim: Vector3)
	local look = flatLook(origin, aim)
	if not look then
		return
	end
	local at = origin + look * 1.2 + Vector3.new(0, 0.2, 0)
	Effects.Play("CleaveSwipe", CFrame.lookAt(at, at + look))
end

SpellEffects.cleave = {
	swing = cleaveSwing,
}

-- Rage rings race out across the ground, embers lift, and the caster's screen flushes red.
SpellEffects.war_cry = {
	resolve = function(info)
		local feet = Particles.Ground(info.origin)
		Effects.Play("WarCryWave", CFrame.new(feet + Vector3.new(0, 0.6, 0)))
		Effects.Play("HitShake", CFrame.new(feet))
		if isLocal(info.caster) then
			Effects.Screen("RageTint")
		end
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

-- Light attack: a flat, level crescent swept around the front of the attacker at chest height.
SpellEffects.strike = {
	swing = function(origin, aim)
		local look = flatLook(origin, aim)
		if not look then
			return
		end
		local at = origin + look * 0.8 + Vector3.new(0, 0.5, 0)
		Effects.Play("StrikeSwipe", CFrame.lookAt(at, at + look))
	end,
}

local function scatter(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * radius
	return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Ground eruption: rime spreads over the area and ice splinters stab up at staggered points.
SpellEffects.ice_patch = {
	cast = function(root, duration)
		return Effects.Charge("FrostCharge", root, duration)
	end,
	resolve = function(info)
		local center = groundTarget(info)
		local yaw = CFrame.Angles(0, math.random() * math.pi * 2, 0)
		Effects.Play("IcePatchFloor", CFrame.new(center + Vector3.new(0, 0.6, 0)) * yaw)
		for i = 1, 8 do
			local point = if i == 1 then center else scatter(center, 6)
			task.delay((i - 1) * 0.045, function()
				Effects.Play("IceSpike", CFrame.new(Particles.Ground(point)))
			end)
		end
	end,
}

-- Fits a cone template to a skill: each emitter's `Reach` share of the range sets its speed (the
-- flames cover it in 0.45 s) and its `Arc` share of the angle sets its sideways spread.
local function aimCone(part: BasePart, range: number, angle: number)
	local speed = range / 0.45
	for _, item in part:GetDescendants() do
		if not item:IsA("ParticleEmitter") then
			continue
		end
		local reach = item:GetAttribute("Reach")
		local arc = item:GetAttribute("Arc")
		if typeof(reach) == "number" then
			item.Speed = NumberRange.new(speed * reach * 0.8, speed * reach)
		end
		if typeof(arc) == "number" then
			item.SpreadAngle = Vector2.new(item.SpreadAngle.X, angle * arc)
		end
	end
end

-- Fire breath: a short stream of flame jets fanning out from the hands.
SpellEffects.flame_fan = {
	swing = function(origin, aim, range, angle)
		local look = flatLook(origin, aim)
		if not look then
			return
		end
		local start = origin + Vector3.new(0, 0.6, 0) + look * 1.5
		local nozzle = Particles.Anchor(CFrame.lookAt(start, start + look))
		Effects.Attach("FlameFanJet", nozzle)
		aimCone(nozzle, range, angle)
		task.delay(0.35, Particles.Release, nozzle, 1.3)
		-- Scorch marks spread through the cone once the flames reach the ground.
		task.delay(0.25, function()
			for _ = 1, 3 do
				local turn = CFrame.Angles(0, math.rad((math.random() - 0.5) * angle * 0.8), 0)
				local reach = range * (0.35 + 0.55 * math.random())
				local point = origin + turn:VectorToWorldSpace(look) * reach
				groundMark("Scorch", point, 6)
			end
		end)
	end,
}

-- Overhead blow: a tall crescent arcs down, then the ground cracks and a shock ring tears outward.
SpellEffects.heavy_strike = {
	swing = function(origin, aim, range)
		local look = flatLook(origin, aim)
		if not look then
			return
		end
		local spot = Particles.Ground(origin + look * range * 0.6)
		Effects.Play("HeavySwipe", CFrame.new(spot + Vector3.new(0, 3, 0)))
		task.delay(0.07, function()
			local yaw = CFrame.Angles(0, math.random() * math.pi * 2, 0)
			-- Lifted clear of tall grass so the crack and ring stay visible.
			Effects.Play("GroundSlam", CFrame.new(spot + Vector3.new(0, 0.6, 0)) * yaw)
			Effects.Play("HitShake", CFrame.new(spot))
		end)
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

-- Dash: dust kicked back at take-off, a streak along the path and a crunch on arrival (the
-- `burst` template). `speedLines` adds the screen rush for the caster.
local function chargeResolve(color: ColorSequence, burst: string, speedLines: boolean): (ResolveInfo) -> ()
	return function(info)
		local root = rootOf(info.caster)
		if not root or (root.Position - info.origin).Magnitude < 2 then
			return
		end
		local feet = Particles.Ground(info.origin)
		local takeoff = feet + Vector3.new(0, 0.5, 0)
		Effects.Play("ChargeDust", CFrame.lookAt(takeoff, takeoff + root.CFrame.LookVector))
		dashStreak(info.origin, root.Position, color, 3)
		if speedLines and isLocal(info.caster) then
			Effects.Screen("SpeedLines")
		end
		task.delay(0.12, function()
			local hit = Particles.Ground(root.Position + root.CFrame.LookVector * 2.5)
			Effects.Play(burst, CFrame.new(hit + Vector3.new(0, 0.6, 0)))
			Effects.Play("HitShake", CFrame.new(hit))
		end)
	end
end

SpellEffects.charge = { resolve = chargeResolve(C(rgb(235, 240, 255), rgb(130, 150, 190)), "ChargeBurst", true) }
SpellEffects.wolf_charge = { resolve = chargeResolve(DUST, "ChargeHit", false) }

-- Plays a flat ground template on the ground under a point.
local function onGround(name: string, position: Vector3)
	-- Lifted clear of tall grass, like the other ground layers.
	Effects.Play(name, CFrame.new(Particles.Ground(position) + Vector3.new(0, 0.6, 0)))
end

-- Teleport: a vortex swallows the mage, a streak and a thin bolt mark the jump, a vortex unwinds
-- at the arrival with a ring across the ground and a violet flash for the caster.
SpellEffects.blink = {
	resolve = function(info)
		local root = rootOf(info.caster)
		if not root then
			return
		end
		local from = info.origin + Vector3.new(0, 0.5, 0)
		Effects.Play("BlinkOut", CFrame.new(from))
		if (root.Position - info.origin).Magnitude > 2 then
			Effects.Link("BlinkTrail", from, root.Position, 0.3)
		end
		Effects.Play("BlinkIn", CFrame.new(root.Position))
		onGround("ArcaneRing", root.Position)
		if isLocal(info.caster) then
			Effects.Screen("BlinkFlash")
		end
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

-- Ward: a shimmering hex bubble with crawling swirls clings to the mage; a ring runs across the ground.
SpellEffects.arcane_shield = {
	resolve = function(info)
		local root = rootOf(info.caster)
		if not root then
			return
		end
		local aura = Particles.Anchor(root.CFrame)
		Effects.Attach("ArcaneShieldBubble", aura)
		Particles.Follow(aura, root, CFrame.identity, 2.2, 0.8)
		Effects.Play("ArcaneShieldBurst", root.CFrame)
		onGround("WardRing", root.Position)
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

-- Chains: lightning forks from the mage into the ground around them while arcs crawl over the body;
-- the caster's screen washes yellow with speed lines.
SpellEffects.overcharge = {
	resolve = function(info)
		local root = rootOf(info.caster)
		if not root then
			return
		end
		for i = 1, 4 do
			task.delay((i - 1) * 0.07, function()
				local strike = Particles.Ground(scatter(root.Position, 5))
				Effects.Link("OverchargeBolt", root.Position + Vector3.new(0, 1, 0), strike, 0.2)
				onGround("OverchargeStrike", strike)
			end)
		end
		local aura = Particles.Anchor(root.CFrame, Vector3.new(2, 4, 2))
		Effects.Attach("OverchargeAura", aura)
		Particles.Follow(aura, root, CFrame.identity, 1.2, 0.3)
		if isLocal(info.caster) then
			Effects.Screen("StormTint")
			Effects.Screen("SpeedLines")
		end
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
