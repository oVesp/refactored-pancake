# Classes

Class roster, unlock requirements and level progression. Rules shared by every class live in [game-design §3.6](../game-design.md); this doc holds the per-class design. Code (once migrated): `Content/Classes`, `Content/Skills`, `ProgressionService`.

## Unlock requirements

A class unlocks when **every** requirement in its set passes. Level is one requirement among others, never the only gate for a high or rare class.

| Requirement | Passes when | Example |
|---|---|---|
| `ClassLevel` | the character has at least N levels in a named class | Fighter ≥ 5 |
| `CategoryLevel` | the summed levels of every class with a category tag reach N | Martial ≥ 10 |
| `TotalLevel` | the character level reaches N | level ≥ 20 |
| `Kills` | the kill counter for an enemy id or family reaches N | 100 goblins |
| `Achievement` | a named achievement or quest chain is complete | "Cleared the goblin camp" |
| `Karma` | karma is inside a range | karma ≥ 200 (no karma system yet) |
| `Heritage` | the character's race or family is in a list | Human, Demi-Human |
| `ItemTurnIn` | the item is handed to the class trainer (consumed) | 1 wolf pelt |

Categories are tags on a class (`Martial` for physical-damage classes; casting lines count as their own category). A class with an empty set is a starter class.

## Roster

| Class | Tier | Cap | Category | Requirements | Role |
|---|---|---|---|---|---|
| **Fighter** | Base | 15 | Martial | none (starter) | General physical damage, any weapon |
| **Warrior** | High | 10 | Martial | Fighter ≥ 5; more TBD | Melee physical damage |
| **Ranger** | High | 10 | Martial | Fighter ≥ 5; more TBD | Ranged physical damage |

Warrior and Ranger are Fighter's specializations. Weapon-specific skills (area swings, armor breaking, volleys) belong to them, not to Fighter. Warrior skill candidates carried over from the old M0.5 Warrior: Cleave, Charge (interrupt), War Cry (taunt).

## Fighter

Base class for every physical damage dealer. Stamina resource. Stat lean: Physical Attack, Agility, Max HP. Physical damage only.

**Weapon rule:** Fighter skills are weapon-agnostic. Each active either modifies the next attack or buffs the Fighter; damage is delivered by the equipped weapon's own attack (melee hit or projectile). Weapon families: **Sword, Bow**.

| Lv | Skill | Kind | Effect |
|---|---|---|---|
| 1 | **Weapon Proficiency I** | Passive, choice | Choose one weapon family. **+10% damage** with it. |
| 2 | **Precise Attack** | Active, GCD | Single-target attack with the equipped weapon: 140% damage, +15% crit chance. |
| 3 | **Combat Conditioning** | Passive | +20 Max Stamina, +15% Stamina regen. |
| 4 | **Gather Strength** | Active, oGCD | 25 Stamina, 20 s cooldown. The next attack or skill within 8 s deals **+50% damage**. |
| 5 | **Second Wind** | Active, oGCD | 60 s cooldown. Restore 40% Stamina and 10% Max HP. |
| 6 | **Weapon Proficiency II** | Passive | Family damage bonus **+20%**. |
| 7 | **Heightened Senses** | Active, oGCD | 30 Stamina, 45 s cooldown. **+40% Agility** for 8 s. |
| 8 | **Battle Rhythm** | Passive | Each hit within 3 s of the last: +2% damage, stacks to 5. |
| 9 | **Disengage** | Active, oGCD | Leap backward; the next attack within 3 s is a guaranteed crit. |
| 10 | **Exploit Weakness** | Passive | Crits apply Exposed: the target takes +10% physical damage from you for 5 s. |
| 11 | **Weapon Proficiency III** | Passive | Family damage bonus **+30%**, +15% crit damage with it. |
| 12 | **Gather Strength II** | Passive | Gather Strength holds 2 charges; bonus +75%. |
| 13 | **Keen Reflexes** | Passive | Heightened Senses lasts 12 s and grants +60% Agility. |
| 14 | **Finishing Instinct** | Passive | +25% damage to targets below 30% HP. |
| 15 | **Battle Trance** (signature) | Active, oGCD | 120 s cooldown, 12 s. +25% damage, Stamina costs halved, Battle Rhythm starts at 5 stacks; a free Gather Strength when it ends. |

Shape: 1–5 core loop (open with Precise Attack, empower with Gather Strength, sustain with Second Wind); 6–10 tempo and defence; 11–15 upgrades and the signature. Fighter 5 unlocks Warrior and Ranger.

Naming: the skill is **Gather Strength**, not "Focus", because Focus is the Disciplines resource (§3.3). No skill grants speed; Haste stays item-only (§3.4).
