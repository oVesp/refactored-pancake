# Stats and HUD

Code: `Server/Services/StatService.luau`, `Server/Services/NeedsService.luau`, `Shared/Needs.luau`, `Content/Tuning.luau`, `Client/Controllers/HudController.luau`, `Client/Controllers/PromptController.luau`, `StarterGui/*.model.json`. Look and layout: [art/ui-style.md](../art/ui-style.md).

- Character attributes `Hp`, `MaxHp`, `Mp`, `MaxMp`, `Focus`, `MaxFocus` (names in `Shared/Constants`) are the replicated display state. `Hp` is authoritative; `Humanoid.Health` mirrors it via `StatService.SetHp`/`ApplyDamage`.
- `StarterCharacterScripts/Health` replaces Roblox's default regeneration so nothing else writes health.
- Screens are declarative `.model.json` ScreenGuis; repeated rows clone `ReplicatedStorage.UiTemplates`. `UIController.Bind` resolves `Bind_` children and errors at startup listing any that are missing. Controllers only read attributes and snapshots.
- The HUD target frame follows `TargetController.Changed` (lock or soft target) and reads the target's `DisplayName`, `Level`, `Elite`, `Hp`, `MaxHp` and `Casting` attributes. The Notices panel hides itself when empty. The hotbar always lays out its 8 slots from the profile's `hotbar` (empty slots are faded) and hides only when every slot is empty and the spellbook is closed.
- Gold: the snapshot's `gold` shows in `Bind_GoldText` beside the Focus line ([economy](economy.md)).
- `PromptController` sets every `ProximityPrompt` to the Custom style on the client and draws the `InteractPrompt` card beside the object; the server side of prompts is unchanged.

## Hunger and thirst

Numbers live in `Tuning.Needs`; the math is pure in `Shared/Needs`; `NeedsService` owns the state.

- Hunger runs from 100 to 0 in 40 minutes, thirst in 25. Decay pauses while the player is dead or before character creation.
- Below 25%, HP and MP regen are halved per low need (both low: a quarter). Stamina regen is unaffected. `NeedsService` writes the result to `entity.regenScale`; `StatService` applies it.
- A need at 0 stops HP and MP regen and drains 0.5 HP per second per empty need, down to 1 HP. It never kills, skips god mode and does not count as combat.
- Values are session state keyed by `Player`, not `Profile`: they survive respawn and reset on rejoin. Persist them when the persistent Data module lands. Writing through `DataService.Update` each tick would fire `Changed` and recompute stats.
- They replicate as `Hunger` and `Thirst` attributes on the `Player`, unlike the character attributes above, and only when the rounded-up value changes. The HUD bars turn from gold to red below 25%.
- Restore with `NeedsService.Restore(player, "Hunger" | "Thirst", amount)`, clamped to 0-100. Items use it through `use.hunger` and `use.thirst` (`bread`, `cooked_meat`, `water_flask`).
