# Stats and HUD

Code: `Server/Services/StatService.luau`, `Content/Tuning.luau`, `Client/Controllers/HudController.luau`, `StarterGui/*.model.json`.

- Character attributes `Hp`, `MaxHp`, `Mp`, `MaxMp`, `Focus`, `MaxFocus` (names in `Shared/Constants`) are the replicated display state. `Hp` is authoritative; `Humanoid.Health` mirrors it via `StatService.SetHp`/`ApplyDamage`.
- `StarterCharacterScripts/Health` replaces Roblox's default regeneration so nothing else writes health.
- Screens are declarative `.model.json` ScreenGuis; repeated rows clone `ReplicatedStorage.UiTemplates`. `UIController.Bind` resolves `Bind_` children and errors at startup listing any that are missing. Controllers only read attributes and snapshots.
