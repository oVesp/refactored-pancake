--!strict

--[=[
	Player-facing message templates keyed by id. Server sends keys and arguments; the client
	formats. This table is the single source to move into a LocalizationTable later.
]=]
return table.freeze({
	LevelUp = "Level %d! Visit a trainer to spend your level.",
	Trained = "%s is now level %d.",
	NoUnspentLevel = "No unspent level. Earn XP to level up.",
	ClassCapped = "That class is at its cap.",
	UnknownClass = "Unknown class.",
	LearnedSpell = "Learned %s.",
	SpellPickReady = "You can learn %d new spell(s). Open the spellbook (B).",
	TierLocked = "That spell's Tier is still locked.",
	NoPick = "No spell pick left for that class.",
	NotOnClassList = "None of your classes teaches that spell.",
	AlreadyKnown = "Already known.",
	UnknownSpell = "Unknown spell.",
	LearnedDiscipline = "Learned the Discipline %s.",
	DisciplinesKnown = "You already know every Discipline taught here.",
	NoFocus = "Not enough Focus capacity.",
	InventoryFull = "Inventory full.",
	Died = "You were defeated. XP debt: %d.",
	VendorClosed = "The vendor is closed in this build.",
	Kindled = "The brazier catches fire.",
	Purified = "The water runs clear.",
	EnteredZone = "%s (%s)",
	CastNoResource = "Not enough resource to finish the cast.",
	DevOnly = "Dev command refused.",
	DevDone = "%s",
	BadLook = "That look is not available.",
	BadCreation = "The character could not be created.",
	HeritageLocked = "That race is not available yet.",
	BadName = "Pick a name from the list.",
	NeedSpell = "Choose a starting spell.",
})
