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
	cast: ((root: BasePart, duration: number, hold: number) -> Instance?)?,
	--[=[ Dresses the invisible projectile anchor the controller moves along the flight path. ]=]
	projectile: ((body: BasePart) -> ())?,
	--[=[ Projectile hit at a world position. ]=]
	impact: ((position: Vector3) -> ())?,
	--[=[ Instant (non-projectile) skill resolved on the server. ]=]
	resolve: ((info: ResolveInfo) -> ())?,
	--[=[ Melee swing; also used as the local player's prediction. ]=]
	swing: ((origin: Vector3, aim: Vector3, range: number, angle: number) -> ())?,
	--[=[ Template played where the melee hit lands, in place of the default `HitImpact`. ]=]
	hit: string?,
	--[=[ Hit pause in seconds when the local player lands or takes the hit. ]=]
	hitstop: number?,
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

local DUST = C(rgb(170, 150, 125), rgb(120, 105, 90))

--[=[
	Visual recipes per skill id, for class spells and enemy attacks; a spec requires one for every
	usable skill. Hitboxes are not drawn here; shapes come from textures, so the look is free to
	differ from the server's hit volume.
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

-- Plays a flat ground template on the ground under a point.
local function onGround(name: string, position: Vector3)
	-- Lifted clear of tall grass, like the other ground layers.
	Effects.Play(name, CFrame.new(Particles.Ground(position) + Vector3.new(0, 0.6, 0)))
end

SpellEffects.firebolt = {
	cast = function(root, duration, hold)
		return Effects.Charge("FireCharge", root, duration, hold)
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
	cast = function(root, duration, hold)
		return Effects.Charge("FrostCharge", root, duration, hold)
	end,
	projectile = function(body)
		Effects.Attach("FrostShardBody", body)
	end,
	impact = function(position)
		Effects.Play("FrostBurst", CFrame.new(position))
		groundMark("FrostSplash", position, 5)
	end,
}

SpellEffects.spark = {
	cast = function(root, duration, hold)
		return Effects.Charge("SparkCharge", root, duration, hold)
	end,
	projectile = function(body)
		Effects.Attach("SparkBody", body)
	end,
	impact = function(position)
		Effects.Play("SparkBurst", CFrame.new(position))
	end,
}

-- Holy bolt: a knot of light rays in flight; on the hit a shaft of light drops onto the target and
-- bursts over an ink star, with a gold ring on the ground below.
SpellEffects.smite = {
	cast = function(root, duration, hold)
		return Effects.Charge("HolyCharge", root, duration, hold)
	end,
	projectile = function(body)
		Effects.Attach("SmiteBody", body)
	end,
	impact = function(position)
		Effects.Link("SmiteColumn", position + Vector3.new(0, 30, 0), position, 0.3)
		Effects.Play("SmiteBurst", CFrame.new(position))
		groundMark("HolyRing", position, 6)
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

-- Holy burst: rays blow out of the cleric and a gold shock ring runs to the edge of the knockback.
SpellEffects.rebuke = {
	resolve = function(info)
		Effects.Play("RebukeBurst", CFrame.new(info.origin + Vector3.new(0, 1, 0)))
		onGround("RebukeWave", info.origin)
	end,
}

-- Heal: a green rune seal turns under the ally while leaves of light lift off it.
SpellEffects.mend = {
	cast = function(root, duration, hold)
		return Effects.Charge("LifeCharge", root, duration, hold)
	end,
	resolve = function(info)
		local root = rootOf(info.target) or rootOf(info.caster)
		if not root then
			return
		end
		onGround("MendSeal", root.Position)
		Effects.Play("MendBloom", root.CFrame)
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

-- Turns a CFrame so its top face, which fist and guard templates emit from, points along `look`.
local TOP_ALONG_LOOK = CFrame.Angles(-math.pi / 2, 0, 0)

-- Fist chain (light attacks 1-3): a puff of displaced air off the knuckles; the hit lands as an air
-- burst rather than a blade's cut. The third punch finishes the chain with a bigger burst.
local function punch(template: string): (origin: Vector3, aim: Vector3) -> ()
	return function(origin, aim)
		local look = flatLook(origin, aim)
		if not look then
			return
		end
		local at = origin + look * 1.8 + Vector3.new(0, 0.5, 0)
		Effects.Play(template, CFrame.lookAt(at, at + look) * TOP_ALONG_LOOK)
	end
end

SpellEffects.strike = { swing = punch("PunchJab"), hit = "PunchImpact" }
SpellEffects.strike_2 = { swing = punch("PunchJab"), hit = "PunchImpact" }
SpellEffects.strike_3 = { swing = punch("PunchFinisher"), hit = "PunchImpactHeavy", hitstop = 0.085 }

-- Weapon basics (Content/Weapons): placeholder looks built from existing templates.
-- Sword chain (Content/Skills): the cleave crescent turned to the clip's cut. `roll` tilts it about the
-- look axis (0 level, 90 upright) and `lift` raises it from the waist.
local function slash(roll: number, lift: number): (origin: Vector3, aim: Vector3) -> ()
	return function(origin, aim)
		local look = flatLook(origin, aim)
		if not look then
			return
		end
		local at = origin + look * 1.6 + Vector3.new(0, lift, 0)
		Effects.Play("CleaveSwipe", CFrame.lookAt(at, at + look) * CFrame.Angles(0, 0, math.rad(roll)))
	end
end

SpellEffects.sword_slash = { swing = slash(40, 1.2) } -- diagonal, top right to bottom left
SpellEffects.sword_slash_2 = { swing = slash(0, 0.8) } -- horizontal, left to right
SpellEffects.sword_slash_3 = { swing = slash(90, 1.4), hitstop = 0.085 } -- vertical chop
SpellEffects.staff_strike = { swing = cleaveSwing }
SpellEffects.staff_strike_2 = { swing = cleaveSwing, hitstop = 0.085 }
SpellEffects.shield_bash = { swing = punch("PunchFinisher"), hit = "PunchImpactHeavy", hitstop = 0.085 }

local function scatter(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * radius
	return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- Ground eruption: rime spreads over the area and ice splinters stab up at staggered points.
SpellEffects.ice_patch = {
	cast = function(root, duration, hold)
		return Effects.Charge("FrostCharge", root, duration, hold)
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

SpellEffects.sword_heavy = SpellEffects.heavy_strike

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

-- Falling strike (high tier): a wide shaft of light drops onto the ally and bursts at their feet over
-- a turning gold seal; the caster's screen flashes gold with speed lines.
SpellEffects.lay_on_hands = {
	resolve = function(info)
		local root = rootOf(info.target) or rootOf(info.caster)
		if not root then
			return
		end
		local feet = Particles.Ground(root.Position)
		-- The column sinks below ground so its tapered end does not float over the ally.
		Effects.Link("LayOnHandsColumn", feet + Vector3.new(0, 40, 0), feet - Vector3.new(0, 4, 0), 0.8)
		task.delay(0.12, function()
			onGround("LayOnHandsImpact", feet)
		end)
		if isLocal(info.caster) then
			Effects.Screen("HolyFlash")
			Effects.Screen("SpeedLines")
		end
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

-- Heal over time: a faint seal holds under the ally while leaves spiral up around them.
SpellEffects.renew = {
	resolve = function(info)
		local root = rootOf(info.target) or rootOf(info.caster)
		if not root then
			return
		end
		local feet = Particles.Ground(root.Position)
		onGround("RenewSeal", feet)
		local offset = CFrame.new(0, feet.Y - root.Position.Y + 0.3, 0)
		local aura = Particles.Anchor(root.CFrame * offset, Vector3.new(3.5, 0.2, 3.5))
		Effects.Attach("RenewAura", aura)
		Particles.Follow(aura, root, offset, 3, 1.5)
	end,
}

-- Ward: a ribbon of light runs from the cleric to the ally, then a gold hex ward closes around them.
SpellEffects.shelter = {
	resolve = function(info)
		local target = rootOf(info.target) or rootOf(info.caster)
		if not target then
			return
		end
		local caster = rootOf(info.caster)
		if caster and caster ~= target then
			Effects.Link("ShelterLink", caster.Position + Vector3.new(0, 0.5, 0), target, 0.4)
		end
		task.delay(0.1, function()
			local ward = Particles.Anchor(target.CFrame)
			Effects.Attach("ShelterBubble", ward)
			Particles.Follow(ward, target, CFrame.identity, 1.8, 0.6)
			Effects.Play("ShelterBurst", target.CFrame)
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

-- Nova: the ground cracks under a heavy stomp, a dust ring rolls out and rubble flies.
local function quakeResolve(template: string): (ResolveInfo) -> ()
	return function(info)
		local feet = Particles.Ground(info.origin)
		local yaw = CFrame.Angles(0, math.random() * math.pi * 2, 0)
		-- Lifted clear of tall grass, like the other ground layers.
		Effects.Play(template, CFrame.new(feet + Vector3.new(0, 0.6, 0)) * yaw)
		Effects.Play("HitShake", CFrame.new(feet))
	end
end

SpellEffects.brute_slam = { resolve = quakeResolve("BruteSlam") }
SpellEffects.chief_stomp = { resolve = quakeResolve("ChiefStomp") }

-- Falling strike: a volley of arrows rains down across the target area.
SpellEffects.archer_volley = {
	resolve = function(info)
		local center = groundTarget(info)
		local skill = Skills.ById[info.skillId]
		local radius = skill and skill.radius or 8
		for _ = 1, 14 do
			task.delay(math.random() * 0.35, function()
				local landing = Particles.Ground(scatter(center, radius))
				Effects.Play("ArrowFall", CFrame.new(landing + Vector3.new(0, 30, 0)))
				task.delay(0.3, function()
					Effects.Play("ArrowLand", CFrame.new(landing + Vector3.new(0, 0.2, 0)))
				end)
			end)
		end
	end,
}

-- Ground eruption: a toxic stain soaks the ground while bubbles boil up and pop across it.
SpellEffects.poison_snare = {
	resolve = function(info)
		local center = groundTarget(info)
		onGround("PoisonStain", center)
		local pool = Particles.Anchor(CFrame.new(center + Vector3.new(0, 0.6, 0)), Vector3.new(10, 0.3, 10))
		Effects.Attach("PoisonPool", pool)
		task.delay(1.8, Particles.Release, pool, 1.2)
	end,
}

-- Hex missile: a wisp gathers at the hand, flies in a tinted haze and bursts into an unwinding swirl.
local function hexMissile(kind: string): Recipe
	return {
		cast = function(root, duration, hold)
			return Effects.Charge(kind .. "Charge", root, duration, hold)
		end,
		projectile = function(body)
			Effects.Attach(kind .. "Body", body)
		end,
		impact = function(position)
			Effects.Play(kind .. "Burst", CFrame.new(position))
		end,
	}
end

SpellEffects.hex_bolt = hexMissile("Venom")
SpellEffects.hex_curse = hexMissile("Hex")
SpellEffects.shaman_heal = SpellEffects.mend

-- Charge-up by template, shared by the recipes below.
local function charge(template: string): (root: BasePart, duration: number, hold: number) -> Instance?
	return function(root, duration, hold)
		return Effects.Charge(template, root, duration, hold)
	end
end

-- A flying bolt: `body` worn in flight, `burst` where it lands, `cast` (optional) at the hand first.
local function bolt(body: string, burst: string, cast: string?): Recipe
	return {
		cast = if cast then charge(cast) else nil,
		projectile = function(flying)
			Effects.Attach(body, flying)
		end,
		impact = function(position)
			Effects.Play(burst, CFrame.new(position))
		end,
	}
end

SpellEffects.staff_bolt = bolt("ArcaneBody", "ArcaneBurst", "ArcaneCharge")
SpellEffects.magic_arrow = bolt("ArcaneBody", "ArcaneBurst", "ArcaneCharge")
SpellEffects.wand_bolt = bolt("ArcaneBody", "ArcaneBurst")
SpellEffects.wand_bolt_2 = SpellEffects.wand_bolt
SpellEffects.wand_bolt_3 = SpellEffects.wand_bolt
SpellEffects.wand_blast = bolt("ArcaneBlastBody", "ArcaneBurst", "ArcaneCharge")
SpellEffects.destruction_water = bolt("WaterBody", "WaterBurst", "WaterCharge")
SpellEffects.sleep = bolt("SleepBody", "SleepBurst", "HexCharge")
SpellEffects.bow_shot = bolt("ArrowBody", "ArrowLand")
SpellEffects.guard_bolt = bolt("ArrowBody", "ArrowLand")
SpellEffects.sling_shot = bolt("SlingBody", "ArrowLand")
SpellEffects.poison_dart = bolt("DartBody", "VenomBurst")

-- A buff on the caster or the targeted ally, and the optional charge before it.
local function bodyBuff(template: string, cast: string?): Recipe
	return {
		cast = if cast then charge(cast) else nil,
		resolve = function(info)
			local root = rootOf(info.target) or rootOf(info.caster)
			if root then
				Effects.Play(template, root.CFrame)
			end
		end,
	}
end

SpellEffects.gather_strength = bodyBuff("MightBuff")
SpellEffects.battle_trance = bodyBuff("MightBuff")
SpellEffects.second_wind = bodyBuff("VigorBuff")
SpellEffects.heightened_senses = bodyBuff("FocusBuff")
SpellEffects.quick_march = bodyBuff("SwiftBuff", "ArcaneCharge")
SpellEffects.light = bodyBuff("LightBuff", "HolyCharge")
SpellEffects.glow = bodyBuff("LightBuff", "HolyCharge")
SpellEffects.bless = bodyBuff("BlessBuff", "HolyCharge")
SpellEffects.cleanse = bodyBuff("CleanseBuff", "LifeCharge")
SpellEffects.anti_evil_protection = {
	cast = charge("HolyCharge"),
	resolve = SpellEffects.shelter.resolve,
}

-- A spell worked on the aimed object, such as a well or a brazier.
local function atAim(template: string, cast: string): Recipe
	return {
		cast = charge(cast),
		resolve = function(info)
			Effects.Play(template, CFrame.new(info.aim))
		end,
	}
end

SpellEffects.kindle = atAim("KindleFlare", "FireCharge")
SpellEffects.purify_water = atAim("WaterBurst", "WaterCharge")
SpellEffects.create_water = atAim("WaterBurst", "WaterCharge")

SpellEffects.create_undead = {
	cast = charge("HexCharge"),
	resolve = function(info)
		onGround("UndeadRise", info.origin)
	end,
}

-- Backward leap: dust at take-off and a streak along the path.
SpellEffects.disengage = {
	resolve = function(info)
		local root = rootOf(info.caster)
		if root then
			local takeoff = Particles.Ground(info.origin) + Vector3.new(0, 0.5, 0)
			Effects.Play("ChargeDust", CFrame.lookAt(takeoff, takeoff - root.CFrame.LookVector))
			dashStreak(info.origin, root.Position, DUST, 2)
		end
	end,
}

-- The rally shout: the war cry's wave, with no screen tint since only monsters use it.
SpellEffects.captain_rally = {
	resolve = function(info)
		Effects.Play("WarCryWave", CFrame.new(Particles.Ground(info.origin) + Vector3.new(0, 0.6, 0)))
	end,
}

-- Enemy melee: a thrust for stabs, the sword crescent for blades, an upright rake for claws.
SpellEffects.goblin_stab = { swing = punch("PunchJab") }
SpellEffects.guard_strike = { swing = slash(-40, 1.2) }
SpellEffects.soldier_strike = { swing = slash(40, 1.2) }
SpellEffects.chief_cleave = { swing = cleaveSwing }
SpellEffects.skeleton_scratch = { swing = slash(70, 1) }
SpellEffects.zombie_claw = { swing = slash(-70, 1) }

return table.freeze(SpellEffects)
