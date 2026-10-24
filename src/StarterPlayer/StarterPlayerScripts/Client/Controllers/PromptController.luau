--!strict

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Maid = require(ReplicatedStorage.Shared.Maid)

--[=[
	Floating interaction prompts (docs/art/ui-style.md, Floating UI). Every ProximityPrompt is
	switched to the Custom style and drawn with the InteractPrompt BillboardGui beside the object
	it belongs to. Keyboard and gamepad input still go through ProximityPromptService; tapping or
	clicking the card holds the prompt.
]=]
local PromptController = {}

local UIController: any

local player = Players.LocalPlayer
local shown: { [ProximityPrompt]: Maid.Maid } = {}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "\u{25C6}"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(UserInputService:GetStringForKeyCode(prompt.GamepadKeyCode), "^Button", ""))
	end
	return UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
end

local function adorneeOf(prompt: ProximityPrompt): Instance?
	local parent = prompt.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent
	elseif parent and parent:IsA("Model") then
		return parent.PrimaryPart
	end
	return nil
end

local function hide(prompt: ProximityPrompt)
	local maid = shown[prompt]
	if maid then
		maid:Clean()
		shown[prompt] = nil
	end
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		return
	end
	hide(prompt)
	local maid = Maid.new()
	shown[prompt] = maid

	local card = UIController.Clone("InteractPrompt") :: BillboardGui
	local parts = UIController.Bind(card, { "Bind_Button", "Bind_Key", "Bind_Action", "Bind_Object", "Bind_HoldFill" })
	UIController.SetText(parts.Bind_Key, keyText(prompt, inputType))
	UIController.SetText(parts.Bind_Action, prompt.ActionText)
	UIController.SetText(parts.Bind_Object, prompt.ObjectText)
	local adornee = adorneeOf(prompt)
	if adornee then
		card.Adornee = adornee
	end
	card.Parent = player:WaitForChild("PlayerGui")
	maid:Give(card)

	local holdFill = parts.Bind_HoldFill
	local holdTween: Tween? = nil
	maid:Give(prompt.PromptButtonHoldBegan:Connect(function()
		holdTween = TweenService:Create(
			holdFill,
			TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 1) }
		);
		(holdTween :: Tween):Play()
	end))
	maid:Give(prompt.PromptButtonHoldEnded:Connect(function()
		if holdTween then
			holdTween:Cancel()
		end
		holdFill.Size = UDim2.fromScale(1, 0)
	end))

	local button = parts.Bind_Button
	maid:Give(button.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			prompt:InputHoldBegin()
		end
	end))
	maid:Give(button.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			prompt:InputHoldEnd()
		end
	end))
end

local function adopt(instance: Instance)
	if instance:IsA("ProximityPrompt") then
		instance.Style = Enum.ProximityPromptStyle.Custom
	end
end

function PromptController.Init(deps: { [string]: any })
	UIController = deps.UIController
end

function PromptController.Start()
	for _, descendant in workspace:GetDescendants() do
		adopt(descendant)
	end
	workspace.DescendantAdded:Connect(adopt)
	ProximityPromptService.PromptShown:Connect(show)
	ProximityPromptService.PromptHidden:Connect(hide)
end

return PromptController
