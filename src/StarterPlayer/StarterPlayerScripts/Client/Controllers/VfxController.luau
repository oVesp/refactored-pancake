--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local AnimRoles = require(ReplicatedStorage.Content.AnimRoles)
local Skills = require(ReplicatedStorage.Content.Skills)

local Animations = require(script.Parent.Parent.Animation.Animations)
local Effects = require(script.Parent.Parent.Vfx.Effects)
local Particles = require(script.Parent.Parent.Vfx.Particles)
local SpellEffects = require(script.Parent.Parent.Vfx.SpellEffects)
local Logger = require(ReplicatedStorage.Shared.Logger)

local log = Logger.new("Vfx")

local TYPE_COLORS: { [string]: Color3 } = {
	physical = Color3.fromRGB(230, 230, 230),
	force = Color3.fromRGB(170, 140, 255),
	fire = Color3.fromRGB(255, 120, 40),
	cold = Color3.fromRGB(140, 210, 255),
	lightning = Color3.fromRGB(255, 240, 120),
	holy = Color3.fromRGB(255, 235, 170),
	poison = Color3.fromRGB(120, 220, 90),
	negative = Color3.fromRGB(150, 90, 200),
}

local DAMAGE_COLORS: { [string]: Color3 } = {
	damage = Color3.fromRGB(255, 255, 255),
	shielded = Color3.fromRGB(160, 200, 255),
	heal = Color3.fromRGB(110, 255, 130),
	shield = Color3.fromRGB(140, 190, 255),
	immune = Color3.fromRGB(200, 200, 200),
	dodged = Color3.fromRGB(200, 200, 200),
	parried = Color3.fromRGB(255, 220, 120),
	blocked = Color3.fromRGB(190, 200, 220),
}

local PARRY_COLOR = Color3.fromRGB(255, 210, 110)
-- Flash on the bow hand at full draw: the perfect release window opens.
local DRAW_READY_COLOR = Color3.fromRGB(255, 225, 140)

local TELEGRAPH_COLOR = Color3.fromRGB(255, 70, 50)

-- Fade times (seconds) for the local player's skill clips.
local CLIP_FADE_IN = 0.05
local CLIP_FADE_OUT = 0.15
local DEFAULT_HIT_TIME = 0.2 -- swing time for a clip with neither a marker nor a baked `Hit`
local HIT_GRACE = 0.06 -- seconds past the baked `Hit` time before the swing shows without the marker

--[=[
	Visuals for casts, telegraphs, projectiles, impacts and floating damage numbers, plus the local
	player's skill clips (`SkillDef.animation`, Action priority). Skills with a recipe in
	`Vfx/SpellEffects` get textured particle effects; the rest keep neon placeholders. Everything
	here is cosmetic and client-only; the server already decided the outcome.
]=]
local VfxController = {}

local UIController: any
local AudioController: any
local CombatController: any

type Flight = { part: BasePart, recipe: SpellEffects.Recipe? }

local projectiles: { [number]: Flight } = {}
-- The local character's skill clips by skill id, loaded when the character spawns.
local skillTracks: { [string]: AnimationTrack } = {}
local charges: { [Instance]: Instance? } = {}
local effectsFolder: Folder

