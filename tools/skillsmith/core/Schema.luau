--!strict

--[[
	Extracts editor field metadata from `src/ReplicatedStorage/Content/Types.luau` by reading its
	source text. The SkillDef record is the schema: every field, whether it is optional (`?`), which
	strings an enum allows, and what its `--[=[ ]=]` doc comment says. Nothing here re-declares those
	facts, so a Types.luau edit reaches the editor with no second place to update.
]]

local Types = require(script.Parent.Types)

local Schema = {}

local SKILL_RECORD = "SkillDef"

-- Splits a record body into `{ name, typeText }` pairs at top-level commas (nested braces/parens
-- and string literals do not split). Mirrors Parser.splitTop but keeps `name : type` halves.
local function splitFields(body: string): { { name: string, typeText: string } }
	local parts = {}
	local depth = 0
	local quote: string? = nil
	local start = 1
	local i = 1
	local len = #body
	while i <= len do
		local ch = string.sub(body, i, i)
		if quote then
			if ch == "\\" then
				i += 2
				continue
			elseif ch == quote then
				quote = nil
			end
		elseif ch == "\"" or ch == "'" then
			quote = ch
		elseif ch == "{" or ch == "[" or ch == "(" then
			depth += 1
		elseif ch == "}" or ch == "]" or ch == ")" then
			depth -= 1
		elseif ch == "," and depth == 0 then
			table.insert(parts, string.sub(body, start, i - 1))
			start = i + 1
		end
		i += 1
	end
	if string.gsub(string.sub(body, start), "^%s+", "") ~= "" then
		table.insert(parts, string.sub(body, start))
	end

	local fields = {}
	for _, part in parts do
		local p = part:gsub("^%s+", ""):gsub("%s+$", "")
		local name, rest = p:match("^(%a[%w_]*)%s*:%s*(.+)$")
		if name and rest then
			table.insert(fields, { name = name, typeText = rest })
		end
	end
	return fields
end

-- Returns the body of `export type Name = { ... }`, or nil when absent.
local function recordBody(src: string, name: string): string?
	local decl = string.find(src, `export type {name} =`)
	if not decl then
		return nil
	end
	local open = string.find(src, "{", decl, true)
	if not open then
		return nil
	end
	local depth = 0
	local i = open
	local len = #src
	while i <= len do
		local ch = string.sub(src, i, i)
		if ch == "{" then
			depth += 1
		elseif ch == "}" then
			depth -= 1
			if depth == 0 then
				return string.sub(src, open + 1, i - 1)
			end
		end
		i += 1
	end
	return nil
end

-- Doc comment lines immediately above a field line, joined. `--[=[` blocks and `--` runs both count.
local function docsAbove(lines: { string }, fieldLine: number): string?
	local collected: { string } = {}
	local j = fieldLine - 1
	while j >= 1 do
		local trimmed = string.match(lines[j], "^%s*(.-)%s*$") or ""
		if trimmed == "" then
			if #collected > 0 then
				break
			end
		elseif trimmed:match("^%]=%]$") then
			-- End of a block comment; walk back to its opener.
			j -= 1
			continue
		elseif trimmed:match("^%-%-") then
			local text = (trimmed:gsub("^%-%-=?", ""):gsub("^%[(=*)%[", ""):gsub("%]%s*$", ""))
			text = (text:gsub("^%s+", ""):gsub("%s+$", ""))
			table.insert(collected, 1, text)
			if trimmed:match("^%-%-[^%-]") or trimmed:match("^%-%-$") then
				break -- plain line comment: only one line belongs to the field
			end
		else
			break
		end
		j -= 1
	end
	if #collected == 0 then
		return nil
	end
	return table.concat(collected, " ")
end

