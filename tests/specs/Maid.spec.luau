--!strict

local Expect = require("../Expect")
local Maid = require("../../src/ReplicatedStorage/Shared/Maid")

return {
	["cleans tasks in reverse order and is reusable"] = function()
		local maid = Maid.new()
		local order = {}
		maid:Give(function()
			table.insert(order, 1)
		end)
		maid:Give({
			Destroy = function()
				table.insert(order, 2)
			end,
		})
		maid:Clean()
		Expect.equal(order[1], 2)
		Expect.equal(order[2], 1)

		maid:Give(function()
			table.insert(order, 3)
		end)
		maid:Clean()
		Expect.equal(order[3], 3)
	end,
}