local function neon(size: Vector3, cframe: CFrame, color: Color3, transparency: number?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Transparency = transparency or 0.2
	part.Parent = effectsFolder
	return part
end

local ground = Particles.Ground

local function disc(center: Vector3, radius: number, color: Color3, duration: number)
	local base = ground(center)
	local ring = neon(
		Vector3.new(0.2, radius * 2, radius * 2),
		CFrame.new(base + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color,
		0.65
	)
	ring.Shape = Enum.PartType.Cylinder
	local fill = neon(Vector3.new(0.25, 0.1, 0.1), ring.CFrame, color, 0.35)
	fill.Shape = Enum.PartType.Cylinder
	TweenService:Create(
		fill,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(0.25, radius * 2, radius * 2) }
	):Play()
	Debris:AddItem(ring, duration + 0.1)
	Debris:AddItem(fill, duration + 0.1)
end

local function burst(position: Vector3, radius: number, color: Color3)
	local ball = neon(Vector3.one, CFrame.new(position), color, 0.3)
	ball.Shape = Enum.PartType.Ball
	local tween = TweenService:Create(ball, TweenInfo.new(0.3), { Size = Vector3.one * radius * 2, Transparency = 1 })
	tween:Play()
	Debris:AddItem(ball, 0.35)
end

local function arc(origin: Vector3, aim: Vector3, range: number, color: Color3)
	local look = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	if look.Magnitude < 1e-3 then
		return
	end
	local cframe = CFrame.lookAt(origin, origin + look) * CFrame.new(0, 0, -range / 2)
	local slab = neon(Vector3.new(range * 0.9, 0.3, range), cframe, color, 0.55)
	TweenService:Create(slab, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	Debris:AddItem(slab, 0.3)
end

local function skillColor(skillId: string): Color3
	local skill = Skills.ById[skillId]
	local damageType = skill and skill.damage and skill.damage.type
	if damageType then
		return TYPE_COLORS[damageType] or Color3.new(1, 1, 1)
	end
	return if skill and (skill.heal or skill.shield) then TYPE_COLORS.holy else Color3.fromRGB(180, 160, 255)
end

local function soundFor(skill: any): string
	local damageType = skill.damage and skill.damage.type
	if damageType == "fire" then
		return "Fire"
	elseif damageType == "lightning" or damageType == "cold" then
		return "Zap"
	elseif skill.heal or skill.shield or skill.delivery == "Ally" then
		return "Heal"
	end
	return "Swing"
end

local function telegraph(info: { [string]: any })
	local skill = Skills.ById[info.skillId]
	if not skill then
		return
	end
	if skill.delivery == "SelfArea" then
		disc(info.origin, skill.radius or 6, TELEGRAPH_COLOR, info.duration)
	elseif skill.delivery == "Ground" then
		disc(info.aim, skill.radius or 6, TELEGRAPH_COLOR, info.duration)
	elseif skill.delivery == "Melee" or skill.delivery == "Cone" then
		local look = Vector3.new(info.aim.X - info.origin.X, 0, info.aim.Z - info.origin.Z)
		if look.Magnitude > 1e-3 then
			local range = skill.range or 6
			local cframe = CFrame.lookAt(ground(info.origin), ground(info.origin) + look)
				* CFrame.new(0, 0.2, -range / 2)
			local slab = neon(Vector3.new(range * 0.8, 0.2, range), cframe, TELEGRAPH_COLOR, 0.6)
			Debris:AddItem(slab, info.duration)
		end
	end
	if info.caster and info.caster:GetAttribute("Team") == "Goblins" then
		AudioController.PlayAt("GoblinBark", info.origin)
	end
end

local function isLocalCaster(caster: Instance?): boolean
	return caster ~= nil and caster == Players.LocalPlayer.Character
end

local function endFlight(id: number)
	local flight = projectiles[id]
	if not flight then
		return
	end
	projectiles[id] = nil
	if flight.recipe then
		Particles.Release(flight.part, 0.8)
	else
		flight.part:Destroy()
	end
end

local function launch(info: { [string]: any }, skill: any)
	local recipe: SpellEffects.Recipe? = SpellEffects[info.skillId]
	local start = CFrame.lookAt(info.origin, info.origin + info.direction)
	local part: BasePart
	if recipe and recipe.projectile then
		part = Particles.Anchor(start)
		recipe.projectile(part)
	else
		part = neon(Vector3.new(0.8, 0.8, 2.4) * (skill.projectileScale or 1), start, skillColor(info.skillId), 0)
		recipe = nil
	end
	local id = info.id
	projectiles[id] = { part = part, recipe = recipe }
	AudioController.PlayAt(soundFor(skill), info.origin)
	local travelled = 0
	local position: Vector3 = info.origin
	local direction: Vector3 = info.direction
	local homing: Instance? = info.homing
	-- Arrows fall like the server's (`gravity`); speed along the path grows as they drop.
	local velocity = direction * info.speed
	local fall = Vector3.new(0, -(info.gravity or 0), 0)
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not part.Parent or not projectiles[id] then
			connection:Disconnect()
			return
		end
		velocity += fall * dt
		local step = velocity.Magnitude * dt
		travelled += step
		if travelled >= info.range then
			connection:Disconnect()
			endFlight(id)
			return
		end
		-- Homing spells steer toward the target's current position; the server decides the hit.
		local targetRoot = homing and homing:FindFirstChild("HumanoidRootPart")
		if targetRoot and targetRoot:IsA("BasePart") then
			local offset = targetRoot.Position - position
			if offset.Magnitude > 1e-3 then
				direction = offset.Unit
			end
		else
			direction = velocity.Unit
		end
		position += direction * step
		part.CFrame = CFrame.lookAt(position, position + direction)
	end)
	Debris:AddItem(part, info.range / info.speed + 1.5)
end

local function startCharge(info: { [string]: any }, skill: any)
	local recipe = SpellEffects[info.skillId]
	local caster = info.caster
	local root = caster and (caster:FindFirstChild("HumanoidRootPart") or caster.PrimaryPart)
	if recipe and recipe.cast and root and root:IsA("BasePart") then
		local previous = charges[caster]
		if previous then
			previous:Destroy()
		end
		charges[caster] = recipe.cast(root, info.duration)
	else
		burst(info.origin + Vector3.new(0, 1, 0), 2, skillColor(skill.id))
	end
end

local function cancelCharge(caster: Instance?)
	local charge = caster and charges[caster]
	if charge then
		charges[caster :: Instance] = nil
		charge:Destroy()
	end
end

-- Light swings carry no telegraph: the owner's client draws them at the clip's `Hit` marker.
local function predictsSwing(skill: any): boolean
	return skill.telegraph == false or not skill.windup
end

local function onResolve(info: { [string]: any }, skill: any)
	if info.caster then
		charges[info.caster] = nil
	end
	local recipe = SpellEffects[info.skillId]
	if not recipe then
		return
	end
	if recipe.resolve then
		recipe.resolve(info :: any)
	elseif recipe.swing and not (isLocalCaster(info.caster) and predictsSwing(skill)) then
		-- The local player's committed melee swings were already predicted at the clip's Hit marker.
		recipe.swing(info.origin, info.aim, skill.range or 6, skill.angle or 90)
	end
end

local function onCast(info: { [string]: any })
	local skill = Skills.ById[info.skillId or ""]
	if not skill then
		return
	end
	if info.kind == "Projectile" then
		launch(info, skill)
	elseif info.kind == "Telegraph" then
		telegraph(info)
	elseif info.kind == "Cast" then
		startCharge(info, skill)
	elseif info.kind == "Interrupted" then
		cancelCharge(info.caster)
		local track = skillTracks[info.skillId]
		if track and isLocalCaster(info.caster) then
			track:Stop(CLIP_FADE_OUT)
		end
	elseif info.kind == "Resolve" then
		onResolve(info, skill)
	end
end

local function onImpact(id: number, position: Vector3, kind: string)
	local flight = projectiles[id]
	endFlight(id)
	if kind == "hit" and flight and flight.recipe and flight.recipe.impact then
		flight.recipe.impact(position)
		AudioController.PlayAt("Hit", position)
	elseif kind == "hit" then
		burst(position, 2.5, Color3.fromRGB(255, 220, 160))
		AudioController.PlayAt("Hit", position)
	elseif kind == "interrupt" then
		burst(position + Vector3.new(0, 2, 0), 3, Color3.fromRGB(255, 255, 255))
	end
end

local MELEE_DELIVERIES = { Melee = true, Cone = true, Dash = true }

-- Turns a CFrame so its top face, which hit templates emit from, points along `look`.
local TOP_ALONG_LOOK = CFrame.Angles(-math.pi / 2, 0, 0)

local function rootOf(model: Model?): BasePart?
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	return if root and root:IsA("BasePart") then root else nil
end

-- Level unit vector from `root` toward `source`'s root, or nil when there is none.
local function towardSource(root: BasePart, source: Model?): Vector3?
	local sourceRoot = rootOf(source)
	local toward = sourceRoot and (sourceRoot.Position - root.Position) * Vector3.new(1, 0, 1)
	return if toward and toward.Magnitude > 1e-3 then toward.Unit else nil
end

-- Template frame at `at` with its top face along `look`; plain position without a direction.
local function facing(at: Vector3, look: Vector3?): CFrame
	return if look then CFrame.lookAt(at, at + look) * TOP_ALONG_LOOK else CFrame.new(at)
end

local function involvesLocal(a: Model?, b: Model?): boolean
	local character = Players.LocalPlayer.Character
	return character ~= nil and (a == character or b == character)
end

-- Melee hit on a body: the recipe's impact (default `HitImpact`) along the blow, white flash and
-- light; hitstop and shake when the local player gives or takes it.
local function meleeImpact(model: Model, root: BasePart, source: Model?, crit: boolean, recipe: SpellEffects.Recipe?)
	local toward = towardSource(root, source)
	local at = root.Position + Vector3.new(0, 0.5, 0) + (if toward then toward * 0.8 else Vector3.zero)
	Effects.Play(recipe and recipe.hit or "HitImpact", facing(at, toward and -toward))
	Effects.BodyFlash(model, Color3.new(1, 1, 1), if crit then 0.22 else 0.14)
	Particles.Flash(at, Color3.fromRGB(220, 230, 255), 14, 0.15)
	if involvesLocal(model, source) then
		local hitstop = recipe and recipe.hitstop or 0.055
		Effects.Hitstop({ model, source }, if crit then hitstop + 0.035 else hitstop)
		Effects.Play("HitShake", CFrame.new(at))
	end
end

-- Hit taken on a guard: sparks off the front of the defender, toward the attacker.
local function blockImpact(root: BasePart, source: Model?)
	local toward = towardSource(root, source)
	local at = root.Position + Vector3.new(0, 0.8, 0) + (if toward then toward * 1.1 else Vector3.zero)
	Effects.Play("BlockSpark", facing(at, toward))
end

-- Parry: a gold clang at the defender's guard facing the attacker, a gold body flash, and hitstop
-- and shake when the local player is either side of it.
local function onParry(defender: Model?, attacker: Model?)
	local root = rootOf(defender)
	if not root or not defender then
		return
	end
	local toward = towardSource(root, attacker)
	local at = root.Position + Vector3.new(0, 0.8, 0) + (if toward then toward * 1.3 else Vector3.zero)
	Effects.Play("ParryClash", facing(at, toward))
	Effects.BodyFlash(defender, PARRY_COLOR, 0.2)
	Particles.Flash(at, PARRY_COLOR, 18, 0.2)
	AudioController.PlayAt("Hit", at)
	if involvesLocal(defender, attacker) then
		Effects.Hitstop({ defender, attacker }, 0.12)
		Effects.Play("HitShake", CFrame.new(at))
	end
end

local function onDamage(model: Model, amount: number, kind: string, crit: boolean, skillId: string?, source: Model?)
	local root = model and model:FindFirstChild("HumanoidRootPart") or (model and model.PrimaryPart)
	if not root or not root:IsA("BasePart") then
		return
	end
	local skill = skillId and Skills.ById[skillId]
	if (kind == "damage" or kind == "shielded") and skill and MELEE_DELIVERIES[skill.delivery] then
		meleeImpact(model, root, source, crit, SpellEffects[skill.id])
	elseif kind == "blocked" then
		blockImpact(root, source)
	end
	local gui = UIController.Clone("DamageNumber") :: BillboardGui
	local text = gui:FindFirstChild("Bind_Text", true) :: TextLabel
	local word = if kind == "immune"
		then "Immune"
		elseif kind == "dodged" then "Dodged"
		elseif kind == "parried" then "Parried"
		else nil
	text.Text = word or string.format(if kind == "heal" then "+%d" elseif crit then "%d!" else "%d", amount)
	text.TextColor3 = if crit then Color3.fromRGB(255, 200, 60) else DAMAGE_COLORS[kind] or Color3.new(1, 1, 1)
	gui.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.5, 0)
	gui.Adornee = root
	gui.Parent = effectsFolder
	TweenService:Create(gui, TweenInfo.new(0.9), { StudsOffset = gui.StudsOffset + Vector3.new(0, 2.5, 0) }):Play()
	TweenService
		:Create(text, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 })
		:Play()
	Debris:AddItem(gui, 1)
	if kind == "damage" or kind == "shielded" or kind == "blocked" then
		AudioController.PlayAt("Hit", root.Position)
	end
