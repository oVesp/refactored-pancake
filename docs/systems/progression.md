# Progression, classes and items

Code: `Server/Services/ProgressionService.luau`, `DisciplineService.luau`, `InventoryService.luau`; content `Classes`, `Skills`, `Disciplines`, `Items`, `Tuning`; client `SpellbookController`, `DragController`, `InventoryController`, `CharacterController`; shared `Shared/Hotbar.luau`.

- Character level comes from XP (`Tuning.Progression.XpToNext`, cap 5). The level-1 level and, for a caster, its spell pick are spent in the character creator ([character creation](character-creation.md)). Every later level is an unspent level, spent at a class trainer: the ProximityPrompt on a `Trainer`-tagged part opens the trainer panel (`OpenTrainer`), and its button sends `RequestTrain`, which the server checks for the tag, range and rate limit before training. XP gains and loot show over the character (`ShowGain`).
- Each class level grants one class skill (Active or Passive); per-class grants and unlock requirements are in [classes](classes.md). Caster levels also grant `SpellPicksPerLevel` picks from the class list, limited by the casting line's Tier ceiling (`Formulas.TierCeilings`).
- Kill XP scales with the level difference. Death adds XP debt (10% of the current level's requirement) that later XP repays first, and applies Weakened after respawn.
- Disciplines are learned from the Discipline trainer and occupy Focus capacity while active.
- Loot rolls server-side (`ContentServerOnly/Loot`) straight into the inventory. Two equipment slots (weapon, armor); item modifiers feed `StatService`.
- The server pushes `SendProfileSnapshot` (profile plus derived level, picks, ceilings, actives and the pruned hotbar) whenever the profile changes.

## Spellbook

- Opened with B. Two tabs: **Spells** (every spell, numbered by its fixed `number` in `Content/Skills`) and **Techniques** (class actives in class and grant order, then Disciplines). Pages of 16 cells (`UiTemplates/SpellCell`), with a detail pane beside the grid.
- Each entry is Known, Learnable (a spell `Formulas.CanLearnSpell` allows now) or Locked. Locked entries show as silhouettes: number, Tier or grant level, and the reason, but no name or effect. Learnable spells show in full with a Learn button (`LearnSpell`).
- Filters: status (All, Known, Learnable, Locked) and a class cycle (All, each class, General for Disciplines). Changing tab or filter returns to page 1 and keeps the selection when it is still listed.

## Hotbar

- The hotbar is the loadout: 8 slots stored in the profile as `hotbar` (`Shared/Hotbar`: `""` or `Kind:id`). Anything known can be used whether or not it is on the bar; the bar only picks what has a key.
- `SetHotbarSlot(index, kind, id)` places a known active skill or Discipline (basic attacks and passives are refused); an entry already on the bar swaps with the target slot, and `kind = ""` clears. The server checks it is known.
- Newly learned spells, granted class actives and Disciplines go into the first empty slot. Entries the player no longer knows (a removed class) are pruned.
- In the spellbook, Known entries are dragged onto a slot, or placed with the eight slot buttons in the detail pane (gamepad and touch); pressing the slot an entry already uses clears it. While the spellbook is open, hotbar presses drag instead of cast: drop on another slot to swap, off the bar to clear. The drag ghost lives in the `DragLayer` screen and drops test the HUD slots' screen rects, so drags work from a world-space panel too.
