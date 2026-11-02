--!strict

--[[
	Lenient Luau table reader. Reads the *source text* of content modules (they are plain data with
	`--[=[ ]=]` doc comments and inline comments) without a sourcemap, so it runs under Lune on disk
	and inside Studio on synced scripts alike. It understands exactly the shapes Content files use:
	lists of record entries, maps keyed by bare names or strings, nested braces, and `table.freeze`.
	It never evaluates code — no require, no function calls beyond stripping table.freeze(...).
]]

local Parser = {}

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

Parser.trim = trim

-- Strips --[=[ ]=] blocks, --[[ ]] blocks and -- line comments outside string literals.
function Parser.stripComments(src: string): string
	local out = {}
	local i = 1
	local len = #src
	while i <= len do
		local two = string.sub(src, i, i + 1)
		if two == "--" then
			-- Comment; skip to end (block comments can contain anything but their terminator).
			local b1, b2 = string.sub(src, i, i + 3), string.sub(src, i, i + 4)
			if b1 == "--[=[" then
				local finish = string.find(src, "]=]", i + 4, true)
				i = if finish then finish + 3 else len + 1
			elseif b2 == "--[==" or b1 == "--[==" then
				local finish = string.find(src, "]]", i + 4, true)
				i = if finish then finish + 2 else len + 1
			else
				local finish = string.find(src, "\n", i, true)
				i = if finish then finish else len + 1
			end
		elseif two == "\"\"" or two == "''" then
			table.insert(out, two)
			i += 2
		elseif two == "[[" then
			local finish = string.find(src, "]]", i + 2, true)
			if finish then
				table.insert(out, string.sub(src, i, finish + 1))
				i = finish + 2
			else
				table.insert(out, string.sub(src, i)); break
			end
		else
			table.insert(out, string.sub(src, i, i))
			i += 1
		end
	end
	return table.concat(out)
end

-- Splits `inner` (text between matching braces/brackets, already stripped of them) at top-level commas.
function Parser.splitTop(inner: string): { string }
	local parts = {}
	local depth = 0
	local quote: string? = nil
	local start = 1
	local i = 1
	local len = #inner
	while i <= len do
		local ch = string.sub(inner, i, i)
		if quote then
			if ch == "\\" then
				i += 2
				continue
			elseif ch == quote then
				quote = nil
			end
		elseif ch == "\"" or ch == "'" then
			quote = ch
		elseif ch == "{" or ch == "[" then
			depth += 1
		elseif ch == "}" or ch == "]" then
			depth -= 1
		elseif ch == "," and depth == 0 then
			table.insert(parts, string.sub(inner, start, i - 1))
			start = i + 1
		end
		i += 1
	end
	local tail = string.sub(inner, start)
	if trim(tail) ~= "" then
		table.insert(parts, tail)
	end
	return parts
end

-- Returns the index just past a balanced brace group starting at `open`, or nil.
local function matchBrace(src: string, open: number): number?
	local depth = 0
	local i = open
	local len = #src
	local quote: string? = nil
	while i <= len do
		local ch = string.sub(src, i, i)
		if quote then
			if ch == "\\" then
				i += 2
				continue
			elseif ch == quote then
				quote = nil
			end
		elseif ch == "\"" or ch == "'" then
			quote = ch
		elseif ch == "{" then
			depth += 1
		elseif ch == "}" then
			depth -= 1
			if depth == 0 then
				return i
			end
		end
		i += 1
	end
	return nil
end

Parser.matchBrace = matchBrace

local function lineOf(src: string, pos: number): number
	local _, n = string.sub(src, 1, pos):gsub("\n", "\n")
	return n + 1
end

Parser.lineOf = lineOf

--[=[ Parses one literal value into Lua data (numbers, booleans, strings, nested tables, arrays). ]=]
function Parser.parseValue(text: string): any
	local t = trim(text)
	-- table.freeze(...) wrapper
	local inner = t:match("^table%.freeze%((.*)%)${'$'}")
	if inner then
		return Parser.parseValue(trim(inner))
	end
	if t == "true" then
		return true
	elseif t == "false" then
		return false
	elseif t == "nil" then
		return nil
	end
	local num = tonumber(t)
	if num then
		return num
	end
	local str = t:match('^"(.*)"$') or t:match("^'(.*)'$")
	if str then
		return (str:gsub("\\\"", "\""):gsub("\\\\", "\\"))
	end
	if t:match("^%{") and t:match("}$") then
		local body = t:sub(2, -2)
		local result = {}
		local arrayIdx = 1
		for _, part in Parser.splitTop(body) do
			local p = trim(part)
			if p == "" then
				continue
			end
			local key, value = p:match("^%[\"?(%w+)\"?%]%s*=%s*(.+)$")
			if not key then
				key, value = p:match("^(%a[%w_]*)%s*=%s*(.+)$")
			end
			if key and value then
				result[key] = Parser.parseValue(value)
			else
				result[arrayIdx] = Parser.parseValue(p)
				arrayIdx += 1
			end
		end
		return result
	end
	-- Unparseable (function call, complex expression): keep raw text so round-trips don't lose it.
	return { __raw = t }