end

-- Preloads every skill clip on the new character's Animator so the first press plays at once.
local function loadSkillTracks(character: Model)
	for _, track in skillTracks do
		track:Destroy()
	end
	table.clear(skillTracks)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local animator = humanoid and humanoid:WaitForChild("Animator", 10)
	if not animator or not animator:IsA("Animator") or character ~= Players.LocalPlayer.Character then
		return
	end
	for id, skill in Skills.ById do
		if skill.animation and skill.source ~= "Enemy" then
			local track = Animations.Load(animator, skill.animation, Enum.AnimationPriority.Action, false)
			if track then
				skillTracks[id] = track
			end
		end
	end
end

-- Plays the local player's clip for a used skill. A predicted melee swing waits for the clip's
-- `Hit` marker; without a clip it shows at once. Telegraphed swings come from the server's Resolve.
local function onUsed(skillId: string, aim: Vector3)
	local track = skillTracks[skillId]
	local skill = Skills.ById[skillId]
	local swing = function()
		local root = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			VfxController.PredictSwing(skillId, root.Position, aim)
		end
	end
	if not track then
		swing()
		return
	end
	track:Play(CLIP_FADE_IN)
	if skill and predictsSwing(skill) then
		-- The clip's own `Hit` marker wins; a clip without it still swings at the time baked into the
		-- Animation, or at DEFAULT_HIT_TIME when none is baked.
		local fired = false
		local function once()
			if not fired then
				fired = true
				swing()
			end
		end
		local hit = track:GetMarkerReachedSignal(AnimRoles.Markers.Hit):Once(once)
		local animation = Animations.Get(skill.animation or "")
		local baked = animation and animation:GetAttribute("Hit")
		local at = if type(baked) == "number" then baked else DEFAULT_HIT_TIME
		local fallback = task.delay(at + HIT_GRACE, function()
			if not fired then
				log:Throttled(
					"no-hit-" .. skillId,
					30,
					"warn",
					"Animation %s has no Hit marker; swing shown at %.2fs",
					skill.animation or skillId,
					at
				)
				once()
			end
		end)
		track.Stopped:Once(function()
			hit:Disconnect()
			task.cancel(fallback)
		end)
	end
