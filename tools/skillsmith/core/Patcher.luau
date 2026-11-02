--!strict

--[[
	Surgical text patches. A patch changes exactly one span of one dataset file: the value of a key
	inside an entry block, the removal of a key line, a new entry before the list's closing brace, or
	a map key inside a named local map. Everything outside the matched span — tabs, comments, key
	order, the rest of the file — survives byte for byte, which is what lets generated files stay
	stylua-clean and reviewable in `git diff`. The Patcher never evaluates code and never rewrites a
	file it cannot find the target span in; it errors instead of guessing.
]]

local Types = require(script.Parent.Types)
local Parser = require(script.Parent.Parser)
local Registry = require(script.Parent.Registry)

local Patcher = {}

-- Lune 0.11 parses single-expression type syntax conservatively, so multi-value return types go
-- through a named alias here instead of `(number, number)?` inline.
type SpanPair = { start: number, finish: number }

-- Finds the inclusive character range of `field = <value>` within the entry's source slice.
-- Returns nil when the key is absent (the caller then inserts after an anchor).
local function findValueSpan(entrySource: string, field: string): SpanPair?
	-- Value starts after `field =` and runs to the top-level comma or the closing brace.
	local searchFrom = 1
	while true do
		local s = string.find(entrySource, `{field} =`, searchFrom, true)
		if not s then
			return nil
		end
		-- Must be a real key position: preceded by newline+tabs, not part of a longer identifier.
		local prevChar = string.sub(entrySource, s - 1, s - 1)
		local nextChar = string.sub(entrySource, s + #field + 2, s + #field + 2)
		if (prevChar == "\n" or prevChar == "{" or s == 1) and (nextChar == " " or nextChar == "\t") then
			local valueStart = s + #field + 2
			while true do
				local ch = string.sub(entrySource, valueStart, valueStart)
				if ch ~= " " and ch ~= "\t" then
					break
				end
				valueStart += 1
			end
			-- Walk to the end of the value at brace/quote depth zero.
			local i = valueStart
			local depth = 0
			local quote: string? = nil
			local len = #entrySource
			while i <= len do
				local c = string.sub(entrySource, i, i)
				if quote then
					if c == "\\" then
						i += 2
						continue
					elseif c == quote then
						quote = nil
					end
				elseif c == "\"" or c == "'" then
					quote = c
				elseif c == "{" or c == "[" then
					depth += 1
				elseif c == "}" or c == "]" then
					if depth == 0 then
						break -- reached the entry's closing brace
					end
					depth -= 1
				elseif c == "," and depth == 0 then
					break
				end
				i += 1
			end
			return s, i - 1
		end
		searchFrom = s + 1
	end
end

Patcher.findValueSpan = findValueSpan

-- Renders Luau data as a literal for writing into content files (inverse of Parser.parseValue for
-- the shapes Content uses). Numbers keep enough precision; strings escape quotes.
function Patcher.render(value: any): string
	if type(value) == "number" then
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return string.format("%.10g", value)
	elseif type(value) == "boolean" then
		return tostring(value)
	elseif type(value) == "string" then
		local escaped = (value:gsub("\\", "\\\\"):gsub("\"", "\\\""))
		return `"{escaped}"`
	elseif type(value) == "table" then
		if value.__raw then
			return value.__raw
		end
		local parts = {}
		local arrayOnly = true
		for k in pairs(value) do
			if type(k) ~= "number" then
				arrayOnly = false
				break
			end
		end
		if arrayOnly and #value > 0 then
			for _, item in value do
				table.insert(parts, Patcher.render(item))
			end
			return `{ {table.concat(parts, ", ")} }`:gsub("{ %{", "{"):gsub("%} }", "}")
		end
		local keys = {}
		for k in pairs(value) do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		for _, k in keys do
			table.insert(parts, `{k} = {Patcher.render(value[k])}`)
		end
		return `{ {table.concat(parts, ", ")} }`
	end
	error(`Patcher cannot render {type(value)}`)
end

-- Locates the character range of an entry block ("{ ... }") whose id equals `key`.
local function entryRange(source: string, key: string): (number, number)?
	local marker = string.find(source, `id = "{key}"`, 1, true)
	if not marker then
		return nil
	end
	-- Scan back to the opening brace of this entry: the nearest preceding "{" that begins a line.
	local open: number? = nil
	local i = marker
	while i > 0 do
		local ch = string.sub(source, i, i)
		if ch == "{" then
			local lineStart = string.len(string.match(string.sub(source, 1, i), "^[\n]*[^\n]*$") or "")
			local before = string.sub(source, lineStart + 1, i - 1)
			if string.match(before, "^%s*$") then
				open = i
				break
			end
		elseif ch == "\n" then
			-- Stop if we crossed a line that is not blank/comment and not part of this entry.
		end
		i -= 1
	end
	if not open then
		return nil
	end
	local close = Parser.matchBrace(source, open)
	if not close then
		return nil
	end
	return open, close
end

--[=[
	Applies one patch to a file's text, returning the new text. Raises when the target cannot be
	found precisely — an error here means the editor and the repo disagree, and silently writing
	somewhere else would corrupt content.
]=]
function Patcher.applyOne(source: string, patch: Types.Patch): string
	if patch.patchKind == "setKey" or patch.patchKind == "clearKey" then
		assert(patch.entry and patch.field, "setKey/clearKey need entry and field")
		local range = entryRange(source, patch.entry)
		assert(range, `Entry {patch.entry} not found`)
		local openPos, closePos = range[1], range[2]
		local block = string.sub(source, openPos, closePos)
		local span = findValueSpan(block, patch.field)
		if patch.patchKind == "clearKey" then
			assert(span, `Field {patch.field} absent in {patch.entry}; nothing to clear`)
			local s, e = span[1], span[2]
			-- Include the trailing comma and the line break so no empty line remains.
			local afterE = string.sub(block, e + 1, e + 1)
			if afterE == "," then
				e += 1
			end
			local lineStart = s
			while lineStart > 1 and string.sub(block, lineStart - 1, lineStart - 1) ~= "\n" do
				lineStart -= 1
			end
			local tail = string.sub(block, e + 1)
			if string.match(tail, "^%s*\n") then
				e += select(2, string.gsub(string.match(tail, "^[%s]*\n"), "", ""))
			end
			local removed = string.sub(block, lineStart, e)
			if string.match(removed, "^%s+$") then
				removed = removed
			end
			block = string.sub(block, 1, lineStart - 1) .. string.sub(block, e + 1)
			return string.sub(source, 1, openPos - 1) .. block .. string.sub(source, closePos + 1)
		end

		assert(patch.valueText, "setKey needs valueText")
		if span then
			local s, e = span[1], span[2]
			local head = string.sub(block, 1, s - 1)
			local tail = string.sub(block, e + 1)
			-- Replace only the value portion: from after `field =` whitespace to e.
			local eqEnd = string.find(head, "=", s - #patch.field - 4, true) or #head
			local valueStartInHead = #head
			while valueStartInHead > eqEnd and string.sub(head, valueStartInHead, valueStartInHead):match("^%s$") do
				valueStartInHead -= 1
			end
			valueStartInHead += 1
			local newBlock = string.sub(head, 1, valueStartInHead - 1) .. patch.valueText .. tail
			return string.sub(source, 1, openPos - 1) .. newBlock .. string.sub(source, closePos + 1)
		end

		-- Key absent: insert after the anchor (or first key when no anchor given).
		local anchor = patch.anchor
		local insertAfterKey = anchor or "name"
		local spanAnchor = findValueSpan(block, insertAfterKey)
		if not spanAnchor then
			-- Anchor missing too: append before the closing brace of the entry.
			local closeIdx = #block
			local indent = string.rep("\t", 3)
			local line = `\n{indent}{patch.field} = {patch.valueText},`
			-- Match the indentation of the last key line instead of assuming.
			local lines = string.split(block, "\n")
			for j = #lines, 1, -1 do
				local m = string.match(lines[j], "^(%s+)[%a_]+ =")
				if m then
					line = `\n{m}{patch.field} = {patch.valueText},`
					break
				end
			end
			block = string.sub(block, 1, closeIdx - 1) .. line .. string.sub(block, closeIdx)
			return string.sub(source, 1, openPos - 1) .. block .. string.sub(source, closePos + 1)
		end
		local _, e = spanAnchor[1], spanAnchor[2]
		-- Move past the comma and end-of-line.
		local insertAt = e + 1
		while string.sub(block, insertAt, insertAt) ~= "\n" and insertAt <= #block do
			insertAt += 1
		end
		local indentMatch: string? = nil
		local lines = string.split(block, "\n")
		for _, line in lines do
			local m = string.match(line, "^(%s+)" .. (patch.field ~= nil and "%a" or "%a") .. "[%w_]* =")
			if m then
				indentMatch = m
				break
			end
		end
		local indent = indentMatch or string.rep("\t", 3)
		local insertion = `\n{indent}{patch.field} = {patch.valueText},`
		block = string.sub(block, 1, insertAt - 1) .. insertion .. string.sub(block, insertAt)
		return string.sub(source, 1, openPos - 1) .. block .. string.sub(source, closePos + 1)
	elseif patch.patchKind == "appendEntry" then
		assert(patch.fields and #patch.fields > 0, "appendEntry needs fields")
		-- Insert before the closing brace of the top-level list: find the list opener first.
		local listOpen = string.find(source, "=%s*{\n", 1)
		assert(listOpen, "No list assignment found")
		local close = Parser.matchBrace(source, string.find(source, "{", listOpen, true) :: number)
		assert(close, "Unbalanced list braces")
		local lines = string.split(source, "\n")
		local closeLine = Parser.lineOf(source, close)
		local entryIndent = "\t"
		local keyIndent = "\t\t"
		local rendered = {}
		table.insert(rendered, `{entryIndent}{{`)
		for _, pair in patch.fields :: { { key: string, valueText: string } } do
			table.insert(rendered, `{keyIndent}{pair.key} = {pair.valueText},`)
		end
		table.insert(rendered, `{entryIndent}}},`)
		local insertPos = 0
		for l = 1, closeLine - 1 do
			insertPos += #(lines[l] .. "\n")
		end
		-- Skip trailing blank lines right above the closer.
		while closeLine - 1 >= 1 and string.match(lines[closeLine - 1], "^%s*$") do
			closeLine -= 1
			insertPos -= #(lines[closeLine + 1] .. "\n")
		end
		local chunk = table.concat(rendered, "\n")
		return string.sub(source, 1, insertPos) .. chunk .. "\n" .. string.sub(source, insertPos + 1)
	elseif patch.patchKind == "setMapValue" or patch.patchKind == "appendMapEntry" then
		assert(patch.entry and patch.valueText, "map patches need entry and valueText")
		local dataset = Registry.datasets[patch.dataset]
		assert(dataset and dataset.selector, `Patch dataset {patch.dataset} is not a map`)
		local decl = string.find(source, `local {dataset.selector}`)
		assert(decl, `Map {dataset.selector} not found in {dataset.path}`)
		local open = string.find(source, "{", decl, true)
		assert(open, "Map has no opening brace")
		local close = Parser.matchBrace(source, open :: number)
		assert(close, "Unbalanced map braces")
		local body = string.sub(source, open + 1, close - 1)
		local key = patch.entry
		-- Existing key on its own line (bare or quoted)?
		local s = string.find(body, `\n%s*["']?{key}["']?%s*=%s*`)
		if patch.patchKind == "setMapValue" then
			assert(s, `Map key {key} absent; use appendMapEntry`)
			local valueStart = s + (string.find(string.sub(body, s, s + 200), "=", 1, true) or 0)
			while string.sub(body, valueStart, valueStart):match("^%s$") do
				valueStart += 1
			end
			local i = valueStart
			local depth = 0
			local quote: string? = nil
			while i <= #body do
				local c = string.sub(body, i, i)
				if quote then
					if c == "\\" then
						i += 2
						continue
					elseif c == quote then
						quote = nil
					end
				elseif c == "\"" or c == "'" then
					quote = c
				elseif c == "{" then
					depth += 1
				elseif c == "}" then
					if depth == 0 then
						break
					end
					depth -= 1
				elseif c == "," and depth == 0 then
					break
				end
				i += 1
			end
			local newBody = string.sub(body, 1, valueStart - 1) .. patch.valueText .. string.sub(body, i)
			return string.sub(source, 1, open) .. newBody .. string.sub(source, close)
		else
			assert(not s, `Map key {key} already present`)
			-- Append before the map's closing brace, matching the last entry's indentation.
			local bodyLines = string.split(body, "\n")
			local indent = "\t"
			for j = #bodyLines, 1, -1 do
				local m = string.match(bodyLines[j], "^(%s+)%a")
				if m then
					indent = m
					break
				end
			end
			local trimmedBody = body:gsub("%s+$", "")
			local newBody = `{trimmedBody}\n{indent}{key} = {patch.valueText},`
			return string.sub(source, 1, open) .. newBody .. string.sub(source, close)
		end
	end
	error(`Unknown patch kind {patch.patchKind}`)
end

--[=[ Applies a bundle against a { path = text } table, returning { path = newText }. ]=]
function Patcher.applyBundle(sources: { [string]: string }, bundle: { Types.Patch }): { [string]: string }
	local result = {}
	for path, text in sources do
		result[path] = text
	end
	for _, patch in bundle do
		local dataset = Registry.datasets[patch.dataset]
		assert(dataset, `Patch references unknown dataset {patch.dataset}`)
		assert(dataset.writable, `Dataset {patch.dataset} is read-only`)
		local source = result[dataset.path]
		assert(source, `File not loaded: {dataset.path}`)
		result[dataset.path] = Patcher.applyOne(source, patch)
	end
	return result
end

return Patcher
