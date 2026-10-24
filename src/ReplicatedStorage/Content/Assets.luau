--!strict

export type AudioAsset = {
	id: string,
	volume: number,
	looped: boolean?,
}

--[=[
	Asset manifest (game-design.md 7.3): the only place asset ids live. Every key has a row in
	content/register.json (origin, license, review state). Audio comes from the Creator Store
	while upload quota is limited (game-design.md 7.5).
]=]
local Audio: { [string]: AudioAsset } = {
	Swing = { id = "rbxassetid://134671877618939", volume = 0.5 },
	Hit = { id = "rbxassetid://126976659766267", volume = 0.6 },
	Fire = { id = "rbxassetid://9114446852", volume = 0.5 },
	Zap = { id = "rbxassetid://9114277757", volume = 0.45 },
	Heal = { id = "rbxassetid://9116394545", volume = 0.5 },
	LevelUp = { id = "rbxassetid://9116395085", volume = 0.6 },
	GoblinBark = { id = "rbxassetid://9125475729", volume = 0.5 },
	UiClick = { id = "rbxassetid://9119717529", volume = 0.4 },
	VillageAmbience = { id = "rbxassetid://9112835056", volume = 0.25, looped = true },
	FieldMusic = { id = "rbxassetid://1842008726", volume = 0.2, looped = true },
}

return table.freeze({
	Audio = table.freeze(Audio),
})
