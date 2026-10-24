# Progression, classes and items

Code: `Server/Services/ProgressionService.luau`, `DisciplineService.luau`, `InventoryService.luau`; content `Classes`, `Skills`, `Disciplines`, `Items`, `Tuning`; client `SpellbookController`, `InventoryController`, `CharacterController`.

- Character level comes from XP (`Tuning.Progression.XpToNext`, cap 5). Each level is an unspent level, spent at a class trainer (ProximityPrompt on a `Trainer`-tagged part).
- Each class level grants one class skill (Active or Passive). Caster levels also grant `SpellPicksPerLevel` picks from the class list, limited by the casting line's Circle ceiling (`Formulas.CircleCeilings`).
- Kill XP scales with the level difference. Death adds XP debt (10% of the current level's requirement) that later XP repays first, and applies Weakened after respawn.
- Disciplines are learned from the Discipline trainer and occupy Focus capacity while active.
- Loot rolls server-side (`ContentServerOnly/Loot`) straight into the inventory. Two equipment slots (weapon, armor); item modifiers feed `StatService`.
- The server pushes `SendProfileSnapshot` (profile plus derived level, picks, ceilings and actives) whenever the profile changes.
