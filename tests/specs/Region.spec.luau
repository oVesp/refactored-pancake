--!strict

-- Region builds (src/ServerStorage/WorldGen/Gen/Region, docs/systems/world-generation.md).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Expect = require("../Expect")
local Loader = require("../Loader")

local Continent = Loader.load("src/ServerStorage/WorldGen/Gen/Continent")
local Region = Loader.load("src/ServerStorage/WorldGen/Gen/Region")
local Template = Loader.load("src/ServerStorage/WorldGen/Continent")

local sample = Continent.sampler(Template, Template.seed)

local function at(x: number, z: number): any
	return sample(Continent.toUnit(Template, x, z))
end

return {
	["the origin is the Harbor village"] = function()
		for _, site in Template.sites do
			if site.id == "harbor" then
				Expect.truthy(site.fixed, "harbor must be fixed")
				Expect.equal(site.at[1], Template.origin[1])
				Expect.equal(site.at[2], Template.origin[2])
				return
			end
		end
		error("no harbor site")
	end,

	["the Map's zones stand on flat, dry pads"] = function()
		local map = roblox.deserializeModel(fs.readFile("src/Workspace/Map.rbxmx"))[1]
		local zones = map:FindFirstChild("Zones")
		Expect.truthy(zones, "Map has no Zones")
		for _, zone in zones:GetChildren() do
			local p = zone.CFrame.Position
			local half = zone.Size / 2
			for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 0 } } do
				local x, z = p.X + c[1] * half.X, p.Z + c[2] * half.Z
				local point = at(x, z)
				Expect.truthy(point.pad > 0.99, `{zone.Name}: ({x}, {z}) is off the pads`)
				Expect.truthy(point.water == nil, `{zone.Name}: ({x}, {z}) is under water`)
				Expect.truthy(
					math.abs(point.height - Template.heights.ground) < 0.01,
					`{zone.Name}: ground {point.height} at ({x}, {z})`
				)
				Expect.equal(point.owner, Region.index(Region.context(Template), Template.pads.region))
			end
		end
	end,

	["the sea lies beside the village for the docks"] = function()
		local found = false
		for z = 100, 300, 8 do
			local point = at(0, z)
			if point.region == Continent.SEA then
				found = true
				break
			end
		end
		Expect.truthy(found, "no sea within 300 studs south of the village")
	end,

	["approved regions are unchanged"] = function()
		local ctx: any = nil
		for id, fingerprint in Template.approved do
			ctx = ctx or Region.context(Template)
			Expect.equal(Region.fingerprint(ctx, id), fingerprint)
		end
	end,
}
