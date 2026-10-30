--!strict

--[=[
	Chat casting (docs/systems/combat.md): resolves a chat message to a spell the player knows.
	Matching ignores case, accents, punctuation and extra spaces. A message must be exactly the
	spell's name; skills with `chatArg` may follow the name with an argument (Gate: the zone).
	Only spells and dev skills cast from chat; text starting with `/` never matches, so chat
	commands keep working. Shared so the client predicts and the server decides with one rule.
]=]
local ChatCast = {}

--[=[ Longest message, in bytes, that may be sent as a chat cast. ]=]
ChatCast.MaxLength = 80

local FOLDS: { [string]: string } = {
	a = "ÀÁÂÃÄÅàáâãäåĀāĂăĄą",
	c = "ÇçĆćĈĉĊċČč",
	d = "ĎďĐđ",
	e = "ÈÉÊËèéêëĒēĔĕĖėĘęĚě",
	g = "ĜĝĞğĠġĢģ",
	h = "ĤĥĦħ",
	i = "ÌÍÎÏìíîïĨĩĪīĬĭĮįİı",
	j = "Ĵĵ",
	k = "Ķķ",
	l = "ĹĺĻļĽľĿŀŁł",
	n = "ÑñŃńŅņŇň",
	o = "ÒÓÔÕÖØòóôõöøŌōŎŏŐő",
	r = "ŔŕŖŗŘř",
	s = "ŚśŜŝŞşŠšß",
	t = "ŢţŤťŦŧ",
	u = "ÙÚÛÜùúûüŨũŪūŬŭŮůŰűŲų",
	w = "Ŵŵ",
	y = "ÝýÿŶŷŸ",
	z = "ŹźŻżŽž",
}

local fold: { [number]: string } = {}
for plain, accented in FOLDS do
	for _, codepoint in utf8.codes(accented) do
		fold[codepoint] = plain
	end
end

local CASTABLE_SOURCES = { Spell = true, Dev = true }

--[=[
	Lowercase, accent-free form of `text` with ASCII punctuation as spaces, runs of spaces
	collapsed and ends trimmed. Invalid UTF-8 gives "".
]=]
function ChatCast.Normalize(text: string): string
	if utf8.len(text) == nil then
		return ""
	end
	local parts = {}
	for _, codepoint in utf8.codes(text) do
		local folded = fold[codepoint]
		if folded then
			table.insert(parts, folded)
		elseif codepoint < 128 then
			local char = string.lower(string.char(codepoint))
			table.insert(parts, if string.match(char, "%w") then char else " ")
		else
			table.insert(parts, utf8.char(codepoint))
		end
	end
	local joined = string.gsub(table.concat(parts), "%s+", " ")
	return (string.match(joined, "^%s*(.-)%s*$") or "")
end

--[=[
	The skill in `known` a chat message casts, and its argument (normalized) for `chatArg`
	skills, or nil when the message is ordinary chat. The longest matching name wins.
]=]
function ChatCast.Resolve(text: string, known: { string }, skillsById: { [string]: any }): (string?, string?)
	if #text == 0 or #text > ChatCast.MaxLength or string.sub(text, 1, 1) == "/" then
		return nil, nil
	end
	local message = ChatCast.Normalize(text)
	if message == "" then
		return nil, nil
	end
	local bestId: string?, bestArg: string?, bestLength = nil, nil, 0
	for _, id in known do
		local skill = skillsById[id]
		if not skill or skill.kind ~= "Active" or not CASTABLE_SOURCES[skill.source] then
			continue
		end
		local name = ChatCast.Normalize(skill.name)
		if #name <= bestLength or name == "" then
			continue
		end
		if message == name then
			bestId, bestArg, bestLength = id, nil, #name
		elseif skill.chatArg and string.sub(message, 1, #name + 1) == name .. " " then
			bestId, bestArg, bestLength = id, string.sub(message, #name + 2), #name
		end
	end
	return bestId, bestArg
end

return table.freeze(ChatCast)
