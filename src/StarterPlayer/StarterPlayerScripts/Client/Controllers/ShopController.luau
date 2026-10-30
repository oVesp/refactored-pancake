--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Content.Items)
local NetClient = require(ReplicatedStorage.Shared.Net.Client)
local Shop = require(ReplicatedStorage.Content.Shop)
local Theme = require(ReplicatedStorage.Shared.Theme)

--[=[
	Shop panel (docs/systems/economy.md): a vendor's prompt opens the Shop screen beside the vendor.
	Rows come from `Content/Shop` through the `ListRow` template; a button asks the server to buy one,
	and the server checks price, range and inventory room.
]=]
local ShopController = {}

local UIController: any
local ProfileController: any

local bound: { [string]: GuiObject }
local vendor: BasePart? = nil

local function shopOf(body: BasePart): Shop.ShopDef?
	local id = body:GetAttribute("ShopId")
	return Shop.ById[if type(id) == "string" then id else Shop.Default]
end

local function render()
	local body = vendor
	local shop = body and shopOf(body)
	if not body or not shop then
		return
	end
	local snapshot = ProfileController.Get()
	local gold = if snapshot then snapshot.gold or 0 else 0
	UIController.SetText(bound.Bind_Title, string.upper(shop.name))
	UIController.SetText(bound.Bind_Gold, string.format("%d gold", gold))
	UIController.ClearRows(bound.Bind_List)
	for index, entry in shop.stock do
		local def = Items.ById[entry.item]
		if not def then
			continue
		end
		local row = UIController.Clone("ListRow") :: Frame
		local parts = UIController.Bind(row, { "Bind_Title", "Bind_Detail", "Bind_Action" })
		UIController.SetText(parts.Bind_Title, def.name)
		UIController.SetText(parts.Bind_Detail, string.format("%d gold. %s", entry.price, def.description))
		local action = parts.Bind_Action :: TextButton
		action.Text = "Buy"
		local affordable = gold >= entry.price
		action.AutoButtonColor = affordable
		action.BackgroundColor3 = if affordable then Theme.Gold else Theme.GoldDim
		action.Activated:Connect(function()
			if vendor then
				NetClient.Fire("BuyItem", vendor, entry.item, 1)
			end
		end)
		row.LayoutOrder = index
		row.Parent = bound.Bind_List
	end
end

local function open(body: Instance)
	if not body:IsA("BasePart") then
		return
	end
	vendor = body
	render()
	UIController.Close("Shop")
	UIController.Open("Shop", body)
end

function ShopController.Init(deps: { [string]: any })
	UIController = deps.UIController
	ProfileController = deps.ProfileController
end

function ShopController.Start()
	local screen = UIController.GetScreen("Shop")
	bound = UIController.Bind(screen, { "Bind_Title", "Bind_Close", "Bind_Gold", "Bind_List" })
	UIController.BindClose("Shop")
	ProfileController.Changed:Connect(function()
		if screen.Enabled then
			render()
		end
	end)
	UIController.ModalChanged:Connect(function(name: string, isOpen: boolean)
		if name == "Shop" and not isOpen then
			vendor = nil
		end
	end)
	NetClient.Connect("OpenShop", open)
end

return ShopController
