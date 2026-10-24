--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Content.Items)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)

--[=[
	Inventory screen: item grid, equipment line and an inspector with the Capacity bar
	(Imprints are not editable in M0.5). Equip/use/unequip go to the server.
]=]
local InventoryController = {}

local UIController: any
local ProfileController: any

local bound: { [string]: GuiObject }
local selectedUid: number? = nil

local function equippedSlot(snapshot: { [string]: any }, uid: number): string?
	for slot, equipped in snapshot.equipment do
		if equipped == uid then
			return slot
		end
	end
	return nil
end

local function modifierText(modifiers: { [string]: number }?): string
	if not modifiers then
		return ""
	end
	local parts = {}
	for name, value in modifiers do
		table.insert(
			parts,
			if math.abs(value) < 1
				then string.format("%s %+d%%", name, value * 100)
				else string.format("%s %+d", name, value)
		)
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function renderInspector(snapshot: { [string]: any })
	local stack
	for _, entry in snapshot.inventory do
		if entry.uid == selectedUid then
			stack = entry
		end
	end
	local nameLabel = bound.Bind_ItemName :: TextLabel
	local info = bound.Bind_ItemInfo :: TextLabel
	local primary = bound.Bind_Primary :: TextButton
	local def = stack and Items.ById[stack.id]
	if not stack or not def then
		nameLabel.Text = "Select an item"
		info.Text = ""
		primary.Visible = false
		bound.Bind_CapacityFill.Size = UDim2.fromScale(0, 1)
		UIController.SetText(bound.Bind_CapacityText, "")
		return
	end
	nameLabel.Text = def.name
	info.Text = string.format(
		"Grade %s %s\n%s\n%s",
		string.rep("I", def.grade),
		def.kind,
		def.description,
		modifierText(def.modifiers)
	)
	bound.Bind_CapacityFill.Size = UDim2.fromScale(0, 1)
	UIController.SetText(
		bound.Bind_CapacityText,
		if def.capacity > 0 then string.format("0 / %d used · no Imprints", def.capacity) else "No Capacity"
	)
	primary.Visible = def.kind ~= "Material"
	local slot = equippedSlot(snapshot, stack.uid)
	primary.Text = if def.kind == "Consumable" then "Use" elseif slot then "Unequip" else "Equip"
end

local function render(snapshot: { [string]: any }?)
	if not snapshot then
		return
	end
	UIController.ClearRows(bound.Bind_Grid)
	for index, stack in snapshot.inventory do
		local def = Items.ById[stack.id]
		local slot = UIController.Clone("ItemSlot") :: TextButton
		slot.LayoutOrder = index
		local parts = UIController.Bind(slot, { "Bind_Name", "Bind_Count", "Bind_Equipped" })
		UIController.SetText(parts.Bind_Name, if def then def.name else stack.id)
		UIController.SetText(parts.Bind_Count, if stack.count > 1 then tostring(stack.count) else "")
		parts.Bind_Equipped.Visible = equippedSlot(snapshot, stack.uid) ~= nil
		slot.Activated:Connect(function()
			selectedUid = stack.uid
			renderInspector(snapshot)
		end)
		slot.Parent = bound.Bind_Grid
	end

	local equipment = {}
	for slotName in Items.Slots do
		local uid = snapshot.equipment[slotName]
		local label = "empty"
		for _, stack in snapshot.inventory do
			if stack.uid == uid then
				label = Items.ById[stack.id].name
			end
		end
		table.insert(equipment, string.format("%s: %s", tostring(slotName), label))
	end
	table.sort(equipment)
	UIController.SetText(
		bound.Bind_Equipment,
		string.format("%s\n%d / %d slots", table.concat(equipment, " · "), #snapshot.inventory, Items.InventorySize)
	)
	renderInspector(snapshot)
end

function InventoryController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
end

function InventoryController.Start()
	local screen = UIController.GetScreen("Inventory")
	bound = UIController.Bind(screen, {
		"Bind_Equipment",
		"Bind_Grid",
		"Bind_ItemName",
		"Bind_ItemInfo",
		"Bind_CapacityFill",
		"Bind_CapacityText",
		"Bind_Primary",
		"Bind_Close",
	})
	UIController.BindClose("Inventory")

	local primaryButton = bound.Bind_Primary :: TextButton
	primaryButton.Activated:Connect(function()
		local snapshot = ProfileController.Get()
		if not snapshot or not selectedUid then
			return
		end
		for _, stack in snapshot.inventory do
			if stack.uid == selectedUid then
				local def = Items.ById[stack.id]
				local slot = equippedSlot(snapshot, stack.uid)
				if def.kind == "Consumable" then
					NetClient.Fire("UseItem", stack.uid)
				elseif slot then
					NetClient.Fire("UnequipSlot", slot)
				else
					NetClient.Fire("EquipItem", stack.uid)
				end
			end
		end
	end)

	ProfileController.Changed:Connect(function(snapshot)
		if screen.Enabled then
			render(snapshot)
		end
	end)
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "Inventory" and isOpen then
			render(ProfileController.Get())
		end
	end)
end

return InventoryController
