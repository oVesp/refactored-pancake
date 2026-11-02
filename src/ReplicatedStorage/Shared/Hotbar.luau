--!strict

--[=[
	Hotbar layout rules shared by server and client (docs/systems/progression.md, Hotbar). The
	profile stores `Size` strings, one per slot: `""` for empty, otherwise `Kind:id`
	(`Skill:firebolt`, `Discipline:dash_step`). No nil holes, so the array stays serializable.
]=]
local Hotbar = {}

Hotbar.Size = 8

export type Kind = "Skill" | "Discipline"

--[=[ A fresh layout with every slot empty. ]=]
function Hotbar.Empty(): { string }
	return table.create(Hotbar.Size, "")
end

--[=[ Encodes an entry for storage. ]=]
function Hotbar.Encode(kind: Kind, id: string): string
	return `{kind}:{id}`
end

--[=[ Decodes a stored slot. Returns nil for an empty or malformed slot. ]=]
function Hotbar.Decode(slot: string): (Kind?, string?)
	local kind, id = string.match(slot, "^(%a+):([%w_]+)$")
	if kind == "Skill" then
		return "Skill", id
	elseif kind == "Discipline" then
		return "Discipline", id
	end
	return nil, nil
end

--[=[
	Puts `entry` (an encoded slot, or `""` to clear) into slot `index`. If the entry already sits
	in another slot, the two slots swap, so an entry is never on the bar twice.
]=]
function Hotbar.Place(slots: { string }, index: number, entry: string)
	assert(index >= 1 and index <= Hotbar.Size and index % 1 == 0, `Hotbar index {index} out of range`)
	if entry ~= "" then
		local from = table.find(slots, entry)
		if from and from ~= index then
			slots[from] = slots[index]
		end
	end
	slots[index] = entry
end

--[=[
	Puts a newly learned entry into the first empty slot, unless it is already on the bar or the
	bar is full. Returns the slot used, or nil.
]=]
function Hotbar.AutoPlace(slots: { string }, entry: string): number?
	if table.find(slots, entry) then
		return nil
	end
	for index = 1, Hotbar.Size do
		if slots[index] == "" then
			slots[index] = entry
			return index
		end
	end
	return nil
end

--[=[ Clears every slot whose entry `isKnown` rejects. Mutates and returns `slots`. ]=]
function Hotbar.Prune(slots: { string }, isKnown: (kind: Kind, id: string) -> boolean): { string }
	for index = 1, Hotbar.Size do
		local kind: Kind?, id: string? = Hotbar.Decode(slots[index] or "")
		if not kind or not id or not isKnown(kind, id) then
			slots[index] = ""
		end
	end
	return slots
end

return table.freeze(Hotbar)
