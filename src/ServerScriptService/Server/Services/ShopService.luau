--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Items = require(ReplicatedStorage.Content.Items)
local NetServer = require(ReplicatedStorage.Shared.Net.Server)
local Profile = require(script.Parent.Parent.Data.Profile)
local Shop = require(ReplicatedStorage.Content.Shop)
local Tuning = require(ReplicatedStorage.Content.Tuning)

-- Slack on top of the prompt's reach for lag, in studs.
local REACH_SLACK = 8

local DataService: any

--[=[
	Vendors (docs/systems/economy.md). A vendor is a part tagged `Trainer` with `TrainerType =
	"Vendor"`; its optional `ShopId` attribute picks the stock (default `inn`). The client only names
	the item and the count: price, stock, range and inventory room are all checked here.
]=]
local ShopService = {}

local function notify(player: Player, key: string, ...: any)
	NetServer.Fire("Notify", player, key, { ... })
end

--[=[ The shop a vendor body sells from, or nil when the body is not a vendor. ]=]
function ShopService.ShopOf(body: Instance): Shop.ShopDef?
	if not body:IsA("BasePart") or not CollectionService:HasTag(body, "Trainer") then
		return nil
	end
	if body:GetAttribute("TrainerType") ~= "Vendor" then
		return nil
	end
	local id = body:GetAttribute("ShopId")
	return Shop.ById[if type(id) == "string" then id else Shop.Default]
end

local function inReach(player: Player, body: BasePart): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local prompt = body:FindFirstChildOfClass("ProximityPrompt")
	local reach = if prompt then prompt.MaxActivationDistance else Tuning.Quests.Reach
	return (root.Position - body.Position).Magnitude <= reach + REACH_SLACK
end

--[=[ Buys `count` of an item from the vendor `body`. Returns true when the purchase went through. ]=]
function ShopService.Buy(player: Player, body: Instance, itemId: string, count: number): boolean
	local shop = ShopService.ShopOf(body)
	local profile = DataService.Get(player)
	if not shop or not profile or not body:IsA("BasePart") then
		return false
	end
	if not inReach(player, body) then
		notify(player, "TooFar")
		return false
	end
	local entry
	for _, candidate in shop.stock do
		if candidate.item == itemId then
			entry = candidate
			break
		end
	end
	local def = Items.ById[itemId]
	if not entry or not def or count < 1 or count > Shop.MaxPurchase then
		notify(player, "NotForSale")
		return false
	end
	local cost = entry.price * count
	if profile.gold < cost then
		notify(player, "NoGold")
		return false
	end
	if not Profile.CanFit(profile, def.stack, itemId, count, Items.InventorySize) then
		notify(player, "InventoryFull")
		return false
	end
	DataService.Update(player, function(p: any)
		p.gold -= cost
		Profile.AddItem(p, itemId, count, def.stack, Items.InventorySize)
	end, "inventory")
	notify(player, "Bought", count, def.name)
	return true
end

function ShopService.Init(deps: { [string]: any })
	DataService = deps.DataService
end

function ShopService.Start()
	NetServer.Connect("BuyItem", ShopService.Buy)
end

return ShopService
