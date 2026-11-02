--!strict

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Content.Assets)

export type EmitterSpec = {
	texture: string,
	color: ColorSequence,
	size: NumberSequence,
	lifetime: NumberRange,
	transparency: NumberSequence?,
	speed: NumberRange?,
	spread: Vector2?,
	rotation: NumberRange?,
	rotSpeed: NumberRange?,
	emission: number?,
	brightness: number?,
	rate: number?,
	count: number?,
	drag: number?,
	acceleration: Vector3?,
	orientation: Enum.ParticleOrientation?,
	direction: Enum.NormalId?,
	shape: Enum.ParticleEmitterShape?,
	shapeStyle: Enum.ParticleEmitterShapeStyle?,
	shapeInOut: Enum.ParticleEmitterShapeInOut?,
	locked: boolean?,
	zOffset: number?,
}

export type TrailSpec = {
	color: ColorSequence,
	lifetime: number,
	width: number,
	transparency: NumberSequence?,
	texture: string?,
	emission: number?,
}

--[=[
	Building blocks for spell visuals: textured particle emitters, trails and lights on invisible
	anchors. Every visible shape comes from a texture, never from part geometry. Client-only and
	cosmetic.
]=]
local Particles = {}

local folder: Folder

--[=[ Sets the workspace folder that holds every effect instance. Call once before use. ]=]
function Particles.Init(effectsFolder: Folder)
	folder = effectsFolder
end

--[=[ Content id for an `Assets.Textures` key: the uploaded id, else the built-in fallback. ]=]
function Particles.Texture(key: string): string
	local asset = Assets.Textures[key]
	assert(asset, `Unknown texture {key}`)
	return asset.id or asset.fallback
end

