--!strict

--[=[
	Pure decisions of the double-tap W run (docs/systems/combat.md, Entities): a second forward tap
	inside the window starts running; releasing forward or standing still stops it. InputController
	feeds it input and the clock; the server sets the walk speed.
]=]
local Gait = {}

--[=[ Move direction length under which the character counts as standing still. ]=]
Gait.STOP_MOVE_MAGNITUDE = 0.1

export type State = {
	running: boolean,
	tappedAt: number,
}

function Gait.new(): State
	return { running = false, tappedAt = -math.huge }
end

--[=[ Forward key went down. Keys the game already processed (chat, UI) never count as a tap. ]=]
function Gait.ForwardBegan(state: State, processed: boolean, now: number, window: number)
	if processed then
		return
	end
	if now - state.tappedAt <= window then
		state.running = true
		state.tappedAt = -math.huge
	else
		state.tappedAt = now
	end
end

--[=[ Forward key went up: running ends even if the character is still sliding. ]=]
function Gait.ForwardEnded(state: State)
	state.running = false
end

--[=[ Per-frame check: running ends when the character is gone, dead or standing still. ]=]
function Gait.Step(state: State, hasCharacter: boolean, health: number, moveMagnitude: number)
	if state.running and (not hasCharacter or health <= 0 or moveMagnitude < Gait.STOP_MOVE_MAGNITUDE) then
		state.running = false
	end
end

return Gait
