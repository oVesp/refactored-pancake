--!strict

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Atmosphere = require(ReplicatedStorage.Content.Atmosphere)
local AtmosphereBlend = require(ReplicatedStorage.Shared.AtmosphereBlend)
local DayCycle = require(ReplicatedStorage.Shared.DayCycle)
local Logger = require(ReplicatedStorage.Shared.Logger)

type Mood = Atmosphere.Mood

--[=[
	Sky, light and haze (docs/systems/atmosphere.md). Drives the shared day clock and blends the
	region mood at the camera into the Lighting effects authored in `src/Lighting`. Client-only
	and cosmetic: the server never writes Lighting at runtime.
]=]
local AtmosphereController = {}

local log = Logger.new("Atmosphere")
local WHITE = Color3.new(1, 1, 1)

local current: Mood? = nil

local function blendToward(from: Mood, to: Mood, t: number): Mood
	local out = table.clone(from)
	for key, value in to :: any do
		local now = (from :: any)[key];
		(out :: any)[key] = if typeof(value) == "Color3"
			then AtmosphereBlend.LerpColor(now, value, t)
			else now + (value - now) * t
	end
	return out
end

local function effect(className: string): Instance?
	local found = Lighting:FindFirstChildOfClass(className)
	if not found then
		log:Throttled("missing-" .. className, 60, "warn", "Lighting has no %s; check src/Lighting", className)
	end
	return found
end

local function clouds(): Clouds
	local terrain = workspace.Terrain
	local existing = terrain:FindFirstChildOfClass("Clouds")
	if existing then
		return existing
	end
	local created = Instance.new("Clouds")
	created.Parent = terrain
	return created
end

local function apply(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local target = AtmosphereBlend.Mix(AtmosphereBlend.Weights(camera.CFrame.Position))
	current = if current then blendToward(current, target, 1 - math.exp(-Atmosphere.Smoothing * dt)) else target
	local clock = DayCycle.Now()
	local light = AtmosphereBlend.LightAt(clock)
	local mood = AtmosphereBlend.Lit(current :: Mood, light)

	Lighting.ClockTime = clock
	Lighting.Brightness = light.brightness
	Lighting.ExposureCompensation = light.exposure
	Lighting.Ambient = light.ambient
	Lighting.OutdoorAmbient = light.outdoorAmbient
	Lighting.ColorShift_Top = light.shiftTop

	local air = effect("Atmosphere") :: Atmosphere?
	if air then
		air.Density = mood.density
		air.Offset = mood.offset
		air.Haze = mood.haze
		air.Glare = mood.glare
		air.Color = mood.color
		air.Decay = mood.decay
	end
	local grade = effect("ColorCorrectionEffect") :: ColorCorrectionEffect?
	if grade then
		grade.Saturation = mood.saturation
		grade.Contrast = mood.contrast
		grade.TintColor = mood.tint
	end
	local bloom = effect("BloomEffect") :: BloomEffect?
	if bloom then
		bloom.Intensity = light.bloom
	end
	local rays = effect("SunRaysEffect") :: SunRaysEffect?
	if rays then
		rays.Intensity = light.sunRays
	end
	local sky = clouds()
	sky.Cover = mood.cloudCover
	sky.Density = mood.cloudDensity
	sky.Color = AtmosphereBlend.LerpColor(light.skyLight, WHITE, 0.4)
end

function AtmosphereController.Init(_deps: { [string]: any }) end

function AtmosphereController.Start()
	local interval = 1 / Atmosphere.UpdateHz
	local elapsed = interval
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < interval then
			return
		end
		apply(elapsed)
		elapsed = 0
	end)
end

return AtmosphereController
