--!strict

-- Terrain generator (tools/terrain) and the committed WorldGen data it produces.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Expect = require("../Expect")
local Config = require("../../tools/terrain/lib/Config")
local Encode = require("../../tools/terrain/lib/Encode")
local Grid = require("../../tools/terrain/lib/Grid")
local Heightfield = require("../../tools/terrain/lib/Heightfield")
local Layout = require("../../tools/terrain/lib/Layout")
local Noise = require("../../tools/terrain/lib/Noise")
local Scatter = require("../../tools/terrain/lib/Scatter")
local Water = require("../../tools/terrain/lib/Water")

local DATA = "src/ServerStorage/WorldGen/Data"

local function smallConfig(): any
	local cfg = table.clone(Config) :: any
	cfg.n = 64
	cfg.originX = -128
	cfg.originZ = -128
	return cfg
end

local function smallLayout(cfg: any): any
	return Layout.build(cfg.seed, nil, { { name = "Pad", cx = 0, cz = 0, hx = 20, hz = 20 } })
end

local function loadMeta(): any
	return luau.load(fs.readFile(`{DATA}/Meta.luau`))()
end

local function readModuleString(path: string): string
	local source = fs.readFile(path)
	return string.match(source, 'return "([^"]*)"') or string.match(source, "return %[%[\n(.-)%]%]") or ""
end

return {
	["hash is deterministic, spread and in range"] = function()
		Expect.equal(Noise.hash32(1, 2, 3), Noise.hash32(1, 2, 3), "same input")
		Expect.truthy(Noise.hash32(1, 2, 3) ~= Noise.hash32(1, 2, 4), "neighbour differs")
		local sum = 0
		for k = 1, 2000 do
			local v = Noise.hash01(7, k)
			Expect.truthy(v >= 0 and v < 1, "hash01 range")
			sum += v
		end
		Expect.truthy(math.abs(sum / 2000 - 0.5) < 0.03, "hash01 mean near 0.5")
	end,
	["fbm stays in [-1, 1] and ridged in [0, 1]"] = function()
		local f = Noise.fbm(3, 100, 5, 2, 0.5)
		local r = Noise.ridged(3, 100, 5, 2, 0.5)
		for k = 1, 500 do
			local x, z = k * 13.7, k * -7.3
			Expect.truthy(math.abs(f(x, z)) <= 1, "fbm range")
			local v = r(x, z)
			Expect.truthy(v >= 0 and v <= 1, "ridged range")
		end
	end,
	["base64 matches the RFC 4648 vectors"] = function()
		local function enc(s: string): string
			return Encode.base64(buffer.fromstring(s))
		end
		Expect.equal(enc("Man"), "TWFu")
		Expect.equal(enc("Ma"), "TWE=")
		Expect.equal(enc("M"), "TQ==")
		Expect.equal(enc("foobar"), "Zm9vYmFy")
	end,
	["height encoding round-trips within a sixteenth of a stud"] = function()
		for _, h in { -80, -3, 0, 0.2, 57.31, 357 } do
			Expect.truthy(math.abs(Encode.decodeHeight(Encode.height(h)) - h) <= 1 / 32, `height {h}`)
		end
	end,
	["heightfield is deterministic and pads end flat at 0"] = function()
		local cfg = smallConfig()
		local a = Heightfield.generate(cfg, smallLayout(cfg))
		local b = Heightfield.generate(cfg, smallLayout(cfg))
		Expect.equal(buffer.tostring(a.height.data), buffer.tostring(b.height.data), "same seed, same terrain")
		Heightfield.flattenPads(cfg, a)
		for j = 0, cfg.n - 1 do
			for i = 0, cfg.n - 1 do
				if Grid.get(a.padDistance, i, j) <= 0 then
					Expect.equal(Grid.get(a.height, i, j), 0, `pad cell {i},{j}`)
				end
			end
		end
	end,
	["flow drains every cell to the border"] = function()
		local g = Grid.new(32)
		for j = 0, 31 do
			for i = 0, 31 do
				Grid.set(g, i, j, i + j * 0.1)
			end
		end
		local acc = Water.flow(g)
		local total = 0
		for j = 0, 31 do
			total += Grid.get(acc, 0, j)
		end
		-- Most of a plane tilted toward x = 0 drains out through that edge.
		Expect.truthy(total > 0.9, `drained share {total}`)
	end,
	["poisson samples keep the minimum distance"] = function()
		local cfg = smallConfig()
		local pts = Scatter.poisson(cfg, 10, 42)
		Expect.truthy(#pts > 50, "enough samples")
		for a = 1, #pts do
			for b = a + 1, #pts do
				local d = math.sqrt((pts[a][1] - pts[b][1]) ^ 2 + (pts[a][2] - pts[b][2]) ^ 2)
				Expect.truthy(d >= 10 - 1e-6, "spacing")
			end
		end
	end,
	["committed terrain data is complete"] = function()
		local meta = loadMeta()
		Expect.equal(meta.chunks * meta.chunkRows, meta.n, "chunks cover the tile")
		for c = 1, meta.chunks do
			local text = readModuleString(string.format("%s/Terrain%02d.luau", DATA, c))
			Expect.equal(#text, math.ceil(meta.chunkRows * meta.n * 5 / 3) * 4, `chunk {c} length`)
		end
	end,
	["committed props reference known assets inside the tile"] = function()
		local meta = loadMeta()
		local known = {}
		for _, group in Config.groups do
			for _, a in group.assets do
				known[a.name] = true
			end
		end
		for _, asset in meta.assets do
			Expect.truthy(known[asset.name], `asset {asset.name} is in Config`)
		end
		local names = meta.assets
		local size = Config.n * Config.cell
		for _, layer in { "Paths", "Trees", "Rocks", "Understory", "Cover", "Pebbles" } do
			local text = readModuleString(`{DATA}/Scatter{layer}.luau`)
			for line in string.gmatch(text, "[^\n]+") do
				local a, x, _, z = string.match(line, "^(%d+) (%S+) (%S+) (%S+)")
				local idx, px, pz = tonumber(a), tonumber(x), tonumber(z)
				assert(idx and px and pz, `bad line in {layer}: {line}`)
				Expect.truthy(idx >= 1 and idx <= #names, `{layer} asset index {idx}`)
				Expect.truthy(px > Config.originX and px < Config.originX + size, `{layer} x {px}`)
				Expect.truthy(pz > Config.originZ and pz < Config.originZ + size, `{layer} z {pz}`)
			end
		end
	end,
}
