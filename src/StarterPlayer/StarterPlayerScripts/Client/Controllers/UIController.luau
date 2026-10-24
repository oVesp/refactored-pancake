--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

--[=[
	Owns Studio-authored screens (game-design.md 6.2). Controllers get screens and their bound
	children from here; nothing builds UI in code.
]=]
local UIController = {}

--[=[
	Returns a screen from PlayerGui, waiting for it to replicate. Errors if it never appears.
]=]
function UIController.GetScreen(name: string): ScreenGui
	local screen = playerGui:WaitForChild(name, Constants.ClientWaitTimeout)
	assert(screen and screen:IsA("ScreenGui"), `Screen {name} is missing from StarterGui`)
	return screen
end

--[=[
	Finds every named binding (`Bind_` prefix) under a screen. Errors loudly listing all missing
	names, so a renamed instance in Studio breaks at startup rather than at runtime.
]=]
function UIController.Bind(screen: ScreenGui, names: { string }): { [string]: GuiObject }
	local found: { [string]: GuiObject } = {}
	local missing: { string } = {}

	for _, name in names do
		assert(string.sub(name, 1, 5) == "Bind_", `Binding {name} must use the Bind_ prefix`)
		local instance = screen:FindFirstChild(name, true)
		if instance and instance:IsA("GuiObject") then
			found[name] = instance
		else
			table.insert(missing, name)
		end
	end

	assert(#missing == 0, `Screen {screen.Name} is missing bindings: {table.concat(missing, ", ")}`)
	return found
end

function UIController.Init(_deps: { [string]: any }) end

function UIController.Start() end

return UIController
