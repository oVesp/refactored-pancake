--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Factions = Loader.load("src/ReplicatedStorage/Content/Factions")
local Relations = Loader.load("src/ReplicatedStorage/Shared/Relations")

return {
	["relations name known factions only, once per pair"] = function()
		local seen: { [string]: boolean } = {}
		for _, entry in Factions.Relations do
			local a, b, standing = entry[1], entry[2], entry[3]
			Expect.truthy(Factions.ById[a], `unknown faction {a}`)
			Expect.truthy(Factions.ById[b], `unknown faction {b}`)
			Expect.truthy(a ~= b, `{a} lists itself`)
			Expect.truthy(standing == "Hostile" or standing == "Allied", `{a}/{b}: bad standing {standing}`)
			local key = if a < b then a .. "/" .. b else b .. "/" .. a
			Expect.truthy(not seen[key], `{key} listed twice`)
			seen[key] = true
		end
	end,

	["standing is symmetric and self-allied"] = function()
		for a in Factions.ById do
			Expect.equal(Relations.Standing(a, a), "Allied")
			for b in Factions.ById do
				Expect.equal(Relations.Standing(a, b), Relations.Standing(b, a))
			end
		end
	end,

	["monsters are hostile to players and the town"] = function()
		for id, def in Factions.ById do
			if def.monster then
				Expect.truthy(Relations.Hostile(id, "Adventurers"), `{id} not hostile to players`)
				Expect.truthy(Relations.Hostile(id, "Town"), `{id} not hostile to the town`)
				Expect.truthy(Relations.IsMonster(id), id)
			end
		end
	end,

	["adventurers never fight adventurers or civilians"] = function()
		for _, other in { "Adventurers", "Town", "Merchants", "Travelers" } do
			Expect.truthy(not Relations.Hostile("Adventurers", other), other)
		end
		Expect.truthy(Relations.Hostile("Adventurers", "Neutral"))
		Expect.truthy(not Relations.Hostile("Goblins", "Neutral"))
	end,

	["the empires are at war and adventurers stay neutral to both"] = function()
		Expect.truthy(Relations.Hostile("HolyKingdom", "DragonEmpire"))
		for _, empire in { "HolyKingdom", "DragonEmpire" } do
			Expect.equal(Relations.Standing("Adventurers", empire), "Neutral")
		end
	end,
}