end

function VfxController.Init(deps: { [string]: any })
	UIController = deps.UIController
	AudioController = deps.AudioController
	CombatController = deps.CombatController
end

function VfxController.Start()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "ClientEffects"
	effectsFolder.Parent = workspace
	Particles.Init(effectsFolder)
	Effects.Init(effectsFolder)

	NetClient.Connect("ShowCast", onCast)
	NetClient.Connect("ShowImpact", onImpact)
	NetClient.Connect("ShowDamage", onDamage)
	NetClient.Connect("ShowParry", onParry)
	CombatController.Used:Connect(onUsed)
	CombatController.DrawReady:Connect(function()
		local hand = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild("LeftHand")
		if hand and hand:IsA("BasePart") then
			burst(hand.Position, 0.8, DRAW_READY_COLOR)
		end
	end)
	CombatController.Rejected:Connect(function(skillId: string)
		local track = skillTracks[skillId]
		if track and track.IsPlaying then
			track:Stop(CLIP_FADE_OUT)
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(loadSkillTracks)
	if Players.LocalPlayer.Character then
		task.spawn(loadSkillTracks, Players.LocalPlayer.Character)
	end
	NetClient.Connect("Notify", function(key: string)
		if key == "LevelUp" then
			AudioController.Play("LevelUp")
		end
	end)
end

--[=[ Local swing feedback for the player's own melee, shown before the server confirms. ]=]
function VfxController.PredictSwing(skillId: string, origin: Vector3, aim: Vector3)
	local skill = Skills.ById[skillId]
	if skill and (skill.delivery == "Melee" or skill.delivery == "Cone") and not skill.windup then
		local recipe = SpellEffects[skillId]
		if recipe and recipe.swing then
			recipe.swing(origin, aim, skill.range or 6, skill.angle or 90)
		else
			arc(origin, aim, skill.range or 6, skillColor(skillId))
		end
		AudioController.Play(soundFor(skill))
	end
end

return VfxController
