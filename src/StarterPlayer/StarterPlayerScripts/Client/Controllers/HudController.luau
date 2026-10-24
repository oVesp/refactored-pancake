--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Maid = require(ReplicatedStorage.Shared.Maid)

local Attributes = Constants.Attributes

type UIControllerModule = {
	GetScreen: (name: string) -> ScreenGui,
	Bind: (screen: ScreenGui, names: { string }) -> { [string]: GuiObject },
}

--[=[
	View model for the HUD screen: reads replicated character attributes and never writes
	authoritative state (game-design.md 6.2).
]=]
local HudController = {}

local uiController: UIControllerModule
local characterMaid = Maid.new()

local hpFill: GuiObject
local hpText: TextLabel

local function render(character: Model)
	local hp = character:GetAttribute(Attributes.Hp)
	local maxHp = character:GetAttribute(Attributes.MaxHp)
	if type(hp) ~= "number" or type(maxHp) ~= "number" or maxHp <= 0 then
		return
	end

	hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
	hpText.Text = string.format("%d / %d", math.ceil(hp), math.ceil(maxHp))
end

local function watchCharacter(character: Model)
	characterMaid:Clean()
	characterMaid:Give(character:GetAttributeChangedSignal(Attributes.Hp):Connect(function()
		render(character)
	end))
	characterMaid:Give(character:GetAttributeChangedSignal(Attributes.MaxHp):Connect(function()
		render(character)
	end))
	render(character)
end

function HudController.Init(deps: { [string]: any })
	uiController = deps.UIController
end

function HudController.Start()
	local screen = uiController.GetScreen("Hud")
	local bound = uiController.Bind(screen, { "Bind_HpFill", "Bind_HpText" })
	hpFill = bound.Bind_HpFill
	assert(bound.Bind_HpText:IsA("TextLabel"), "Bind_HpText must be a TextLabel")
	hpText = bound.Bind_HpText

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return HudController
