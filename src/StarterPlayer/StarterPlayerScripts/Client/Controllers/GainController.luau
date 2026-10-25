--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Theme = require(ReplicatedStorage.Shared.Theme)

local RISE = Vector3.new(0, 1.2, 0)
local LIFETIME = 1.8
local STACK_STEP = 0.8
local MAX_STACK = 5

--[=[
	Floating gains (docs/art/ui-style.md, Floating UI): XP and looted items rise over the
	player's character as FloatingGain BillboardGuis instead of screen toasts. Gains that land
	together stack upwards.
]=]
local GainController = {}

local UIController: any

local player = Players.LocalPlayer
local inFlight = 0

local function show(kind: string, label: string, amount: number)
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head or not head:IsA("BasePart") or inFlight >= MAX_STACK then
		return
	end
	local gui = UIController.Clone("FloatingGain") :: BillboardGui
	local parts = UIController.Bind(gui, { "Bind_Text", "Bind_Gem" })
	local text = parts.Bind_Text :: TextLabel
	local color = if kind == "Xp" then Theme.Xp else Theme.GoldBright
	text.Text = if kind == "Xp" then string.format("+%d %s", amount, label) else string.format("%s ×%d", label, amount)
	text.TextColor3 = color
	parts.Bind_Gem.BackgroundColor3 = color

	local start = gui.StudsOffset + Vector3.new(0, inFlight * STACK_STEP, 0)
	gui.StudsOffset = start
	gui.Adornee = head
	gui.Parent = player:WaitForChild("PlayerGui")
	inFlight += 1

	TweenService:Create(gui, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = start + RISE,
	}):Play()
	local fade = TweenInfo.new(LIFETIME / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, LIFETIME / 2)
	TweenService:Create(text, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(parts.Bind_Gem, fade, { BackgroundTransparency = 1 }):Play()
	task.delay(LIFETIME, function()
		inFlight -= 1
		gui:Destroy()
	end)
end

function GainController.Init(deps: { [string]: any })
	UIController = deps.UIController
end

function GainController.Start()
	NetClient.Connect("ShowGain", function(kind: string, label: string, amount: number)
		show(kind, label, amount)
	end)
end

return GainController
