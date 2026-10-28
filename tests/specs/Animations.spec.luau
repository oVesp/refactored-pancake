--!strict

-- Animation manifests (docs/art/animation-pipeline.md): content/animations/<set>.json agree with
-- Content/Assets and Content/AnimRoles, and every enemy set fills the required roles.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Expect = require("../Expect")
local Loader = require("../Loader")

local Assets = Loader.load("src/ReplicatedStorage/Content/Assets")
local AnimRoles = Loader.load("src/ReplicatedStorage/Content/AnimRoles")

local TIERS = { placeholder = true, final = true }
local EXPORTERS = { fbx = true, rbxanim = true, studio = true }

local function manifests(): { any }
	local list = {}
	for _, name in fs.readDir("content/animations") do
		if string.match(name, "%.json$") then
			local manifest = serde.decode("json", fs.readFile("content/animations/" .. name))
			Expect.equal(string.lower(manifest.set) .. ".json", name, `{name}: file name must match the set`)
			table.insert(list, manifest)
		end
	end
	return list
end

return {
	["every manifest clip is in Assets with the same id and KeyframeSequence"] = function()
		local seen = {}
		for _, manifest in manifests() do
			Expect.truthy(EXPORTERS[manifest.exporter], `{manifest.set}: unknown exporter {manifest.exporter}`)
			for key, clip in manifest.clips do
				Expect.truthy(seen[key] == nil, `{key} is in two manifests`)
				seen[key] = true
				Expect.truthy(TIERS[clip.tier], `{key}: tier must be placeholder or final`)
				local asset = Assets.Animations[key]
				Expect.truthy(asset, `{key} is not in Assets.Animations; run tools/anim/anim.py sync`)
				Expect.equal(clip.keyframes or key, asset.keyframes, `{key} keyframes`)
				Expect.equal(if clip.assetId then "rbxassetid://" .. clip.assetId else nil, asset.id, `{key} id`)
				Expect.truthy(
					fs.isFile(`{manifest.outDir}/{asset.keyframes}.rbxmx`),
					`{key}: {manifest.outDir}/{asset.keyframes}.rbxmx does not exist`
				)
			end
		end
		for key in Assets.Animations do
			Expect.truthy(seen[key], `Assets.Animations.{key} has no manifest clip`)
		end
	end,
	["every enemy set fills its required roles with matching keys and looping"] = function()
		for _, manifest in manifests() do
			if manifest.kind ~= "enemy" then
				continue
			end
			local filled = {}
			for key, clip in manifest.clips do
				local role = AnimRoles.Enemy[clip.role]
				Expect.truthy(role, `{key}: unknown role {clip.role}`)
				Expect.equal(manifest.set .. clip.role, key, `{key}: enemy keys are <AnimSet><Role>`)
				Expect.equal(role.looped, clip.looped, `{key} looped`)
				filled[clip.role] = true
			end
			for name, role in AnimRoles.Enemy do
				if role.required then
					Expect.truthy(filled[name], `{manifest.set} has no {name} clip`)
				end
			end
		end
	end,
	["fbx sets name a rig and only map clips that are not also in the library"] = function()
		for _, manifest in manifests() do
			if manifest.exporter ~= "fbx" then
				continue
			end
			Expect.truthy(manifest.rig and manifest.rig.status, `{manifest.set}: fbx sets need a rig block`)
			if manifest.rig.status == "ready" then
				Expect.truthy(fs.isFile(manifest.rig.bones), `{manifest.set}: rig bone list missing`)
				local scale = manifest.rig.studsPerMetre
				Expect.truthy(type(scale) == "number" or scale == "auto", `{manifest.set}: studsPerMetre`)
			end
			for key, clip in manifest.clips do
				Expect.truthy(clip.source, `{key}: no source`)
				Expect.truthy(manifest.library[clip.source] == nil, `{key}: {clip.source} is also in the library`)
			end
		end
	end,
}
