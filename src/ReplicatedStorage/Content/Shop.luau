--!strict

export type Entry = {
	item: string,
	--[=[ Coins per unit. ]=]
	price: number,
}

export type ShopDef = {
	id: string,
	name: string,
	stock: { Entry },
}

--[=[
	Shops, keyed by the `ShopId` attribute of a vendor body (default `inn`). Prices live here, never
	on the client's request: the server looks them up (docs/systems/economy.md).
]=]
local list: { ShopDef } = {
	{
		id = "inn",
		name = "Harbor Inn",
		stock = {
			{ item = "bread", price = 3 },
			{ item = "water_flask", price = 2 },
			{ item = "cooked_meat", price = 8 },
			{ item = "minor_health_potion", price = 15 },
			{ item = "minor_mana_potion", price = 15 },
		},
	},
}

local byId: { [string]: ShopDef } = {}
for _, shop in list do
	byId[shop.id] = table.freeze(shop)
end

return table.freeze({
	ById = table.freeze(byId),
	Default = "inn",
	--[=[ Most units one purchase may buy. ]=]
	MaxPurchase = 20,
})