-- `"Melee" | "Target"` style unions -> {"Melee", "Target"}; nil for anything else.
local function enumValues(typeText: string): { string }?
	local withoutOptional = typeText:gsub("%?$", ""):gsub("^%((.*)%)$", "%1")
	local quoted = {}
	local rest = withoutOptional
	while true do
		local q = string.match(rest, '"(.-)"')
		if not q then
			break
		end
		table.insert(quoted, q)
		local finish = string.find(rest, '"' .. q .. '"', 1, true) :: number
		rest = string.sub(rest, finish + #q + 2)
		if not rest:match("^%s*|") then
			break
		end
		rest = rest:gsub("^%s*|%s*", "")
	end
	if #quoted < 2 then
		return nil
	end
	return quoted
end

local namedEnums: { [string]: boolean } = {
	Delivery = true,
	DamageType = true,
	StatName = true,
}

-- Maps a raw type text onto a FieldSchema kind plus extras. Handles the shapes Types.luau uses.
local function classify(name: string, typeText: string, src: string): Types.FieldSchema
	local text = typeText:gsub("%s+", "")
	local required = not text:match("%?$")
	local core = text:gsub("%?$", "")

	local out: Types.FieldSchema = { name = name, kind = "string", required = required }

	-- Named alias (Delivery?, DamageType?, StatBlock?) -> resolve once.
	local alias = core:match("^%a[%w_]*$")
	if alias and namedEnums[alias] then
		local decl = string.find(src, `export type {alias} =`)
		local union = if decl then string.sub(src, decl + #(`export type {alias} =`), (string.find(src, "\n\n", decl) or #src + 1) - 1) else nil
		local values = if union then enumValues(union:gsub("\n", " ")) else nil
		out.kind = "enum"
		out.enumValues = values
		return out
	elseif alias == "StatBlock" then
		out.kind = "record"
		out.fields = { { name = "value", kind = "number", required = true } }
		return out
	elseif alias == "Amount" then
		local body = recordBody(src, "Amount")
		out.kind = "amount"
		out.fields = if body then Schema.fieldsFromRecord(src, "Amount") else nil
		return out
	elseif alias == "Effect" then
		out.kind = "effects"
		out.fields = Schema.fieldsFromRecord(src, "Effect")
		return out
	end

	-- Inline union: ("Enemy" | "Ally" | "Self")? or "Active" | "Passive".
	local values = enumValues(core)
	if values then
		out.kind = "enum"
		out.enumValues = values
		return out
	end

	-- Intersection: (Amount & { type: string })? — damage.
	if core:match("^%(.+&.+%)$") then
		out.kind = "amount"
		out.fields = Schema.fieldsFromRecord(src, "Amount")
		return out
	end

	-- Array of records or strings: { Effect }, { string }.
	local arrayItem = core:match("^%{(.+)%}$")
	if arrayItem then
		out.kind = "list"
		local item = arrayItem:gsub("%s+", "")
		if item == "string" then
			out.listItem = { name = name, kind = "string", required = true }
		elseif item:match("^%a") and item:match("Effect$") then
			out.listItem = { name = name, kind = "effects", required = true, fields = Schema.fieldsFromRecord(src, "Effect") }
		else
			out.listItem = { name = name, kind = "record", required = true }
		end
		return out
	end

	-- Inline record: { resource: "Mp" | "Stamina", amount: number }.
	if core:match("^%{") then
		local body = core:sub(2, -2)
		out.kind = "record"
		local children = {}
		for _, pair in splitFields(body) do
			local child = classify(pair.name, pair.typeText, src)
			child.doc = nil
			table.insert(children, child)
		end
		out.fields = children
		return out
	end

	if core == "number" then
		out.kind = "number"
	elseif core == "boolean" then
		out.kind = "boolean"
	elseif core == "string" then
		out.kind = "string"
	else
		out.kind = "record"
	end
	return out
end

--[=[ Parses one `export type Name = { ... }` record into field schemas, docs included. ]=]
function Schema.fieldsFromRecord(src: string, recordName: string): { Types.FieldSchema }?
	local body = recordBody(src, recordName)
	if not body then
		return nil
	end
	local stripped = body
	-- Keep the doc comments: they are read per line below, so work from the original body lines.
	local lines = string.split(stripped, "\n")
	local result: { Types.FieldSchema } = {}
	local offsetInSrc = 0 -- unused; docs are found directly in the body lines
	for index, line in lines do
		local trimmed = string.match(line, "^%s*(.-)%s*$") or ""
		local fieldName = trimmed:match("^(%a[%w_]*)%s*:")
		if fieldName and not trimmed:match("^%-%-") then
			-- Collect the full type text: unions and records can span several source lines.
			local typeText = trimmed:sub(#fieldName + 2)
			local finish = index
			local balance = (select(2, typeText:gsub("{", "{")) - select(2, typeText:gsub("}", "}")))
				+ (select(2, typeText:gsub("%(", "%(")) - select(2, typeText:gsub("%)", "%)")))
			while balance > 0 and finish < #lines do
				finish += 1
				typeText = typeText .. " " .. lines[finish]
				balance = (select(2, typeText:gsub("{", "{")) - select(2, typeText:gsub("}", "}")))
					+ (select(2, typeText:gsub("%(", "%(")) - select(2, typeText:gsub("%)", "%)")))
			end
			local field = classify(fieldName, typeText, src)
			field.doc = docsAbove(lines, index)
			table.insert(result, field)
		end
	end
	return result
end

--[=[ Full editor schema for skills, read from the Types.luau source text. ]=]
function Schema.skillFields(typesSource: string): { Types.FieldSchema }
	local fields = Schema.fieldsFromRecord(typesSource, SKILL_RECORD)
	return fields or {}
end

--[=[ Convenience lookup: name -> schema, including nested record children at the top level only. ]=]
function Schema.byName(fields: { Types.FieldSchema }): { [string]: Types.FieldSchema }
	local map: { [string]: Types.FieldSchema } = {}
	for _, field in fields do
		map[field.name] = field
	end
	return map
end

--[=[ Serialises the schema to JSON for tools outside Luau (the web view, CI diffing). ]=]
function Schema.toJson(fields: { Types.FieldSchema }): string
	local function esc(s: string): string
		return (s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\t", "    "))
	end
	local encodeField

	encodeField = function(field: Types.FieldSchema): string
		local parts = {
			`"name": "{esc(field.name)}"`,
			`"kind": "{field.kind}"`,
			`"required": {if field.required then "true" else "false"}`,
		}
		if field.doc then
			table.insert(parts, `"doc": "{esc(field.doc)}"`)
		end
		if field.enumValues then
			local quoted = {}
			for _, v in field.enumValues do
				table.insert(quoted, `"{esc(v)}"`)
			end
			table.insert(parts, `"enumValues": [{table.concat(quoted, ", ")}]`)
		end
		if field.fields then
			local encoded = {}
			for _, child in field.fields do
				table.insert(encoded, encodeField(child))
			end
			table.insert(parts, `"fields": [{table.concat(encoded, ", ")}]`)
		end
		if field.listItem then
			table.insert(parts, `"listItem": {encodeField(field.listItem)}`)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end

	local encoded = {}
	for _, field in fields do
		table.insert(encoded, encodeField(field))
	end
	return "[\n\t" .. table.concat(encoded, ",\n\t") .. "\n]"
end

return Schema
