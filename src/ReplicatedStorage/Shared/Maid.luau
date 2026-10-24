--!strict

export type Task = RBXScriptConnection | Instance | () -> () | { Destroy: (any) -> () }

export type Maid = {
	Give: <T>(self: Maid, task: T & Task) -> T,
	Clean: (self: Maid) -> (),
}

local Maid = {}

local function cleanTask(task: Task)
	if typeof(task) == "RBXScriptConnection" then
		task:Disconnect()
	elseif typeof(task) == "Instance" then
		task:Destroy()
	elseif type(task) == "function" then
		task()
	else
		(task :: any):Destroy()
	end
end

--[=[
	Creates a maid that owns cleanup tasks: connections are disconnected, instances destroyed,
	functions called and objects with `Destroy` destroyed. `Clean` runs tasks in reverse order
	and leaves the maid reusable.
]=]
function Maid.new(): Maid
	local tasks: { Task } = {}

	local function give<T>(_self: Maid, task: T & Task): T
		table.insert(tasks, task)
		return task
	end

	local function clean(_self: Maid)
		while #tasks > 0 do
			cleanTask(table.remove(tasks) :: Task)
		end
	end

	return {
		Give = give,
		Clean = clean,
	}
end

return Maid
