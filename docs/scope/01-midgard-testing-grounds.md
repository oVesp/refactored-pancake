# Scope 01 — Midgard Testing Grounds

Status: **approved scope, revision 2.** Milestone **M0.5** in [game-design.md](../game-design.md) §7.4 and §10. Where this file and `game-design.md` disagree, `game-design.md` wins.

| Field | Value |
|---|---|
| Realm | Midgard |
| Level band | 1–5 |
| Classes | Warrior, Mage, Healer |
| Area | Farming Village and its fields |
| Threat | Goblin Rabble (Lv 1–6). Goblin Warband (Lv 7+) is data-only here, spawned in the Dev Yard |
| Place type | Single dev place: placeholder art, testing grounds |

## 0. Decisions (resolved)

| # | Decision |
|---|---|
| D1 | New milestone **M0.5 Testing Grounds** between M0 and M1. M1 targets unchanged except its Circle range (§3 below). |
| D2 | **1 spell pick per caster class level** here (`SPELL_PICKS_PER_LEVEL = 1`, data constant). **Circle 2 unlocks at casting-line level 6**, so levels 1–5 use Circles 0–1 only. |
| D3 | Minimal Disciplines: Focus pool + 2 Disciplines from a trainer NPC. |
| D4 | §4's 8-class starter list and its templates stay as the future plan. This place has 3 classes, so it tests 5 / 3+2 / 2+2+1 / 3+1+1; dabbler (2+1+1+1) waits for a 4th class. |
| D5 | Midgard is used. Public-domain myth and folklore names are allowed (§2 of the design doc, amended). |

---

## 1. Purpose and non-goals

**Purpose:** one place where every core pipeline runs end to end with placeholder content: input → `UseSkill` → server validation → damage → replicated HP → XP → level up → class level → new skill, passive or spell.

**Non-goals:** final art, story, quests beyond test objectives, persistence (DataService stub only, §5.8), teleport or multiple places, crafting, trading, Holds, PvP, monetization, resurrection spells.

---

## 2. Zone layout

One place, run as zones behind `ZoneService` (§3.7). Danger reads honestly from the village outward.

| Zone | Band | Contents | Purpose |
|---|---|---|---|
| **Village Core** | Safe | Spawn/respawn, 3 class trainers, Discipline trainer, vendor stub, well, barns, houses | Class pick, dev respec, safe-zone rules |
| **Dev Yard** | Safe | Training dummies (one per damage type + one with resist tags), spawn pads, lag test lane | Combat tuning, hit validation, Warband tests |
| **Wheat Fields** | Lv 1–3 | Raiders, Slingers, scarecrow cover, fences | First pulls, ranged vs melee |
| **Orchard Edge** | Lv 3–4 | Mixed Raider/Slinger/Trapper packs | Poison and cleanse, healing pressure |
| **Goblin Camp** | Lv 4–6 | Palisade, tents, Brutes, optional Chieftain | Telegraphs, elite fight, leash rules |

Fiction (light): goblin raiders steal grain and livestock from the village. No named characters, no event beats.

---

## 3. Circles at levels 1–5

Rule (§3.2): the Circle ceiling follows levels in the **deepest compatible casting line**, not total level. Unlock table lives in `Content/Magic` and is tunable:

| Circle | Casting-line level |
|---|---|
| 0, 1 | 1 |
| 2 | 6 |
| 3 | 12 |
| n (≥2) | 6 × (n − 1) |

So Circle 3 lands at 12, Circle 6 at 30 and Circle 10 at 54. That matches the research benchmarks: ordinary folk top out around 2, elites around 3.

Here: Mage and Healer see **Circles 0–1 only**. Circle 0 is utility and costs like Circle 1 (§3.2).

---

## 4. Classes

All three are **base classes** (cap 15). Level cap here is 5. Stats per §3.1, numbers in `Content/Classes`.

| Class | Role | Resource | Stat lean | Damage types |
|---|---|---|---|---|
| **Warrior** | Front line, melee | Stamina for class skills, Focus for Disciplines | HP, Physical Attack, Physical Defense | Physical |
| **Mage** | Ranged damage, control | MP | MP, Magic Attack, Agility | Fire, cold, lightning |
| **Healer** | Support, holy damage | MP | MP, Magic Defense, Resistance | Holy |

### 4.1 Class level grants

Every class level grants **one class skill**, either **Active** (hotbar) or **Passive** (always on, applied by `StatService`/`SkillService` from data). Caster levels also grant **1 spell pick** from the class list (D2). Base stat growth per level comes from the class's stat lean, separate from these grants. Names are placeholders, plain descriptive (§2).

