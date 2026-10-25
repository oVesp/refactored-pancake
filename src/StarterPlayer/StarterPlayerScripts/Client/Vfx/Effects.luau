--!strict

local Debris = game:GetService("Debris")
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
	hitstop and a body flash. Templates hold emitters and sprite-sheet SurfaceGui layers; both name
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

-- Steps a template SurfaceGui's sprite-sheet labels through their frames once over its `Lifetime`,
-- growing them by `Grow` and blending a label's `ColorTo` tint.
local function playFlipbook(gui: SurfaceGui)
	local grid = gui:GetAttribute("FlipbookGrid") :: number
	local pixels = gui:GetAttribute("FramePixels") :: number
	local lifetime = gui:GetAttribute("Lifetime") :: number
	local grow = (gui:GetAttribute("Grow") or 1) :: number
	local layers = {}
	for _, label in gui:GetChildren() do
		if label:IsA("ImageLabel") then
			table.insert(layers, {
				label = label,
				scale = label.Size.X.Scale,
				from = label.ImageColor3,
				to = label:GetAttribute("ColorTo"),
			})
		end
	end
	local frames = grid * grid
	local start = os.clock()
	local connection: RBXScriptConnection
	local function step()
		local alpha = math.min((os.clock() - start) / lifetime, 1)
		local frame = math.min(math.floor(alpha * frames), frames - 1)
		local offset = Vector2.new(frame % grid, frame // grid) * pixels
		local size = 1 + (grow - 1) * alpha
		for _, layer in layers do
			layer.label.ImageRectOffset = offset
			layer.label.Size = UDim2.fromScale(layer.scale * size, layer.scale * size)
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
	for _, gui in effect:GetDescendants() do
		if gui:IsA("SurfaceGui") and gui:GetAttribute("FlipbookGrid") then
			playFlipbook(gui)
		end
	end
	forge.emit(effect).Finished:finally(function()
		effect:Destroy()
	end)
	Debris:AddItem(effect, MAX_LIFETIME)
	return effect
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
