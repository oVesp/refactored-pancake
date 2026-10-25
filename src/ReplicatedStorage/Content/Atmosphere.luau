--!strict

export type Mood = {
	density: number,
	offset: number,
	haze: number,
	glare: number,
	color: Color3,
	decay: Color3,
	saturation: number,
	contrast: number,
	tint: Color3,
	cloudCover: number,
	cloudDensity: number,
}

export type Light = {
	hour: number,
	brightness: number,
	exposure: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	shiftTop: Color3,
	-- Multiplies the region's atmosphere colour, decay and grade tint.
	skyLight: Color3,
	-- Multiplies the region's haze; night air reads clearer, dawn and dusk mistier.
	hazeScale: number,
	bloom: number,
	sunRays: number,
}

export type Band = { from: number, to: number }

--[=[
	Midgard atmosphere (docs/systems/atmosphere.md). A mood per region, blended by where the
	camera is, then lit by the time of day. Region bands mirror `tools/terrain/lib/Config.luau`
	`world` (checked by tests/specs/Atmosphere.spec.luau) without the generator's noise warp,
	which is small next to the 1,000-stud blend.
]=]
local moods: { [string]: Mood } = {
	-- Start valley: clear green morning air, haze closing in past about 1,000 studs.
	valley = {
		density = 0.36,
		offset = 0.25,
		haze = 1.6,
		glare = 0.4,
		color = Color3.fromRGB(199, 214, 222),
		decay = Color3.fromRGB(106, 120, 112),
		saturation = 0.08,
		contrast = 0.06,
		tint = Color3.fromRGB(255, 252, 244),
		cloudCover = 0.55,
		cloudDensity = 0.35,
	},
	-- Highlands: open heath, wind-thinned air, cooler grade.
	highland = {
		density = 0.32,
		offset = 0.3,
		haze = 1.2,
		glare = 0.5,
		color = Color3.fromRGB(196, 206, 214),
		decay = Color3.fromRGB(116, 112, 104),
		saturation = 0,
		contrast = 0.08,
		tint = Color3.fromRGB(248, 248, 250),
		cloudCover = 0.62,
		cloudDensity = 0.4,
	},
	-- Mountains: grey-blue, heavy cloud on the peaks.
	mountain = {
		density = 0.4,
		offset = 0.2,
		haze = 2,
		glare = 0.3,
		color = Color3.fromRGB(188, 200, 214),
		decay = Color3.fromRGB(110, 118, 132),
		saturation = -0.12,
		contrast = 0.1,
		tint = Color3.fromRGB(238, 244, 255),
		cloudCover = 0.75,
		cloudDensity = 0.55,
	},
	-- High altitude anywhere: thin, bright, crisp air above the snow line.
	alpine = {
		density = 0.26,
		offset = 0.45,
		haze = 0.6,
		glare = 1.2,
		color = Color3.fromRGB(214, 226, 240),
		decay = Color3.fromRGB(150, 170, 200),
		saturation = -0.05,
		contrast = 0.12,
		tint = Color3.fromRGB(242, 248, 255),
		cloudCover = 0.6,
		cloudDensity = 0.3,
	},
	-- Swamp: thick green-brown murk, short sight lines.
	swamp = {
		density = 0.52,
		offset = 0.05,
		haze = 3.2,
		glare = 0,
		color = Color3.fromRGB(162, 172, 140),
		decay = Color3.fromRGB(78, 88, 62),
		saturation = -0.2,
		contrast = 0.04,
		tint = Color3.fromRGB(236, 244, 220),
		cloudCover = 0.8,
		cloudDensity = 0.6,
	},
	-- Plains: warm, dry, golden distance.
	plains = {
		density = 0.3,
		offset = 0.35,
		haze = 1.4,
		glare = 0.8,
		color = Color3.fromRGB(220, 212, 190),
		decay = Color3.fromRGB(150, 122, 92),
		saturation = 0.12,
		contrast = 0.05,
		tint = Color3.fromRGB(255, 246, 228),
		cloudCover = 0.45,
		cloudDensity = 0.3,
	},
	-- Coast: salt haze, blue-grey, bright glare off the sea.
	coast = {
		density = 0.38,
		offset = 0.2,
		haze = 2.2,
		glare = 1,
		color = Color3.fromRGB(196, 214, 226),
		decay = Color3.fromRGB(110, 130, 150),
		saturation = 0,
		contrast = 0.04,
		tint = Color3.fromRGB(246, 250, 255),
		cloudCover = 0.6,
		cloudDensity = 0.4,
	},
}

