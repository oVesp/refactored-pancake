# Data

Code: `src/ServerScriptService/Server/Services/DataService.luau`, `Server/Data/Profile.luau`.

- Contract from game-design.md 5.8: `Get`, `Update(player, fn, path?)`, `Changed(player, path)`, `WaitForProfile`, `Release`. The persistent module must keep it.
- In-memory only, keyed by `Player`. `Profile.new()` is the only source of a fresh profile; `Profile.Migrate` runs on every load and refuses data from a newer schema.
- Profile fields: `schemaVersion` (1), `heritage`, `classes` (build path in order taken), `xp`. Session state (cooldowns, aggro) never goes here.
- In Studio, `Update` asserts `Profile.IsSerializable` after every mutation.
- `RequestProfile` → `SendProfileSnapshot` sends a snapshot on demand.
