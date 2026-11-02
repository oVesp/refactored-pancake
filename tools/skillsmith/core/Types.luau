--!strict

--[[
	SkillSmith contracts. Everything the framework shares between its modules lives here:
	what a module is, what a patch looks like, how diagnostics travel. Keeping these in one
	small file (and nothing else) is what lets modules stay independent of each other.
]]

local SkillSmithTypes = {}

--[=[ A span of source text, 1-based lines, inclusive. ]=]
export type Span = {
	startLine: number,
	endLine: number,
}

SkillSmithTypes.Span = Span

--[=[
	A single edit to one dataset file. The Patcher applies these by locating `entry` (the value of
	the `key` field inside a top-level list entry, e.g. id = "firebolt") and rewriting only the
	matched span, so comments, key order and indentation elsewhere survive untouched.
	- setKey: write `valueText` as the value of `field`, creating it after `anchor` when missing.
	- clearKey: remove the line(s) of `field` from the entry.
	- appendEntry: insert a whole new entry (rendered from `fields`) before the list's closing brace.
	- setMapValue / appendMapEntry: same idea for `{ [string]: ... }` maps such as BY_SKILL.
]=]
export type PatchKind = "setKey" | "clearKey" | "appendEntry" | "setMapValue" | "appendMapEntry"

export type Patch = {
	patchKind: PatchKind,
	-- Registry dataset name, e.g. "Skills" or "SkillSounds".
	dataset: string,
	-- Entry selector: value of the dataset's id key ("firebolt"), or a map key ("BY_SKILL.sleep").
	entry: string?,
	-- Field inside the entry being written (setKey/clearKey).
	field: string?,
	-- Rendered Luau literal, e.g. "0.68", "\"Firebolt\"", "{ swing = \"Fire\" }".
	valueText: string?,
	-- Insert after this existing key when the field is absent; defaults to end of entry.
	anchor: string?,
	-- For appendEntry: the full field list of the new entry, in order.
	fields: { { key: string, valueText: string } }?,
	reason: string?,
}

SkillSmithTypes.Patch = Patch

--[=[ Severity mirrors luau-lsp so the panel can sort with its output. ]=]
export type DiagnosticSeverity = "error" | "warning" | "info"

export type Diagnostic = {
	severity: DiagnosticSeverity,
	code: string,
	message: string,
	dataset: string?,
	entry: string?,
	field: string?,
}

SkillSmithTypes.Diagnostic = Diagnostic

--[=[
	Field metadata the editor renders from — produced by Schema from Types.luau, never hand-listed.
	kind: "number" | "integer" | "boolean" | "string" | "enum" | "record" | "list" | "amount" | "effects".
]=]
export type FieldSchema = {
	name: string,
	kind: string,
	required: boolean,
	enumValues: { string }?,
	doc: string?,
	-- For nested records (damage, cost, weaponAttack…): their own field list.
	fields: { FieldSchema }?,
	listItem: FieldSchema?,
}

SkillSmithTypes.FieldSchema = FieldSchema

--[=[ Timeline primitives shared by AnimTimeline, SoundPlacement and the view's canvas. ]=]
export type TimelineBar = {
	id: string,
	label: string,
	start: number,
	finish: number,
	color: Color3?,
	-- Field this bar edits when dragged, so the shell routes drops back through patches.
	field: string?,
}

export type TimelineMarker = {
	id: string,
	label: string,
	at: number,
	source: string?,
}

SkillSmithTypes.TimelineBar = TimelineBar
SkillSmithTypes.TimelineMarker = TimelineMarker

--[=[
	The module contract. A module touches the draft only through these functions; it never reaches
	into another module or into the view. `Available` lets optional integrations (VFX Forge, Eclipse)
	drop out cleanly when their plugin is not installed.
]=]
export type ModuleContext = {
	-- Read-only parsed project data: skills, schema, animations, sounds, vfx, classes…
	data: any,
	-- The skill currently open in the editor, as a mutable draft table.
	draft: { [string]: any },
	-- Extra datasets keyed by name for cross-reference dropdowns.
	crossRefs: { [string]: { any } },
}

export type SkillModule = {
	name: string,
	title: string,
	-- False when an optional third-party plugin is missing; the host hides the panel.
	available: ((ModuleContext) -> boolean)?,
	-- Fields this module owns in the form (subset of the schema; the shell renders the rest generically).
	fields: ((ModuleContext) -> { FieldSchema })?,
	-- Bars/markers this module contributes to the timeline canvas.
	timeline: ((ModuleContext) -> { bars: { TimelineBar }, markers: { TimelineMarker}, duration: number })?,
	-- Named buttons ("Draw hitbox", "Preview sound"); the host calls them with the live context.
	actions: ((ModuleContext) -> { { id: string, label: string, run: () -> () } })?,
	-- Rules checked on every keystroke; returned diagnostics block commits when severity == error.
	validate: ((ModuleContext) -> { Diagnostic })?,
	-- Patches that persist this module's fields for the current draft.
	patches: ((ModuleContext) -> { Patch })?,
}

SkillSmithTypes.SkillModule = SkillModule

--[=[ One parsed dataset entry plus the span it came from, so patches can find it again. ]=]
export type ParsedEntry = {
	key: string,
	values: { [string]: any },
	span: Span,
}

SkillSmithTypes.ParsedEntry = ParsedEntry

return SkillSmithTypes
