--!strict

local Expect = require("../Expect")
local Signal = require("../../src/ReplicatedStorage/Shared/Signal")

return {
	["fires handlers in order with arguments"] = function()
		local signal = Signal.new()
		local log = {}
		signal:Connect(function(value: number)
			table.insert(log, value)
		end)
		signal:Connect(function(value: number)
			table.insert(log, value * 10)
		end)
		signal:Fire(2)
		Expect.equal(log[1], 2)
		Expect.equal(log[2], 20)
	end,
	["disconnect stops delivery"] = function()
		local signal = Signal.new()
		local count = 0
		local connection = signal:Connect(function()
			count += 1
		end)
		signal:Fire()
		connection:Disconnect()
		signal:Fire()
		Expect.equal(count, 1)
		Expect.equal(connection.Connected, false)
	end,
	["handler disconnected mid-fire is skipped"] = function()
		local signal = Signal.new()
		local second
		local ran = false
		signal:Connect(function()
			second:Disconnect()
		end)
		second = signal:Connect(function()
			ran = true
		end)
		signal:Fire()
		Expect.equal(ran, false)
	end,
	["disconnectAll clears every handler"] = function()
		local signal = Signal.new()
		local count = 0
		signal:Connect(function()
			count += 1
		end)
		signal:DisconnectAll()
		signal:Fire()
		Expect.equal(count, 0)
	end,
}
