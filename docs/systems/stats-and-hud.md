# Stats and HUD

Code: `Server/Services/StatService.luau`, `Content/BaseStats.luau`, `Client/Controllers/HudController.luau`, `StarterGui/Hud.rbxmx`.

- Character attributes `Hp`, `MaxHp`, `Mp`, `MaxMp`, `Focus`, `MaxFocus` (names in `Shared/Constants`) are the replicated display state. `Hp` is authoritative; `Humanoid.Health` mirrors it via `StatService.SetHp`/`ApplyDamage`.
- `StarterCharacterScripts/Health` replaces Roblox's default regeneration so nothing else writes health.
- The HUD is an authored ScreenGui. `UIController.Bind` resolves `Bind_` children and errors at startup listing any that are missing. `HudController` only reads attributes.