**Warrior**

| Lv | Grant | Kind | Effect | Tests |
|---|---|---|---|---|
| 1 | Cleave | Active | Melee arc | Multi-target hit shapes |
| 2 | Hardy | Passive | +Max HP %, +Physical Defense | Passive stat pipeline |
| 3 | Charge | Active | Dash to target, short stun | Movement validation, stun |
| 4 | Weapon Training | Passive | +Physical Attack, faster heavy attack | Passive modifying an action |
| 5 | War Cry | Active | Area taunt + self buff | Aggro override |

**Mage** (+1 spell pick per level)

| Lv | Grant | Kind | Effect | Tests |
|---|---|---|---|---|
| 1 | Arcane Line | Passive | Opens the arcane casting line (Circle 0–1) | Casting-line ceiling rule |
| 2 | Mana Flow | Passive | +MP regen | Resource regen modifier |
| 3 | Blink | Active | Short teleport | Server movement validation |
| 4 | Elemental Focus | Passive | +burn/slow chance | Proc-on-hit passives |
| 5 | Overcharge | Active | Next spell +damage, +cost | Buff consumed by next cast |

**Healer** (+1 spell pick per level)

| Lv | Grant | Kind | Effect | Tests |
|---|---|---|---|---|
| 1 | Divine Line | Passive | Opens the divine casting line (Circle 0–1) | Second casting line, incompatibility cap |
| 2 | Gentle Hands | Passive | +Healing done | Outgoing-heal modifier |
| 3 | Rebuke | Active | Holy knockback around self | Knockback, self area |
| 4 | Devotion | Passive | +Magic Defense, +Resistance | Mitigation passive |
| 5 | Lay On Hands | Active | Large single heal, long cooldown | Long cooldowns |

### 4.2 Spell lists (Circles 0–1)

8 spells per caster class; 5 picks by level 5, so the list always offers choice.

| Mage | Circle | Delivery | Tests |
|---|---|---|---|
| Light | 0 | Self | Utility cost rule |
| Kindle | 0 | Target object | Interactable world props |
| Spark | 1 | Projectile | Basic projectile |
| Firebolt | 1 | Projectile | Burn status |
| Frost Shard | 1 | Projectile | Slow status |
| Flame Fan | 1 | Cone | Cone hit shape |
| Ice Patch | 1 | Ground target | Ground AoE, root |
| Arcane Shield | 1 | Self | Damage absorb |

| Healer | Circle | Delivery | Tests |
|---|---|---|---|
| Glow | 0 | Ally | Utility cost rule |
| Purify Water | 0 | Target object | Interactable world props |
| Mend | 1 | Ally | Direct heal, ally targeting |
| Smite | 1 | Projectile | Holy damage |
| Cleanse | 1 | Ally | Remove poison/bleed |
| Renew | 1 | Ally | Heal over time |
| Shelter | 1 | Ally | Shield, friendly-target rules |
| Bless | 1 | Ally | Minor stat buff |

Moved to Circle 2+ (M1 or later): chaining lightning, area heal-and-smite, resurrection.

### 4.3 Disciplines (D3)

Focus pool `2 + floor(level / 7)` = 2. Dash Step (cost 1), Body Hardening (cost 1). Any class can learn them (Human heritage).

---

## 5. Goblins

Two tiers. Rigs are Part-based or simple-mesh on `Motor6D` (§8.2), placeholder look. Data in `Content/Enemies`, with a `tier` field.

### 5.1 Goblin Rabble (Lv 1–6, placed in this scope)

Loose raiding bands, no casters.

| Enemy | Lv | Role | Damage | Tags | Tests |
|---|---|---|---|---|---|
| Goblin Raider | 1–3 | Melee grunt, packs of 2–3 | Physical | — | Aggro, chase, leash |
| Goblin Slinger | 2–4 | Ranged, kites | Physical | — | Projectile dodge, kiting AI |
| Goblin Trapper | 3–4 | Lays poison snares, throws darts | Poison | — | Ground hazards, cleanse |
| Goblin Brute | 4–5 | Heavy, slow wind-up slam | Physical | Resist: physical | Telegraph + dodge, mitigation |
| Goblin Chieftain (optional elite) | 6 | 2 phases, calls a Raider pair at 50% HP | Physical | Immune: fear | Scripted timeline (§5.6), level-gap curve vs Lv 5 |
| Training Dummy | any | Static, configurable | — | Configurable | Damage numbers, resist math |

