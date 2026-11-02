--!strict

-- Client prop culling helpers (docs/systems/atmosphere.md, Performance).
local Expect = require("../Expect")
local Loader = require("../Loader")

local PropCulling = Loader.load("src/ReplicatedStorage/Shared/PropCulling")
local PropDetail = Loader.load("src/ReplicatedStorage/Content/PropDetail")

return {
	["chunk centres follow the applier's floor-divided names"] = function()
		local x, z = PropCulling.ChunkCenter("0_-2", 256)
		Expect.equal(x, 128)
		Expect.equal(z, -384)
		Expect.equal(PropCulling.ChunkCenter("PoiSites", 256), nil, "non-chunk name")
		Expect.equal(PropCulling.ChunkDistance("1_0", 256, 384, 128), 0)
	end,
	["thinning keeps about the configured share, stably"] = function()
		local keep = PropDetail.Layers.Trees.keep
		local kept, total = 0, 0
		for x = -2000, 2000, 37 do
			for z = -2000, 2000, 41 do
				total += 1
				if PropCulling.Keeps(x, z, keep) then
					kept += 1
				end
				Expect.equal(PropCulling.Keeps(x, z, keep), PropCulling.Keeps(x, z, keep), "stable")
			end
		end
		Expect.truthy(math.abs(kept / total - keep) < 0.03, `kept share {kept / total}`)
		Expect.truthy(PropCulling.Keeps(5, 5, 1), "keep 1 keeps all")
		Expect.truthy(not PropCulling.Keeps(5, 5, 0), "keep 0 drops all")
	end,
	["hide and thin distances sit inside the streaming radius"] = function()
		for name, rule in PropDetail.Layers do
			local d = rule.hideBeyond or rule.thinBeyond
			Expect.truthy(d and d + PropDetail.Hysteresis < 1024, `{name} distance`)
		end
	end,
}
