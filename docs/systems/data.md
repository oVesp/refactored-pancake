# Data

Code: `src/ServerScriptService/Server/Services/DataService.luau`, `Server/Data/Profile.luau`.

- Contract from game-design.md 5.8: `Get`, `Update(player, fn, path?)`, `Changed(player, path)`, `WaitForProfile`, `Release`. The persistent module must keep it.
- In-memory only, keyed by `Player`. `Profile.new()` is the only source of a fresh profile; `Profile.Migrate` runs on every load and refuses data from a newer schema.
- Profile fields: `schemaVersion` (5), `created` (false until the character creator ran), `name`, `heritage` (id in `Content/Heritages`), `appearance` (creator look: gender, skinTone, hair, hairColor, facialHair, outfit; added with `created` and `name` by the v2 to v3 migration, which leaves old profiles uncreated), `classes` (build path in order taken), `xp`, `xpDebt`, `spells`, `disciplines`, `inventory`, `equipment`, `hotbar` (8 encoded slots, `""` when empty; added by the v1 to v2 migration), `nextUid`, `discoveries` (set of enemy ids the character has killed, which opens summon options; added by the v4 to v5 migration). Session state (cooldowns, aggro, hunger and thirst until the persistent module lands) never goes here.
- In Studio, `Update` asserts `Profile.IsSerializable` after every mutation.
- `RequestProfile` → `SendProfileSnapshot` sends a snapshot on demand; it carries `created` and `name` for the creator and HUD, and `discoveries` for the summon picker.
- Profiles are lost on leave, so the character creator runs on every join until the persistent module lands ([character creation](character-creation.md)).