--[=[ Evenly spaced NumberSequence from two to twenty values. ]=]
function Particles.Numbers(...: number): NumberSequence
	local values = { ... }
	if #values == 1 then
		return NumberSequence.new(values[1])
	end
	local points = {}
	for i, value in values do
		table.insert(points, NumberSequenceKeypoint.new((i - 1) / (#values - 1), value))
	end
	return NumberSequence.new(points)
end

--[=[ Evenly spaced ColorSequence from one to twenty colors. ]=]
function Particles.Colors(...: Color3): ColorSequence
	local values = { ... }
	if #values == 1 then
		return ColorSequence.new(values[1])
	end
	local points = {}
	for i, value in values do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#values - 1), value))
	end
	return ColorSequence.new(points)
end

--[=[ Ground point below a position, ignoring effects and the local character. ]=]
function Particles.Ground(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, Players.LocalPlayer.Character :: Instance }
	local result = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return if result then result.Position else position
end

--[=[ Invisible, non-colliding anchor part for emitters, trails and lights. ]=]
function Particles.Anchor(cframe: CFrame, size: Vector3?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.one * 0.2
	part.CFrame = cframe
	part.Parent = folder
	return part
end

--[=[ Adds one emitter to a part or attachment; emits `spec.count` at once if set. ]=]
function Particles.Emitter(parent: Instance, spec: EmitterSpec): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Particles.Texture(spec.texture)
	emitter.Color = spec.color
	emitter.Size = spec.size
	emitter.Lifetime = spec.lifetime
	emitter.Transparency = spec.transparency or Particles.Numbers(0, 1)
	emitter.Speed = spec.speed or NumberRange.new(0)
	emitter.SpreadAngle = spec.spread or Vector2.zero
	emitter.Rotation = spec.rotation or NumberRange.new(0, 360)
	emitter.RotSpeed = spec.rotSpeed or NumberRange.new(0)
	emitter.LightEmission = spec.emission or 1
	emitter.Brightness = spec.brightness or 1
	emitter.Rate = spec.rate or 0
	emitter.Drag = spec.drag or 0
	emitter.Acceleration = spec.acceleration or Vector3.zero
	emitter.Orientation = spec.orientation or Enum.ParticleOrientation.FacingCamera
	emitter.EmissionDirection = spec.direction or Enum.NormalId.Top
	emitter.Shape = spec.shape or Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = spec.shapeStyle or Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = spec.shapeInOut or Enum.ParticleEmitterShapeInOut.Outward
	emitter.LockedToPart = spec.locked == true
	emitter.ZOffset = spec.zOffset or 0
	emitter.Parent = parent
	if spec.count then
		emitter:Emit(spec.count)
	end
	return emitter
end

--[=[ Adds every spec to a part; returns the longest particle lifetime. ]=]
function Particles.Attach(parent: Instance, specs: { EmitterSpec }): number
	local longest = 0
	for _, spec in specs do
		Particles.Emitter(parent, spec)
		longest = math.max(longest, spec.lifetime.Max)
	end
	return longest
end

--[=[ Ribbon trail between two attachments on a part, spread along its up axis. ]=]
function Particles.Trail(part: BasePart, spec: TrailSpec): Trail
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, spec.width / 2, 0)
	top.Parent = part
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -spec.width / 2, 0)
	bottom.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = spec.color
	trail.Transparency = spec.transparency or Particles.Numbers(0.2, 1)
	trail.Lifetime = spec.lifetime
	trail.LightEmission = spec.emission or 1
	trail.FaceCamera = true
	if spec.texture then
		trail.Texture = Particles.Texture(spec.texture)
		trail.TextureMode = Enum.TextureMode.Stretch
	end
	trail.Parent = part
	return trail
end

--[=[ Point light on a part; fades to dark over `fade` seconds when given. ]=]
function Particles.Light(part: BasePart, color: Color3, range: number, brightness: number, fade: number?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
	if fade then
		TweenService:Create(light, TweenInfo.new(fade, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	end
	return light
end

--[=[ Short light flash at a position. ]=]
function Particles.Flash(position: Vector3, color: Color3, range: number, duration: number)
	local anchor = Particles.Anchor(CFrame.new(position))
	Particles.Light(anchor, color, range, 3, duration)
	Debris:AddItem(anchor, duration + 0.1)
end

--[=[ Stops a part's emitters and trails, lets live particles finish, then removes it. ]=]
function Particles.Release(part: BasePart, linger: number)
	for _, child in part:GetDescendants() do
		if child:IsA("ParticleEmitter") or child:IsA("Trail") then
			(child :: any).Enabled = false
		elseif child:IsA("PointLight") then
			TweenService:Create(child, TweenInfo.new(math.min(linger, 0.3)), { Brightness = 0 }):Play()
		end
	end
	Debris:AddItem(part, linger)
end

--[=[ Keeps an anchor at `offset` from a moving part for `duration` seconds, then releases it. ]=]
function Particles.Follow(anchor: BasePart, target: BasePart, offset: CFrame, duration: number, linger: number)
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if not anchor.Parent or not target.Parent or elapsed >= duration then
			connection:Disconnect()
			if anchor.Parent then
				Particles.Release(anchor, linger)
			end
			return
		end
		anchor.CFrame = target.CFrame * offset
	end)
	anchor.CFrame = target.CFrame * offset
end

--[=[ Slides an anchor from `from` to `to` over `duration` seconds (ease out), then releases it. ]=]
function Particles.Travel(anchor: BasePart, from: Vector3, to: Vector3, duration: number, linger: number)
	local look = if (to - from).Magnitude > 1e-3 then CFrame.lookAt(from, to) else CFrame.new(from)
	local elapsed = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local alpha = math.min(elapsed / duration, 1)
		local eased = 1 - (1 - alpha) ^ 2
		anchor.CFrame = look.Rotation + from:Lerp(to, eased)
		if alpha >= 1 or not anchor.Parent then
			connection:Disconnect()
			if anchor.Parent then
				Particles.Release(anchor, linger)
			end
		end
	end)
	anchor.CFrame = look
end

return Particles
