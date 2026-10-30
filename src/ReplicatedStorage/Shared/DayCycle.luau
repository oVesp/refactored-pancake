--!strict

local Atmosphere = require(script.Parent.Parent.Content.Atmosphere)

local DAWN = 6
local DUSK = 18

--[=[
	World clock shared by every server and client: a pure function of server time, so nothing
	replicates and all players see the same sky. The day (06:00 to 18:00) takes
	`1 - NightShare` of `DayLength`; the night takes the rest.
]=]
local DayCycle = {}

--[=[ Lighting.ClockTime (0..24) at `serverTime` seconds (workspace:GetServerTimeNow()). ]=]
function DayCycle.ClockAt(serverTime: number): number
	local phase = (serverTime % Atmosphere.DayLength) / Atmosphere.DayLength
	local dayShare = 1 - Atmosphere.NightShare
	local hours = if phase < dayShare
		then DAWN + (DUSK - DAWN) * phase / dayShare
		else DUSK + (24 - DUSK + DAWN) * (phase - dayShare) / Atmosphere.NightShare
	return hours % 24
end

--[=[ Seconds into the day cycle at which the clock reads `hour` (0..24); the inverse of `ClockAt`. ]=]
function DayCycle.SecondsAt(hour: number): number
	hour = hour % 24
	local dayShare = 1 - Atmosphere.NightShare
	local phase = if hour >= DAWN and hour < DUSK
		then dayShare * (hour - DAWN) / (DUSK - DAWN)
		else dayShare + Atmosphere.NightShare * ((hour - DUSK) % 24) / (24 - DUSK + DAWN)
	return phase * Atmosphere.DayLength
end

--[=[
	The clock now: server time moved by the workspace `ClockShift` attribute (seconds), which the
	Control Weather dev skill sets so every server and client sees the same changed sky.
]=]
function DayCycle.Now(): number
	local shift = workspace:GetAttribute("ClockShift")
	return DayCycle.ClockAt(workspace:GetServerTimeNow() + (if type(shift) == "number" then shift else 0))
end

--[=[ True between dusk and dawn. ]=]
function DayCycle.IsNight(clock: number): boolean
	return clock >= DUSK or clock < DAWN
end

return DayCycle