### 5.2 Goblin Warband (Lv 7+, data-only in this scope)

An organized war company with specialist roles. Mechanical reference: the research docs' summoned goblin troop. Names, item and composition counts are not copied. No summoning item, no protector-of-the-village role (§2). It is placed in the world from M1 or later. Here, members only spawn via `/spawn` in the Dev Yard to test interrupts and enemy support AI.

| Enemy | Lv | Role | Damage | Tags | Tests |
|---|---|---|---|---|---|
| Warband Soldier | 7–9 | Shielded melee, holds formation | Physical | Resist: physical | Formation AI |
| Warband Archer | 7–9 | Volley fire | Physical | — | Ground-target telegraphs |
| **Goblin Hexer** | 7–10 | Caster: poison bolt, curse, interruptible cast | Poison, negative energy | Vulnerable: holy | Interrupt/silence, cleanse |
| Warband Shaman | 8–10 | Heals and buffs goblins | Holy | — | Enemy healer priority |
| Wolf Rider | 8–10 | Fast flanker, charge | Physical | — | Fast pathing, knockdown |
| Warband Captain | 10–12 | Leader, buffs nearby Warband | Physical | Immune: fear | Leader aura, boss timeline |

Spawning: `Spawner` tags per zone, leash radius, respawn timers, active cap per zone (start at 20, tune after profiling).

---

## 6. Progression in scope

- XP from kills only (plus dev grants). Placeholder curve in `Content/Progression`, 5 levels.
- Class pick at a trainer. Adding a second or third class tests the build path and templates (D4).
- Loot: Grade I placeholder weapons/armor per class, minor potions, a goblin trophy material. Capacity/Imprints shown, not editable.
- Death: Standard rules (§3.9): XP debt + short stat penalty, respawn in Village Core.

---

## 7. Dev and testing tools

Server-gated: allowed only when `RunService:IsStudio()` or the UserId is on a dev allowlist in `ServerStorage`. Handlers validate and rate-limit like any remote (§5.4).

| Tool | Form |
|---|---|
| `/level n`, `/class add/remove X`, `/xp n` | `TextChatCommand` |
| `/spawn enemy lv`, `/clear`, `/god` | `TextChatCommand` |
| `/latency ms` (simulated) | `TextChatCommand`, Studio only |
| Damage log, aggro/state overlay | Studio-authored debug `ScreenGui` + controller (no code-built UI, §6.1) |
| Training dummies | Dev Yard, configurable via attributes |

---

## 8. Assets

Rules live in `game-design.md` §7.5. Per-pack use here:

| Pack | Use |
|---|---|
| retro-fantasy-kit | Village blockout: walls, roofs, fences, barrels, crates, towers, docks, trees; goblin palisade from fortified walls |
| retro-textures-fantasy | Village and camp surfaces |
| prototype-textures | Greybox for Dev Yard and unfinished areas |
| foliage-sprites | Billboard crops, grass, bushes |
| game-icons, game-icons-expansion | Placeholder skill, passive, status and HUD icons |
| ui-pack (+ Kenney Future font), fantasy-ui-borders | HUD and menu frames |
| input-prompts | Keyboard/gamepad/touch prompts |
| crosshair-pack, cursor-pack | Aim reticle, cursors |
| particle-pack, smoke-particles, light-masks | Spell and impact VFX textures |
| pattern-pack, development-essentials | UI fills, debug pixels |
| impact-sounds, rpg-audio, interface-sounds, ui-audio | Reference only; audio comes from Toolbox this scope |
| sci-fi-sounds, digital-audio | Excluded (off-tone) |

Toolbox audio needed: footsteps (grass, wood), melee swing/hit, spell cast/impact per element, heal chime, goblin bark/hurt/death, UI click/open/close, level-up sting, village ambience loop, combat music loop.

---

## 9. Exit criteria

1. Join → pick class at trainer → kill goblins → reach level 5 in each class, on desktop and phone emulator.
2. Every class skill, passive and spell in §4 resolves through the server path. Passives show in stats. Rejected casts roll back client prediction.
3. Circle 2 spells are refused at casting-line level 5 (unit test + playtest).
4. Each Rabble AI state (idle, patrol, aggro, attack, return) observed. Leash and respawn work. Hexer interrupt works in the Dev Yard.
5. Multiclass to 5 total levels using each D4 template.
6. Dev commands refused for non-allowlisted users in a published test.
7. Every asset in the place has a register row. No hard-coded asset ids.
8. Format, lint, typecheck, tests and `rojo build` pass.
