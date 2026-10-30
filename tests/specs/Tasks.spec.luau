--!strict

local Expect = require("../Expect")
local Loader = require("../Loader")

local Enemies = Loader.load("src/ReplicatedStorage/Content/Enemies").ById
local Npcs = Loader.load("src/ReplicatedStorage/Content/Npcs").ById
local Relations = Loader.load("src/ReplicatedStorage/Shared/Relations")
local Tasks = Loader.load("src/ReplicatedStorage/Shared/Tasks")
local Tuning = Loader.load("src/ReplicatedStorage/Content/Tuning")

local follow = Tuning.Tasks.Follow

local function pick(...: string): string
	local open = { ... }
	return Tasks.Select(Tasks.Default, function(task)
		return table.find(open, task.kind) ~= nil
	end).kind
end

return {
	["the cascade runs the first possible task and falls through"] = function()
		Expect.equal(pick("FollowLeader", "Patrol", "Wander"), "FollowLeader")
		Expect.equal(pick("Patrol", "Wander"), "Patrol")
		Expect.equal(pick("Wander"), "Wander")
	end,

	["nothing possible means idle"] = function()
		Expect.equal(pick(), "Idle")
		Expect.equal(
			Tasks.Select({}, function()
				return true
			end).kind,
			"Idle"
		)
	end,

	["definition order decides priority"] = function()
		local chosen = Tasks.Select({ { kind = "Guard", tag = "Banner" }, { kind = "FollowLeader" } }, function()
			return true
		end)
		Expect.equal(chosen.kind, "Guard")
		Expect.equal(chosen.tag, "Banner")
	end,

	["stance defaults by faction and the field wins"] = function()
		Expect.equal(Tasks.Stance({}, true), "Hostile")
		Expect.equal(Tasks.Stance({}, false), "Neutral")
		Expect.equal(Tasks.Stance({ stance = "Neutral" }, true), "Neutral")
		Expect.equal(Tasks.Stance({ stance = "Hostile" }, false), "Hostile")
	end,

	["follow slots stay behind the leader, stable and unstacked"] = function()
		local offsets = {}
		for index = 1, 8 do
			local offset = Tasks.SlotOffset(index, index * 3, follow)
			Expect.truthy(offset.Z > 0, "behind the leader")
			Expect.truthy((offset - Tasks.SlotOffset(index, index * 3, follow)).Magnitude < 1e-6, "stable")
			table.insert(offsets, offset)
		end
		for i = 1, #offsets do
			for j = i + 1, #offsets do
				Expect.truthy((offsets[i] - offsets[j]).Magnitude > 1, `slots {i} and {j} stack`)
			end
		end
	end,

	["jitter stays within its limit"] = function()
		local centre = -(follow.RowWidth - 1) / 2 * follow.Spacing
		for seed = 1, 50 do
			local offset = Tasks.SlotOffset(1, seed, follow)
			Expect.truthy(math.abs(offset.X - centre) <= follow.Jitter + 1e-6, "x jitter")
			Expect.truthy(math.abs(offset.Z - follow.Back) <= follow.Jitter + 1e-6, "z jitter")
		end
	end,

	["the walking deadband keeps followers from twitching"] = function()
		local between = (follow.ArriveRadius + follow.ResumeRadius) / 2
		Expect.truthy(Tasks.ShouldWalk(between, true, false, follow), "keeps walking")
		Expect.truthy(not Tasks.ShouldWalk(between, false, false, follow), "keeps standing")
		Expect.truthy(Tasks.ShouldWalk(follow.ResumeRadius + 1, false, false, follow), "starts walking")
		Expect.truthy(not Tasks.ShouldWalk(follow.ArriveRadius / 2, true, false, follow), "stops")
		Expect.truthy(Tasks.ShouldWalk(0, true, true, follow), "never stops while the leader walks")
	end,

	["followers match the leader, catch up when far, and cap at their own speed"] = function()
		local onSlot = Tasks.FollowPace(follow.ArriveRadius / 2, 6, 14, follow)
		local near = Tasks.FollowPace(follow.ArriveRadius + 1, 6, 14, follow)
		local far = Tasks.FollowPace(follow.CatchUpDistance + 1, 6, 14, follow)
		Expect.truthy(math.abs(onSlot - 6 / 14) < 1e-6, "on its slot it matches the leader")
		Expect.truthy(near > onSlot and far > near, "faster the farther it is")
		Expect.equal(Tasks.FollowPace(100, 20, 10, follow), 1)
		Expect.equal(Tasks.FollowPace(1, 6, 0, follow), 1)
	end,

	["the first capable member takes over; none means no leader"] = function()
		Expect.equal(
			Tasks.PickLeader({
				{ key = "soldier", seq = 1, capable = false },
				{ key = "second", seq = 3, capable = true },
				{ key = "first", seq = 2, capable = true },
			}),
			"first"
		)
		Expect.equal(Tasks.PickLeader({ { key = "soldier", seq = 1, capable = false } }), nil)
	end,

	["monsters are hostile and other people neutral by default"] = function()
		for id, def in Enemies do
			local monster = Relations.IsMonster(def.team or "Goblins")
			Expect.equal(Tasks.Stance(def, monster), if monster then "Hostile" else "Neutral", id)
		end
		for id, def in Npcs do
			Expect.equal(Tasks.Stance(def, Relations.IsMonster(def.team or "Goblins")), "Neutral", id)
		end
	end,

	["declared tasks are well formed"] = function()
		for _, source in { Enemies, Npcs } do
			for id, def in source do
				for _, task in def.tasks or {} do
					Expect.truthy(
						task.kind == "FollowLeader"
							or task.kind == "Guard"
							or task.kind == "Patrol"
							or task.kind == "Wander"
							or task.kind == "Idle",
						`{id}: unknown task {task.kind}`
					)
					Expect.truthy(task.kind ~= "Guard" or task.tag ~= nil, `{id}: Guard without a tag`)
				end
			end
		end
	end,
}
