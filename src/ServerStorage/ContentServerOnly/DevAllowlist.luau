--!strict

--[=[
	UserIds allowed to run dev commands outside Studio. Studio sessions are always allowed.
	Server-only so clients cannot read or spoof it.
]=]
return table.freeze({
	82401475,
})
