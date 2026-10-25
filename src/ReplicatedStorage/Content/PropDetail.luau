--!strict

export type LayerRule = {
	-- Whole 256-stud chunks are hidden past this distance (studs, flat) from the camera.
	hideBeyond: number?,
	-- Past this distance only a `keep` share of the layer's props stays visible.
	thinBeyond: number?,
	keep: number?,
}

--[=[
	Client detail distances for the generated props (docs/systems/atmosphere.md, Performance).
	Measured in Studio on 2026-10-25: hiding small layers past 450 and keeping 40% of trees past
	600 took the start valley from about 27 to 38 fps.
]=]
return table.freeze({
	ChunkStuds = 256,
	-- Distances are re-checked this often; `Hysteresis` stops chunks flickering at the edge.
	UpdateHz = 2,
	Hysteresis = 48,
	Layers = table.freeze({
		Understory = { hideBeyond = 450 },
		Cover = { hideBeyond = 450 },
		Pebbles = { hideBeyond = 350 },
		Trees = { thinBeyond = 600, keep = 0.4 },
	} :: { [string]: LayerRule }),
})