-- Keyed by ClockTime hour, sorted, wrapping from the last key back to the first.
local lights: { Light } = {
	{
		hour = 0,
		brightness = 0.6,
		exposure = 0.1,
		ambient = Color3.fromRGB(48, 54, 72),
		outdoorAmbient = Color3.fromRGB(82, 94, 128),
		shiftTop = Color3.fromRGB(150, 170, 220),
		skyLight = Color3.fromRGB(70, 82, 116),
		hazeScale = 0.6,
		bloom = 0.6,
		sunRays = 0,
	},
	{
		hour = 5.4,
		brightness = 0.8,
		exposure = 0.05,
		ambient = Color3.fromRGB(58, 60, 78),
		outdoorAmbient = Color3.fromRGB(96, 98, 128),
		shiftTop = Color3.fromRGB(170, 160, 200),
		skyLight = Color3.fromRGB(110, 104, 140),
		hazeScale = 1.2,
		bloom = 0.5,
		sunRays = 0,
	},
	{
		hour = 6.4,
		brightness = 1.8,
		exposure = 0,
		ambient = Color3.fromRGB(86, 74, 70),
		outdoorAmbient = Color3.fromRGB(150, 122, 108),
		shiftTop = Color3.fromRGB(255, 170, 120),
		skyLight = Color3.fromRGB(255, 196, 160),
		hazeScale = 1.5,
		bloom = 0.9,
		sunRays = 0.18,
	},
	{
		hour = 9,
		brightness = 2.6,
		exposure = 0,
		ambient = Color3.fromRGB(88, 92, 98),
		outdoorAmbient = Color3.fromRGB(138, 142, 150),
		shiftTop = Color3.fromRGB(255, 240, 220),
		skyLight = Color3.fromRGB(255, 252, 246),
		hazeScale = 1,
		bloom = 0.7,
		sunRays = 0.08,
	},
	{
		hour = 15,
		brightness = 2.6,
		exposure = 0,
		ambient = Color3.fromRGB(90, 90, 92),
		outdoorAmbient = Color3.fromRGB(142, 140, 138),
		shiftTop = Color3.fromRGB(255, 236, 210),
		skyLight = Color3.fromRGB(255, 248, 236),
		hazeScale = 1,
		bloom = 0.7,
		sunRays = 0.08,
	},
	{
		hour = 17.6,
		brightness = 1.8,
		exposure = 0,
		ambient = Color3.fromRGB(92, 72, 66),
		outdoorAmbient = Color3.fromRGB(156, 116, 98),
		shiftTop = Color3.fromRGB(255, 150, 96),
		skyLight = Color3.fromRGB(255, 176, 130),
		hazeScale = 1.4,
		bloom = 1,
		sunRays = 0.2,
	},
	{
		hour = 18.6,
		brightness = 0.9,
		exposure = 0.05,
		ambient = Color3.fromRGB(62, 58, 78),
		outdoorAmbient = Color3.fromRGB(104, 96, 130),
		shiftTop = Color3.fromRGB(190, 140, 180),
		skyLight = Color3.fromRGB(130, 110, 150),
		hazeScale = 1.1,
		bloom = 0.6,
		sunRays = 0,
	},
}

return table.freeze({
	Moods = table.freeze(moods),
	Lights = table.freeze(lights),
	-- Region bands in world studs; each blends 0 -> 1 from `from` to `to`.
	Bands = table.freeze({
		mountain = { from = -2400, to = -3700 } :: Band,
		highland = { from = -1400, to = -2300 } :: Band,
		swamp = { from = -2000, to = -3000 } :: Band,
		plains = { from = 2100, to = 3100 } :: Band,
		coast = { from = 2300, to = 3400 } :: Band,
		-- Camera height; the terrain snow line is at 360.
		alpine = { from = 240, to = 420 } :: Band,
	}),
	-- Seconds per in-game day and the share of it spent at night (owner choice, 2026-10-25).
	DayLength = 24 * 60,
	NightShare = 0.25,
	-- How often the client re-blends, and how fast values ease toward the target (per second).
	UpdateHz = 8,
	Smoothing = 1.5,
})
