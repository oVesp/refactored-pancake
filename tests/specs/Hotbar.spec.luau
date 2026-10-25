--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Hotbar = Loader.load("src/ReplicatedStorage/Shared/Hotbar")

return {
	["encode and decode round-trip"] = function()
		local kind, id = Hotbar.Decode(Hotbar.Encode("Skill", "fire_bolt"))
		Expect.equal(kind, "Skill")
		Expect.equal(id, "fire_bolt")
		Expect.equal(Hotbar.Decode(""), nil, "empty")
		Expect.equal(Hotbar.Decode("Item:potion"), nil, "unknown kind")
		Expect.equal(Hotbar.Decode("Skill:"), nil, "missing id")
	end,
	["place swaps an entry already on the bar"] = function()
		local slots = Hotbar.Empty()
		Hotbar.Place(slots, 1, "Skill:a")
		Hotbar.Place(slots, 2, "Skill:b")
		Hotbar.Place(slots, 2, "Skill:a")
		Expect.equal(slots[1], "Skill:b")
		Expect.equal(slots[2], "Skill:a")
		Hotbar.Place(slots, 1, "")
		Expect.equal(slots[1], "")
		Expect.equal(#slots, Hotbar.Size, "no holes")
	end,
	["place rejects out-of-range slots"] = function()
		Expect.errors(function()
			Hotbar.Place(Hotbar.Empty(), Hotbar.Size + 1, "Skill:a")
		end)
	end,
	["auto place fills the first gap once"] = function()
		local slots = Hotbar.Empty()
		slots[1] = "Skill:a"
		Expect.equal(Hotbar.AutoPlace(slots, "Skill:b"), 2)
		Expect.equal(Hotbar.AutoPlace(slots, "Skill:b"), nil, "already placed")
		for index = 3, Hotbar.Size do
			slots[index] = `Skill:x{index}`
		end
		Expect.equal(Hotbar.AutoPlace(slots, "Skill:c"), nil, "full")
	end,
	["prune clears unknown and malformed slots"] = function()
		local slots = Hotbar.Empty()
		slots[1] = "Skill:a"
		slots[2] = "Skill:b"
		slots[3] = "garbage"
		Hotbar.Prune(slots, function(_kind, id)
			return id == "a"
		end)
		Expect.equal(slots[1], "Skill:a")
		Expect.equal(slots[2], "")
		Expect.equal(slots[3], "")
	end,
}
