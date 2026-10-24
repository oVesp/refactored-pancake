# Net

Code: `src/ReplicatedStorage/Shared/Net/` (`init.luau` declarations, `Server.luau`, `Client.luau`).

- Every remote is declared once in `Net/init.luau` with a direction. ClientToServer remotes must declare a `rateLimit` (token bucket per player) and a `validate` function; the module asserts this at load.
- `NetServer.Init()` creates a `RemoteEvent` per declaration under `ReplicatedStorage.Remotes` before any service starts. `NetClient.Init()` waits for them and errors after `Constants.ClientWaitTimeout`.
- `NetServer.Connect` runs the handler only after the rate limit, then validation, pass. Rejects are dropped silently, counted (`GetRejectionCount`) and logged at debug, throttled.
- Only `RemoteEvent`s. No `RemoteFunction` to clients, ever.

Adding a remote: declare it, give it a `Verb` + `Noun` name, write the validator against the payload schema, connect it in the owning service's `Init`.
