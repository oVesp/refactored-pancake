--!strict

local Factions = require(script.Parent.Parent.Content.Factions)

type FactionId = Factions.FactionId
type Standing = Factions.Standing

--[=[
	Standing between two factions from `Content/Factions` (docs/systems/open-world.md). Pure, so
	the server, the client and Lune tests share it.
]=]
local Relations = {}

local table_: { [string]: { [string]: Standing } } = {}
for _, entry in Factions.Relations do
	local a, b, standing = entry[1], entry[2], entry[3]
	table_[a] = table_[a] or {}
	table_[b] = table_[b] or {}
	table_[a][b] = standing
	table_[b][a] = standing
end

--[=[ Allied with itself; Neutral for any pair the table does not list. ]=]
function Relations.Standing(a: string, b: string): Standing
	if a == b then
		return "Allied"
	end
	local row = table_[a]
	return row and row[b] or "Neutral"
end

function Relations.Hostile(a: string, b: string): boolean
	return Relations.Standing(a, b) == "Hostile"
end

function Relations.Allied(a: string, b: string): boolean
	return Relations.Standing(a, b) == "Allied"
end

--[=[ True for factions hostile to players (kept out of safe zones). ]=]
function Relations.IsMonster(faction: string): boolean
	local def = (Factions.ById :: any)[faction]
	return def ~= nil and def.monster
end

return Relations
