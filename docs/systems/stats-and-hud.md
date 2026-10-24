# Stats and HUD

Code: `Server/Services/StatService.luau`, `Content/Tuning.luau`, `Client/Controllers/HudController.luau`, `Client/Controllers/PromptController.luau`, `StarterGui/*.model.json`. Look and layout: [art/ui-style.md](../art/ui-style.md).

- Character attributes `Hp`, `MaxHp`, `Mp`, `MaxMp`, `Focus`, `MaxFocus` (names in `Shared/Constants`) are the replicated display state. `Hp` is authoritative; `Humanoid.Health` mirrors it via `StatService.SetHp`/`ApplyDamage`.
- `StarterCharacterScripts/Health` replaces Roblox's default regeneration so nothing else writes health.
- Screens are declarative `.model.json` ScreenGuis; repeated rows clone `ReplicatedStorage.UiTemplates`. `UIController.Bind` resolves `Bind_` children and errors at startup listing any that are missing. Controllers only read attributes and snapshots.
- The HUD target frame follows `TargetController.Changed` (lock or soft target) and reads the target's `DisplayName`, `Level`, `Elite`, `Hp`, `MaxHp` and `Casting` attributes. The Notices panel and the hotbar hide themselves when empty.
- `PromptController` sets every `ProximityPrompt` to the Custom style on the client and draws the `InteractPrompt` card beside the object; the server side of prompts is unchanged.
