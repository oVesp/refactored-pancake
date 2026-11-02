--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Maid = require(ReplicatedStorage.Shared.Maid)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)

-- Pixels the pointer must travel before a press becomes a drag (a shorter press stays a click).
local DRAG_THRESHOLD = 6

export type Entry = {
	kind: "Skill" | "Discipline",
	id: string,
}

--[=[
	Drags spellbook entries and hotbar slots onto the hotbar. The ghost lives in the DragLayer screen and
	drops are tested against the hotbar slots' screen rects, so a drag can start in a screen window
	or in a world-space panel (docs/art/ui-style.md, Floating UI). Drops send `SetHotbarSlot`; the
	server checks the entry is known.
]=]
local DragController = {}

local UIController: any

local ghost: GuiObject
local ghostName: TextLabel
local layer: ScreenGui
local targets: { [number]: GuiObject } = {}
local dragMaid = Maid.new()

--[=[ Sets the hotbar slot frames that accept drops, by slot index. ]=]
function DragController.SetTargets(frames: { [number]: GuiObject })
	targets = frames
end

local function slotAt(point: Vector2): number?
	for index, frame in targets do
		local corner = frame.AbsolutePosition
		local size = frame.AbsoluteSize
		if
			frame.Visible
			and point.X >= corner.X
			and point.Y >= corner.Y
			and point.X <= corner.X + size.X
			and point.Y <= corner.Y + size.Y
		then
			return index
		end
	end
	return nil
end

local function moveGhost(point: Vector2)
	local origin = layer.AbsolutePosition
	ghost.Position = UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
end

--[=[ Cancels a drag in progress without dropping. ]=]
function DragController.Cancel()
	dragMaid:Clean()
	ghost.Visible = false
end

--[=[
	Starts tracking a press on a draggable entry. `input` is the press (mouse button 1 or touch).
	Dropping on a hotbar slot puts the entry there; dragging a hotbar slot (`from`) off the bar
	clears it.
]=]
function DragController.Begin(input: InputObject, entry: Entry, label: string, from: number?)
	local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
	if not isMouse and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	DragController.Cancel()
	local start: Vector2? = nil
	local moved = false
	local last = Vector2.zero

	local function follows(changed: InputObject): boolean
		if isMouse then
			return changed.UserInputType == Enum.UserInputType.MouseMovement
		end
		return changed == input or changed.UserInputType == Enum.UserInputType.Touch
	end

	dragMaid:Give(UserInputService.InputChanged:Connect(function(changed: InputObject)
		if not follows(changed) then
			return
		end
		last = Vector2.new(changed.Position.X, changed.Position.Y)
		start = start or last
		if not moved and (last - (start :: Vector2)).Magnitude >= DRAG_THRESHOLD then
			moved = true
			ghostName.Text = label
			ghost.Visible = true
		end
		if moved then
			moveGhost(last)
		end
	end))
	dragMaid:Give(UserInputService.InputEnded:Connect(function(ended: InputObject)
		local released = if isMouse
			then ended.UserInputType == Enum.UserInputType.MouseButton1
			else ended == input or ended.UserInputType == Enum.UserInputType.Touch
		if not released then
			return
		end
		local wasMoved = moved
		DragController.Cancel()
		if not wasMoved then
			return
		end
		local index = slotAt(last)
		if index then
			NetClient.Fire("SetHotbarSlot", index, entry.kind, entry.id)
		elseif from then
			NetClient.Fire("SetHotbarSlot", from, "", "")
		end
	end))
end

function DragController.Init(deps: { [string]: any })
	UIController = deps.UIController
end

function DragController.Start()
	layer = UIController.GetScreen("DragLayer")
	local bound = UIController.Bind(layer, { "Bind_DragGhost", "Bind_DragGhostName" })
	ghost = bound.Bind_DragGhost
	ghostName = bound.Bind_DragGhostName :: TextLabel
	ghost.Visible = false
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "Spellbook" and not isOpen then
			DragController.Cancel()
		end
	end)
end

return DragController
