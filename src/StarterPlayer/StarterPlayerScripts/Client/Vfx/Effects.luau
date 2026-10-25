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
-- Share of its emitters' rate a charge-up starts at; it climbs to the full rate as the cast ends.
local CHARGE_START_RATE = 0.35
-- Seconds a finished charge-up keeps its live particles before it is removed.
local CHARGE_LINGER = 0.5

--[=[
	Authored effects: templates under `ReplicatedStorage.Vfx`, edited in Studio with VFX Forge and
	played through its emit module (`vendor/ForgeVFX`), worn by projectiles and casting hands as
	continuous layers, plus the hit feedback that needs code: hitstop, a body flash and screen
	effects. Templates hold emitters, sprite-sheet `SurfaceGui`
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

local function template(name: string): BasePart?
	local found = templates:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	log:Warn("Unknown effect %s", name)
	return nil
end

--[=[ Plays the template `name` at `cframe`; the copy removes itself when the effect ends. ]=]
function Effects.Play(name: string, cframe: CFrame): BasePart?
	local source = template(name)
	if not source then
		return nil
	end
	local effect = source:Clone()
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
	Copies the continuous layers of template `name` (emitters, trails, lights, attachments) onto
	`part`, such as a projectile body. A trail names its end attachments with `From` and `To`
	attributes. `Particles.Release` stops the layers and removes the part.
]=]
function Effects.Attach(name: string, part: BasePart)
	local source = template(name)
	if not source then
		return
	end
	for _, child in source:GetChildren() do
		child:Clone().Parent = part
	end
	for _, child in part:GetChildren() do
		if child:IsA("Trail") then
			child.Attachment0 = part:FindFirstChild(tostring(child:GetAttribute("From"))) :: Attachment?
			child.Attachment1 = part:FindFirstChild(tostring(child:GetAttribute("To"))) :: Attachment?
		end
	end
end

--[=[
	Holds template `name` at its `Offset` attribute from `root` (the casting hand) for `duration`
	seconds, its emitters speeding up to their full rate as the cast ends, then releases it.
	Returns the copy; destroying it cancels the charge.
]=]
function Effects.Charge(name: string, root: BasePart, duration: number): Instance?
	local source = template(name)
	if not source then
		return nil
	end
	local effect = source:Clone()
	local offset = effect:GetAttribute("Offset")
	local hold = CFrame.new(if typeof(offset) == "Vector3" then offset else Vector3.zero)
	effect.CFrame = root.CFrame * hold
	effect.Parent = folder
	local rates: { [ParticleEmitter]: number } = {}
	for _, item in effect:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			rates[item] = item.Rate
			item.Rate *= CHARGE_START_RATE
		end
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - started
		if not effect.Parent or not root.Parent or elapsed >= duration then
			connection:Disconnect()
			if effect.Parent then
				Particles.Release(effect, CHARGE_LINGER)
			end
			return
		end
		effect.CFrame = root.CFrame * hold
		local ramp = CHARGE_START_RATE + (1 - CHARGE_START_RATE) * elapsed / duration
		for emitter, rate in rates do
			emitter.Rate = rate * ramp
		end
	end)
	return effect
end

--[=[
	Stretches the beams of template `name` between `from` and `to` (points, or parts to follow) for
	`duration` seconds, narrowing them to nothing as it ends. A beam with a `Jitter` attribute
	re-bends by up to that many studs every frame, like lightning.
]=]
function Effects.Link(name: string, from: Vector3 | BasePart, to: Vector3 | BasePart, duration: number)
	local source = template(name)
	if not source then
		return
	end
	local effect = source:Clone()
	effect.CFrame = CFrame.new(if typeof(from) == "Vector3" then from else from.Position)
	effect.Parent = folder
	local function endpoint(point: Vector3 | BasePart): Attachment
		local attachment = Instance.new("Attachment")
		if typeof(point) == "Vector3" then
			attachment.Parent = effect
			attachment.WorldPosition = point
		else
			attachment.Parent = point
		end
		return attachment
	end
	local start, finish = endpoint(from), endpoint(to)
	local beams: { { beam: Beam, width0: number, width1: number, jitter: number } } = {}
	for _, item in effect:GetDescendants() do
		if item:IsA("Beam") then
			item.Attachment0 = start
			item.Attachment1 = finish
			local jitter = attribute(item, "Jitter", 0)
			table.insert(beams, { beam = item, width0 = item.Width0, width1 = item.Width1, jitter = jitter })
		end
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local alpha = (os.clock() - started) / duration
		if alpha >= 1 or not effect.Parent then
			connection:Disconnect()
			start:Destroy()
			finish:Destroy()
			effect:Destroy()
			return
		end
		-- Full width for the first half, then a quick taper, so short bolts still read.
		local width = math.min(1, (1 - alpha) * 2)
		for _, entry in beams do
			entry.beam.Width0 = entry.width0 * width
			entry.beam.Width1 = entry.width1 * width
			if entry.jitter > 0 then
				entry.beam.CurveSize0 = (math.random() * 2 - 1) * entry.jitter
				entry.beam.CurveSize1 = (math.random() * 2 - 1) * entry.jitter
			end
		end
	end)
end

--[=[
	Plays a screen template for the local player: a `ScreenGui` of sprite-sheet layers, or a
	`ColorCorrectionEffect` that eases back to neutral over its `Lifetime` attribute.
]=]
function Effects.Screen(name: string)
	local source = templates:FindFirstChild(name)
	if source and source:IsA("ScreenGui") then
		local gui = source:Clone()
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		Debris:AddItem(gui, playFlipbook(gui) + 0.05)
	elseif source and source:IsA("ColorCorrectionEffect") then
		local tint = source:Clone()
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
