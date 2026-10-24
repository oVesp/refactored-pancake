--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Signal = require(ReplicatedStorage.Shared.Signal)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local templates = ReplicatedStorage:WaitForChild("UiTemplates", Constants.ClientWaitTimeout) :: Folder

--[=[
	Owns Studio-authored screens and templates (game-design.md 6.2). Opens one modal at a time,
	wires close buttons and gamepad focus. Nothing builds UI in code: rows are template clones.
]=]
local UIController = {}

--[=[ Fires `(screenName, isOpen)` when a modal opens or closes. ]=]
UIController.ModalChanged = Signal.new() :: Signal.Signal<string, boolean>

local openModal: ScreenGui? = nil

--[=[ Returns a screen from PlayerGui, waiting for it to replicate. Errors if it never appears. ]=]
function UIController.GetScreen(name: string): ScreenGui
	local screen = playerGui:WaitForChild(name, Constants.ClientWaitTimeout)
	assert(screen and screen:IsA("ScreenGui"), `Screen {name} is missing from StarterGui`)
	return screen
end

--[=[
	Finds every named binding (`Bind_` prefix) under a root. Errors loudly listing all missing
	names, so a renamed instance in Studio breaks at startup rather than at runtime.
]=]
function UIController.Bind(root: Instance, names: { string }): { [string]: GuiObject }
	local found: { [string]: GuiObject } = {}
	local missing: { string } = {}
	for _, name in names do
		assert(string.sub(name, 1, 5) == "Bind_", `Binding {name} must use the Bind_ prefix`)
		local instance = root:FindFirstChild(name, true)
		if instance and instance:IsA("GuiObject") then
			found[name] = instance
		else
			table.insert(missing, name)
		end
	end
	assert(#missing == 0, `{root.Name} is missing bindings: {table.concat(missing, ", ")}`)
	return found
end

--[=[ Clones a template from ReplicatedStorage.UiTemplates. Errors if it does not exist. ]=]
function UIController.Clone(name: string): Instance
	local template = templates:FindFirstChild(name)
	assert(template, `UI template {name} is missing`)
	return template:Clone()
end

--[=[ Sets the text of a bound TextLabel or TextButton. Errors on any other class. ]=]
function UIController.SetText(target: GuiObject, text: string)
	assert(target:IsA("TextLabel") or target:IsA("TextButton"), `{target:GetFullName()} has no text`)
	local label = target :: TextLabel
	label.Text = text
end

--[=[ Destroys every GuiObject child of a container (keeps layouts and padding). ]=]
function UIController.ClearRows(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function firstButton(root: Instance): GuiObject?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiButton") and descendant.Visible then
			return descendant
		end
	end
	return nil
end

--[=[ Opens a modal screen, closing any other modal first. ]=]
function UIController.Open(name: string)
	local screen = UIController.GetScreen(name)
	if openModal and openModal ~= screen then
		UIController.Close(openModal.Name)
	end
	screen.Enabled = true
	openModal = screen
	if GuiService:IsTenFootInterface() or GuiService.SelectedObject ~= nil then
		GuiService.SelectedObject = firstButton(screen)
	end
	UIController.ModalChanged:Fire(name, true)
end

--[=[ Closes a modal screen if open. ]=]
function UIController.Close(name: string)
	local screen = UIController.GetScreen(name)
	if not screen.Enabled then
		return
	end
	screen.Enabled = false
	if openModal == screen then
		openModal = nil
		GuiService.SelectedObject = nil
	end
	UIController.ModalChanged:Fire(name, false)
end

--[=[ Toggles a modal screen. ]=]
function UIController.Toggle(name: string)
	if UIController.GetScreen(name).Enabled then
		UIController.Close(name)
	else
		UIController.Open(name)
	end
end

--[=[ Closes whichever modal is open. Returns true if one was. ]=]
function UIController.CloseTop(): boolean
	if openModal then
		UIController.Close(openModal.Name)
		return true
	end
	return false
end

--[=[ Wires a modal's `Bind_Close` button. ]=]
function UIController.BindClose(name: string)
	local screen = UIController.GetScreen(name)
	local close = UIController.Bind(screen, { "Bind_Close" }).Bind_Close
	assert(close:IsA("GuiButton"), `{name}.Bind_Close must be a button`)
	close.Activated:Connect(function()
		UIController.Close(name)
	end)
end

function UIController.Init(_deps: { [string]: any }) end

function UIController.Start() end

return UIController
