--!strict

local Vector3 = require("@lune/roblox").Vector3

local Expect = require("../Expect")
local Loader = require("../Loader")

local Formation = Loader.load("src/ReplicatedStorage/Shared/Formation")
local Route = Loader.load("src/ReplicatedStorage/Shared/Route")
local SpatialHash = Loader.load("src/ReplicatedStorage/Shared/SpatialHash")

local function near(a: any, b: any, label: string)
	Expect.truthy((a - b).Magnitude < 1e-3, `{label}: {a} vs {b}`)
end

return {
	["formations put the leader at the origin and never stack members"] = function()
		for _, shape in { "Column", "Line", "Wedge", "Ring" } do
			local offsets = Formation.Offsets(shape, 6, 4)
			Expect.equal(#offsets, 6, shape)
			near(offsets[1], Vector3.zero, shape)
			for i = 1, #offsets do
				for j = i + 1, #offsets do
					Expect.truthy((offsets[i] - offsets[j]).Magnitude >= 3.9, `{shape} {i}/{j} overlap`)
				end
			end
		end
	end,

	["column and wedge trail behind the leader"] = function()
		for _, offset in Formation.Offsets("Column", 4, 5) do
			Expect.truthy(offset.Z >= 0 and offset.X == 0)
		end
		local wedge = Formation.Offsets("Wedge", 5, 4)
		Expect.truthy(wedge[2].X > 0 and wedge[3].X < 0 and wedge[2].Z == wedge[3].Z)
	end,

	["place turns offsets into the leader's frame"] = function()
		-- Facing +X: right is +Z, behind is -X.
		local origin = Vector3.new(10, 2, 10)
		near(Formation.Place(origin, Vector3.new(1, 0, 0), Vector3.new(0, 0, 4)), Vector3.new(6, 2, 10), "behind")
		near(Formation.Place(origin, Vector3.new(1, 0, 0), Vector3.new(3, 0, 0)), Vector3.new(10, 2, 13), "right")
	end,

	["open routes clamp and report the end"] = function()
		local route = Route.new({ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 0, 10) }, false)
		Expect.equal(route.length, 20)
		local at, heading, finished = Route.At(route, 15)
		near(at, Vector3.new(10, 0, 5), "mid second leg")
		near(heading, Vector3.new(0, 0, 1), "heading")
		Expect.truthy(not finished)
		at, _, finished = Route.At(route, 99)
		near(at, Vector3.new(10, 0, 10), "end")
		Expect.truthy(finished)
	end,

	["loops wrap through the closing leg"] = function()
		local square = { Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 0, 10), Vector3.new(0, 0, 10) }
		local route = Route.new(square, true)
		Expect.equal(route.length, 40)
		near((Route.At(route, 35)), Vector3.new(0, 0, 5), "closing leg")
		near((Route.At(route, 45)), Vector3.new(5, 0, 0), "wrapped")
	end,

	["nearest finds the distance along the route"] = function()
		local route = Route.new({ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 0, 10) }, false)
		Expect.truthy(math.abs(Route.Nearest(route, Vector3.new(12, 5, 4)) - 14) < 1e-3)
		Expect.truthy(math.abs(Route.Nearest(route, Vector3.new(3, 0, -2)) - 3) < 1e-3)
	end,

	["a hint keeps an out-and-back route on the leg the walker was on"] = function()
		local route = Route.new({ Vector3.new(0, 0, 0), Vector3.new(100, 0, 0), Vector3.new(0, 0, 0) }, false)
		local onReturn = Vector3.new(30, 0, 1)
		Expect.truthy(math.abs(Route.Nearest(route, onReturn) - 30) < 1e-3, "no hint: first leg")
		Expect.truthy(math.abs(Route.Nearest(route, onReturn, 165, 80) - 170) < 1e-3, "hint: return leg")
		local loop = Route.new({ Vector3.new(0, 0, 0), Vector3.new(10, 0, 0), Vector3.new(10, 0, 10) }, true)
		-- (1, 1) lies on the closing leg, 3.4 studs before the start: within the wrapped window.
		Expect.truthy(Route.Nearest(loop, Vector3.new(1, 0, 1), 2, 6) > 30, "loop wraps the window")
	end,

	["spatial hash returns exactly the items in range"] = function()
		local hash = SpatialHash.new(16)
		local points = {}
		for i = 1, 200 do
			local p = Vector3.new((i * 37) % 300 - 150, 0, (i * 91) % 300 - 150)
			points[i] = p
			SpatialHash.Insert(hash, i, p)
		end
		local centre, radius = Vector3.new(20, 0, -30), 45
		local found: { [number]: boolean } = {}
		for _, i in SpatialHash.Query(hash, centre, radius) do
			found[i] = true
		end
		for i, p in points do
			Expect.equal(found[i] == true, (p - centre).Magnitude <= radius, `point {i}`)
		end
		SpatialHash.Clear(hash)
		Expect.equal(#SpatialHash.Query(hash, centre, radius), 0)
	end,
}
