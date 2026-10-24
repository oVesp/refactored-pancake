--!strict

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Slot<T...> = {
	handler: (T...) -> (),
	connection: Connection,
}

local Signal = {}

--[=[
	Creates a signal. Handlers run synchronously in connection order when `Fire` is called,
	so they must not yield. A handler disconnected during a fire is skipped if it has not run yet.
]=]
function Signal.new<T...>(): Signal<T...>
	local slots: { Slot<T...> } = {}

	local function connect(_self: Signal<T...>, handler: (T...) -> ()): Connection
		local connection = { Connected = true } :: Connection
		local slot = { handler = handler, connection = connection }

		function connection.Disconnect(self: Connection)
			if not self.Connected then
				return
			end
			self.Connected = false
			local index = table.find(slots, slot)
			if index then
				table.remove(slots, index)
			end
		end

		table.insert(slots, slot)
		return connection
	end

	local function fire(_self: Signal<T...>, ...: T...)
		for _, slot in table.clone(slots) do
			if slot.connection.Connected then
				slot.handler(...)
			end
		end
	end

	local function disconnectAll(_self: Signal<T...>)
		for _, slot in slots do
			slot.connection.Connected = false
		end
		table.clear(slots)
	end

	return {
		Connect = connect,
		Fire = fire,
		DisconnectAll = disconnectAll,
	}
end

return Signal
