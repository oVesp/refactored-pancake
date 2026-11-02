--!strict

return table.freeze({
	--[=[ Attribute names replicated on characters for display state (game-design.md 5.4). ]=]
	Attributes = table.freeze({
		Hp = "Hp",
		MaxHp = "MaxHp",
		Mp = "Mp",
		MaxMp = "MaxMp",
		Focus = "Focus",
		MaxFocus = "MaxFocus",
		--[=[ Hunger and thirst live on the Player, not the character, so they survive respawn. ]=]
		Hunger = "Hunger",
		Thirst = "Thirst",
	}),

	--[=[ Name of the folder in ReplicatedStorage that holds every remote. ]=]
	RemotesFolderName = "Remotes",

	--[=[ Seconds a client waits for server-created instances before reporting an error. ]=]
	ClientWaitTimeout = 30,
})
