--!strict

export type ClassEntry = {
	id: string,
	level: number,
}

export type Profile = {
	schemaVersion: number,
	heritage: string,
	--[=[ Build path: classes in the order they were taken (game-design.md 3.1). ]=]
	classes: { ClassEntry },
	xp: number,
}

local SCHEMA_VERSION = 1

local Profile = {}

Profile.SchemaVersion = SCHEMA_VERSION

--[=[ Returns a fresh profile for a new character. Persistent state only; no session data. ]=]
function Profile.new(): Profile
	return {
		schemaVersion = SCHEMA_VERSION,
		heritage = "Human",
		classes = {},
		xp = 0,
	}
end

--[=[
	Upgrades stored data to the current schema. Errors on data from a newer schema,
	which means the server is older than the data and must not overwrite it.
]=]
function Profile.Migrate(data: Profile): Profile
	assert(data.schemaVersion <= SCHEMA_VERSION, `Profile schema {data.schemaVersion} is newer than {SCHEMA_VERSION}`)
	return data
end

local function check(value: any, path: string, seen: { [any]: boolean }): (boolean, string?)
	local kind = type(value)
	if kind == "boolean" or kind == "string" then
		return true
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false, `{path} is NaN or infinite`
		end
		return true
	elseif kind == "table" then
		if getmetatable(value) ~= nil then
			return false, `{path} has a metatable`
		end
		if seen[value] then
			return false, `{path} is a cycle or shared reference`
		end
		seen[value] = true
		for key, child in value do
			local keyType = type(key)
			if keyType ~= "string" and keyType ~= "number" then
				return false, `{path} has a {keyType} key`
			end
			local ok, reason = check(child, `{path}.{key}`, seen)
			if not ok then
				return false, reason
			end
		end
		return true
	end
	return false, `{path} is a {kind}`
end

--[=[
	Checks that a value holds only numbers, strings, booleans and plain tables, with no
	NaN/inf, metatables, cycles or shared references (game-design.md 5.8).
	Returns false and the first offending path otherwise.
]=]
function Profile.IsSerializable(value: any): (boolean, string?)
	return check(value, "profile", {})
end

return Profile
