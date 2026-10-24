--!strict

export type ClassEntry = {
	id: string,
	level: number,
}

export type ItemStack = {
	uid: number,
	id: string,
	count: number,
}

export type Profile = {
	schemaVersion: number,
	heritage: string,
	--[=[ Build path: classes in the order they were taken (game-design.md 3.1). ]=]
	classes: { ClassEntry },
	xp: number,
	xpDebt: number,
	spells: { string },
	disciplines: { string },
	inventory: { ItemStack },
	--[=[ Slot name -> item uid. ]=]
	equipment: { [string]: number },
	nextUid: number,
}

local SCHEMA_VERSION = 1

local Profile = {}

Profile.SchemaVersion = SCHEMA_VERSION

--[=[
	Returns a fresh profile for a new character, holding `starter` items. Persistent state only;
	no session data.
]=]
function Profile.new(starter: { { id: string, count: number } }?): Profile
	local profile: Profile = {
		schemaVersion = SCHEMA_VERSION,
		heritage = "Human",
		classes = {},
		xp = 0,
		xpDebt = 0,
		spells = {},
		disciplines = {},
		inventory = {},
		equipment = {},
		nextUid = 1,
	}
	for _, entry in (starter or {}) :: { { id: string, count: number } } do
		table.insert(profile.inventory, { uid = profile.nextUid, id = entry.id, count = entry.count })
		profile.nextUid += 1
	end
	return profile
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

--[=[ Finds an inventory stack by uid. ]=]
function Profile.FindStack(profile: Profile, uid: number): (ItemStack?, number?)
	for index, stack in profile.inventory do
		if stack.uid == uid then
			return stack, index
		end
	end
	return nil, nil
end

--[=[
	Adds `count` of an item, filling existing stacks up to `stackSize` first. Returns how many
	could not fit because the inventory is full.
]=]
function Profile.AddItem(profile: Profile, itemId: string, count: number, stackSize: number, capacity: number): number
	local remaining = count
	for _, stack in profile.inventory do
		if remaining <= 0 then
			break
		end
		if stack.id == itemId and stack.count < stackSize then
			local add = math.min(stackSize - stack.count, remaining)
			stack.count += add
			remaining -= add
		end
	end
	while remaining > 0 and #profile.inventory < capacity do
		local add = math.min(stackSize, remaining)
		table.insert(profile.inventory, { uid = profile.nextUid, id = itemId, count = add })
		profile.nextUid += 1
		remaining -= add
	end
	return remaining
end

--[=[ Removes one item from a stack, dropping the stack when empty and clearing equipment that pointed at it. ]=]
function Profile.ConsumeOne(profile: Profile, uid: number): boolean
	local stack, index = Profile.FindStack(profile, uid)
	if not stack or not index then
		return false
	end
	stack.count -= 1
	if stack.count <= 0 then
		table.remove(profile.inventory, index)
		for slot, equipped in profile.equipment do
			if equipped == uid then
				profile.equipment[slot] = nil
			end
		end
	end
	return true
end

return Profile
