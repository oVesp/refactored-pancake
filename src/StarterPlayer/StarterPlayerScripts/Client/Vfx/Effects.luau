--!strict

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Logger = require(ReplicatedStorage.Shared.Logger)

local Particles = require(script.Parent.Particles)

local log = Logger.new("Effects")

-- Upper bound on an effect's life, in case the emit promise never settles.
local MAX_LIFETIME = 4

--[=[
	Authored effects: templates under `ReplicatedStorage.Vfx`, edited in Studio with VFX Forge and
	played through its emit module (`vendor/ForgeVFX`), plus the hit feedback that needs code:
	hitstop, a body flash and screen effects. Templates hold emitters, sprite-sheet `SurfaceGui`
	layers for shapes that lie level in the world, and flash lights; emitters and image labels name
	their texture with a `TextureKey` attribute (an `Assets.Textures` key) so asset ids stay in the
	manifest. Client-only and cosmetic.
]=]
local Effects = {}

local forge: any
local templates: Folder
local folder: Folder

--[=[ Resolves template textures and starts the emit module. Call once before `Play`. ]=]
function Effects.Init(effectsFolder: Folder)
	folder = effectsFolder
	templates = ReplicatedStorage:WaitForChild("Vfx") :: Folder
	for _, item in templates:GetDescendants() do
		local key = item:GetAttribute("TextureKey")
		if typeof(key) ~= "string" then
			continue
		end
		if item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then
			(item :: any).Texture = Particles.Texture(key)
		elseif item:IsA("ImageLabel") then
			item.Image = Particles.Texture(key)
		end
	end
	forge = require(ReplicatedStorage:WaitForChild("ForgeVFX") :: ModuleScript) :: any
	forge.init()
end

local function attribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

-- Steps a gui's sprite-sheet labels through their frames once over its `Lifetime`, after its
-- `Delay`: labels grow by `Grow`, spin by `Spin` degrees, blend to their `ColorTo` tint and fade
-- out over the last `Fade` share of the life. A `FlipbookGrid` of 1 holds a single image.
-- Returns the seconds until the gui is done.
local function playFlipbook(gui: LayerCollector): number
	local grid = attribute(gui, "FlipbookGrid", 1)
	local pixels = attribute(gui, "FramePixels", 0)
	local lifetime = attribute(gui, "Lifetime", 0.3)
	local delay = attribute(gui, "Delay", 0)
	local grow = attribute(gui, "Grow", 1)
	local spin = attribute(gui, "Spin", 0)
	local fade = attribute(gui, "Fade", 0)
	local layers = {}
	for _, label in gui:GetChildren() do
		if label:IsA("ImageLabel") then
			table.insert(layers, {
				label = label,
				scale = label.Size.X.Scale,
				rotation = label.Rotation,
				transparency = label.ImageTransparency,
				from = label.ImageColor3,
				to = label:GetAttribute("ColorTo"),
			})
		end
	end
	local frames = grid * grid
	local start = os.clock() + delay
	gui.Enabled = delay <= 0
	local connection: RBXScriptConnection
	local function step()
		local elapsed = os.clock() - start
		if elapsed < 0 then
			return
		end
		gui.Enabled = true
		local alpha = math.min(elapsed / lifetime, 1)
		local frame = math.min(math.floor(alpha * frames), frames - 1)
		local offset = Vector2.new(frame % grid, frame // grid) * pixels
		local size = 1 + (grow - 1) * alpha
		local fading = if fade > 0 then math.clamp((alpha - (1 - fade)) / fade, 0, 1) else 0
		for _, layer in layers do
			if grid > 1 then
				layer.label.ImageRectOffset = offset
			end
			layer.label.Size = UDim2.fromScale(layer.scale * size, layer.scale * size)
			layer.label.Rotation = layer.rotation + spin * alpha
			layer.label.ImageTransparency = layer.transparency + (1 - layer.transparency) * fading
			if typeof(layer.to) == "Color3" then
				layer.label.ImageColor3 = layer.from:Lerp(layer.to, alpha)
			end
		end
		if alpha >= 1 then
			connection:Disconnect()
			gui.Enabled = false
		end
	end
	connection = RunService.RenderStepped:Connect(step)
	step()
	return delay + lifetime
end

-- Lights a template light at full brightness and dims it to nothing over its `FlashTime`.
local function flashLight(light: Light): number
	local duration = attribute(light, "FlashTime", 0.2)
	TweenService:Create(light, TweenInfo.new(duration, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
	return duration
end

-- Starts the effect's surfaces and lights; returns how long they need to finish.
local function animate(effect: Instance): number
	local busy = 0
	for _, item in effect:GetDescendants() do
		if item:IsA("LayerCollector") and item:GetAttribute("Lifetime") then
			busy = math.max(busy, playFlipbook(item))
		elseif item:IsA("Light") and item:GetAttribute("FlashTime") then
			busy = math.max(busy, flashLight(item))
		end
	end
	return busy
end

--[=[ Plays the template `name` at `cframe`; the copy removes itself when the effect ends. ]=]
function Effects.Play(name: string, cframe: CFrame): BasePart?
	local template = templates:FindFirstChild(name)
	if not template or not template:IsA("BasePart") then
		log:Warn("Unknown effect %s", name)
		return nil
	end
	local effect = template:Clone()
	effect.CFrame = cframe
	effect.Parent = folder
	local started = os.clock()
	local busy = animate(effect)
	forge.emit(effect).Finished:finally(function()
		task.delay(math.max(0, busy - (os.clock() - started)), effect.Destroy, effect)
	end)
	Debris:AddItem(effect, MAX_LIFETIME)
	return effect
end

--[=[
	Plays a screen template for the local player: a `ScreenGui` of sprite-sheet layers, or a
	`ColorCorrectionEffect` that eases back to neutral over its `Lifetime` attribute.
]=]
function Effects.Screen(name: string)
	local template = templates:FindFirstChild(name)
	if template and template:IsA("ScreenGui") then
		local gui = template:Clone()
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		Debris:AddItem(gui, playFlipbook(gui) + 0.05)
	elseif template and template:IsA("ColorCorrectionEffect") then
		local tint = template:Clone()
		tint.Parent = Lighting
		local duration = attribute(tint, "Lifetime", 0.25)
		TweenService:Create(tint, TweenInfo.new(duration, Enum.EasingStyle.Quad), {
			TintColor = Color3.new(1, 1, 1),
			Brightness = 0,
			Contrast = 0,
			Saturation = 0,
		}):Play()
		Debris:AddItem(tint, duration + 0.05)
	else
		log:Warn("Unknown screen effect %s", name)
	end
end

--[=[ Freezes every playing animation on the models for `duration` seconds (hit pause). ]=]
function Effects.Hitstop(models: { Model? }, duration: number)
	for _, model in models do
		local animator = model and model:FindFirstChildWhichIsA("Animator", true)
		if not animator then
			continue
		end
		for _, track in (animator :: Animator):GetPlayingAnimationTracks() do
			local speed = track.Speed
			track:AdjustSpeed(0)
			task.delay(duration, function()
				if track.IsPlaying then
					track:AdjustSpeed(speed)
				end
			end)
		end
	end
end

--[=[ Washes a model in a solid colour that fades out over `duration` seconds. ]=]
function Effects.BodyFlash(model: Model, color: Color3, duration: number)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.FillTransparency = 0.1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = folder
	TweenService:Create(highlight, TweenInfo.new(duration, Enum.EasingStyle.Quad), { FillTransparency = 1 }):Play()
	Debris:AddItem(highlight, duration + 0.05)
end

return Effects
