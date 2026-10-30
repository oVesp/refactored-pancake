# Weapons and shields

Code: `Content/Weapons.luau` (weapon types), `Content/Items.luau` (`weapon`, `shield` fields, `offhand` slot), `Shared/Loadout.luau` (what a profile or character holds), `Shared/Archery.luau` (bow maths); server `SkillService` (basics, draw, guard rules), `CombatService` (shield guard), `StatService` (sets `Weapon` and `Shield` attributes, draw slow), `LoadoutService` (held models); client `CombatController` (attacks, draw camera), `InputController`, `VfxController`. Placeholder models: `ReplicatedStorage/Weapons/*.model.json`.

Each weapon type swaps the basic attacks bound to light (tap) and heavy (hold) attack, in the spirit of Dragon's Dogma: the same buttons, different verbs. Basic attacks stay off the GCD and cost no MP (`docs/systems/combat.md`, Timing).

| Weapon | Hands | Light | Heavy | Guard without shield |
|---|---|---|---|---|
| Fists (nothing equipped) | One | `strike` chain (jab, cross, hook) | `heavy_strike` | Yes |
| Sword | One | `sword_slash` chain (3 cuts, wide finisher) | `sword_heavy` overhead cut | Yes |
| Bow | Two | Hold to draw, release `bow_shot` | none | No |
| Staff | Two | `staff_strike` chain (arcane melee) | `staff_bolt` charged arcane bolt | Yes |
| Wand | One | `wand_bolt` quick arcane bolt | `wand_blast` charged arcane blast | No |

- **Equipment**: a weapon item names its type (`ItemDef.weapon`); shields are `kind = "Shield"` in the `offhand` slot. A two-handed weapon and a shield push each other off when equipped (`Loadout.Displaced`). `StatService.Recompute` writes `Entity.weapon`, `Entity.shieldGuard` and the character attributes `Weapon` and `Shield` (item id); `LoadoutService` welds the models from `ReplicatedStorage.Weapons` to the hand grip attachments (`Handle` part with a `Grip` attachment).
- **Server rules**: `SkillService.KnownActives` holds only the equipped weapon's basics (`Loadout.Basics`) plus `shield_bash` with a shield, so a basic of another weapon is rejected as `Unknown`. The light chain check uses the weapon's own entry. `heavy = true` marks heavies that `HeavySpeed` shortens.
- **Bow**: pressing attack sends `SetDraw(true)`; the server records `drawSince` and slows the archer to `Tuning.Combat.Bow.DrawMoveMultiplier`. The client turns on an over-the-shoulder camera (offset, narrower FOV, character faces the camera). Releasing sends `UseSkill(bow_shot)`; the server scales damage by `Archery.DrawScale` (nothing below `MinDraw`, `MinScale` → 1 by `FullDraw`, +`PerfectBonus` within `PerfectWindow` after full draw); a gold flash on the bow hand marks full draw. Arrows are free-aim projectiles with `gravity` (aim high at range), never home, and get `rearBonus` when they land within `RearArc` of the target's back. Guarding, dodging, any other skill, a stun or releasing early cancel the draw.
- **Staff and wand**: their magic is the basic attack itself (owner decision 2026-10-30): no MP, off the GCD; heavies are charged (windup) and cost stamina. Damage type `force`, scaled by `MagAtk`.
- **Shields**: while guarding (F) with a shield, its `shield` values replace `Tuning.Combat.Guard`: wider arc, longer parry window, full block (`damageMultiplier = 0`) paid in stamina per hit. Attack while guarding uses `shield_bash` (short shove, stun, knockback, stamina). Bow and wand cannot guard without a shield.
- **Placeholders**: sword and staff reuse the fist clips and the Cleave swipe; the bow has no draw clip yet; bolts use the neon projectile. Weapon-specific clips and VFX are a later art pass.
