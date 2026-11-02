--!strict

--[[
	Maps repository files to logical datasets the modules read and write. The repo *is* the database:
	every dataset knows its source path, how it is parsed (entry list keyed by `id`, a named map such
	as SkillSounds.BY_SKILL, JSON, or model.json), and which patch kinds are legal for it. Nothing
	else in the framework hard-codes a path, so pointing the same core at Items or Enemies later is a
	table edit here plus module registration.
]]

local Types = require("./Types")
local Parser = require("./Parser")

local Registry = {}

export type Dataset = {
	name: string,
	path: string,
	-- "entries": list of records with an id key; "map": one named local map inside the file;
	-- "json": a JSON document; "modelJson": one Rojo model.json per effect under `dir`.
	shape: string,
	-- For entries: the identifying field ("id"). For maps: the local name ("BY_SKILL").
	selector: string?,
	-- Patches may write this dataset (false for read-only references like Tuning).
	writable: boolean,
}

local datasets: { [string]: Dataset } = {}

local function register(dataset: Dataset)
	datasets[dataset.name] = dataset
end

register({ name = "Skills", path = "src/ReplicatedStorage/Content/Skills.luau", shape = "entries", selector = "id", writable = true })
register({ name = "SkillSounds", path = "src/ReplicatedStorage/Content/SkillSounds.luau", shape = "map", selector = "BY_SKILL", writable = true })
register({ name = "Types", path = "src/ReplicatedStorage/Content/Types.luau", shape = "source", writable = false })
register({ name = "Assets", path = "src/ReplicatedStorage/Content/Assets.luau", shape = "source", writable = false })
register({ name = "Tuning", path = "src/ReplicatedStorage/Content/Tuning.luau", shape = "source", writable = false })
register({ name = "Classes", path = "src/ReplicatedStorage/Content/Classes.luau", shape = "source", writable = false })
register({ name = "Weapons", path = "src/ReplicatedStorage/Content/Weapons.luau", shape = "source", writable = false })
register({ name = "Statuses", path = "src/ReplicatedStorage/Content/Statuses.luau", shape = "source", writable = false })
register({ name = "Enemies", path = "src/ReplicatedStorage/Content/Enemies.luau", shape = "source", writable = false })
register({ name = "SpellEffects", path = "src/StarterPlayer/StarterPlayerScripts/Client/Vfx/SpellEffects.luau", shape = "source", writable = false })
register({ name = "Animations", path = "content/animations", shape = "jsonDir", writable = false })
register({ name = "VfxTemplates", path = "src/ReplicatedStorage/Vfx", shape = "modelJsonDir", writable = false })

Registry.datasets = datasets

--[=[ True when `path` is a file a patch bundle is allowed to modify. Everything else is refused. ]=]
function Registry.isWritablePath(path: string): boolean
	for _, dataset in datasets do
		if dataset.writable and dataset.path == path then
			return true
		end
	end
	return false
end

--[=[ Parses one dataset from source text. `entries` and `map` shapes use Parser; sources stay raw. ]=]
function Registry.parse(name: string, source: string): any
	local dataset = datasets[name]
	assert(dataset, `Unknown dataset {name}`)
	if dataset.shape == "entries" then
		return Parser.parseEntryList(source, dataset.selector or "id")
	elseif dataset.shape == "map" then
		return Parser.parseMap(source, dataset.selector or "")
	end
	return source
end

--[=[ Renders a patch's target description for logs and the commit preview. ]=]
function Registry.describe(patch: Types.Patch): string
	local dataset = datasets[patch.dataset]
	local path = if dataset then dataset.path else "?"
	if patch.patchKind == "appendEntry" then
		return `{path}: append entry {patch.entry or "?"}`
	elseif patch.patchKind == "setMapValue" then
		return `{path}: {patch.entry} -> {patch.valueText}`
	elseif patch.patchKind == "appendMapEntry" then
		return `{path}: new map entry {patch.entry}`
	else
		return `{path}: {patch.entry}.{patch.field} = {patch.valueText}`
	end
end

return Registry