end

--[=[
	Parses `{ ... }` list-of-entries source into ordered entries. `idKey` names the field that
	uniquely identifies an entry ("id"). Each entry keeps its source span for the Patcher.
	Returns { entries = { { key, values, span } }, byId = { [string] = entry } }.
]=]
function Parser.parseEntryList(src: string, idKey: string): { entries: { [string]: any }, byId: { [string]: any } }
	local clean = Parser.stripComments(src)
	local entries: { [string]: any } = {}
	local byId: { [string]: any } = {}
	-- Find the outermost `local list ... = {` if present, else the first top-level brace.
	local open = clean:find("{", 1, true)
	if not open then
		return { entries = entries, byId = byId }
	end
	local close = matchBrace(clean, open)
	if not close then
		return { entries = entries, byId = byId }
	end
	local body = clean:sub(open + 1, close - 1)
	for _, part in Parser.splitTop(body) do
		local p = trim(part)
		if p:match("^%{") and p:match("}$") then
			local values = Parser.parseValue(p) :: { [string]: any }
			local key = tostring(values[idKey] or "")
			if key ~= "" then
				local absStart = string.find(src, `{idKey} = "{key}"`, 1, true)
				local startLine = if absStart then lineOf(src, absStart) else 0
				-- Entry block starts at the brace before the id line; approximate generously by
				-- scanning back from the id line to the nearest line ending in `{`.
				local lines = string.split(src, "\n")
				local blockStart = startLine
				for j = startLine, 1, -1 do
					if string.match(lines[j], "^%s*{%s*$") then
						blockStart = j
						break
					end
				end
				local blockEnd = startLine
				local depth = 0
				for j = blockStart, #lines do
					depth += select(2, lines[j]:gsub("{", "{"))
					depth -= select(2, lines[j]:gsub("}", "}"))
					if depth <= 0 and j > blockStart then
						blockEnd = j
						break
					end
				end
				local entry = {
					key = key,
					values = values,
					span = { startLine = blockStart, endLine = blockEnd },
				}
				table.insert(entries, entry)
				byId[key] = entry
			end
		end
	end
	return { entries = entries, byId = byId }
end

--[=[
	Parses a map literal assigned to a local (`local BY_SKILL: {...} = { strike = PUNCH, ... }`)
	into { [key] = parsedValue }. Bare keys allowed, as Content files use them.
]=]
function Parser.parseMap(src: string, localName: string): { [string]: any }
	local clean = Parser.stripComments(src)
	local decl = string.find(clean, `local {localName}`)
	if not decl then
		return {}
	end
	local open = string.find(clean, "{", decl, true)
	if not open then
		return {}
	end
	local close = matchBrace(clean, open)
	if not close then
		return {}
	end
	local result: { [string]: any } = {}
	for _, part in Parser.splitTop(clean:sub(open + 1, close - 1)) do
		local p = trim(part)
		local key, value = p:match('^%[?"?([%w_]+)"?%?%]%s*=%s*(.+)$')
		if not key then
			key, value = p:match("^(%a[%w_]*)%s*=%s*(.+)$")
		end
		if key and value then
			local resolved = value
			-- Resolve local aliases used in SkillSounds (strike = PUNCH).
			local alias = trim(value):match("^%a[%w_]*$")
			if alias and alias ~= "true" and alias ~= "false" then
				local tblDecl = string.find(clean, `local {alias}`)
				if tblDecl then
					local ao = string.find(clean, "{", tblDecl, true)
					local ac = if ao then matchBrace(clean, ao) else nil
					if ao and ac then
						resolved = clean:sub(ao, ac)
					end
				end
			end
			result[key] = Parser.parseValue(resolved)
		end
	end
	return result
end

return Parser
