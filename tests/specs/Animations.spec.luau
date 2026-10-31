--!strict

-- Animation manifests (docs/art/animation-pipeline.md): content/animations/<set>.json agree with the
-- Animation instances under src/ReplicatedStorage/Animations and Content/AnimRoles, and every enemy
-- set fills the required roles.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Expect = require("../Expect")
local Loader = require("../Loader")

local AnimRoles = Loader.load("src/ReplicatedStorage/Content/AnimRoles")

local TIERS = { placeholder = true, final = true }

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

local function assetOf(clips: { [string]: any }, clip: any): string?
	if clip.assetId then
		return clip.assetId
	end
	local target = clip.alias and clips[clip.alias]
	return target and target.assetId
end

return {
	["every manifest clip has an Animation file with its id, and no file is orphaned"] = function()
		local all = {}
		for _, manifest in manifests() do
			for key, clip in manifest.clips do
				Expect.truthy(all[key] == nil, `{key} is in two manifests`)
				all[key] = clip
			end
		end
		for key, clip in all do
			Expect.truthy(TIERS[clip.tier], `{key}: tier must be placeholder or final`)
			local id = assetOf(all, clip)
			Expect.truthy(id, `{key}: no assetId`)
			local path = `src/ReplicatedStorage/Animations/{key}.model.json`
			Expect.truthy(fs.isFile(path), `{path} does not exist; run tools/anim/anim.py sync`)
			local model = serde.decode("json", fs.readFile(path))
			Expect.equal(model.className, "Animation", `{key} class`)
			Expect.equal(model.properties.AnimationId, "rbxassetid://" .. id, `{key} id`)
			Expect.equal(model.attributes.Looped, clip.looped == true, `{key} looped`)
			for marker in clip.markers or {} do
				Expect.truthy(AnimRoles.Markers[marker], `{key}: marker {marker} is not in AnimRoles.Markers`)
			end
		end
		for _, name in fs.readDir("src/ReplicatedStorage/Animations") do
			local key = string.match(name, "^(.+)%.model%.json$")
			Expect.truthy(key and all[key], `{name} has no manifest clip`)
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
}
