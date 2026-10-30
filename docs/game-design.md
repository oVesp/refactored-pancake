# Game Design — Roblox Action MMORPG (working title: *Worldtree*)

Status: design baseline v0.1. This is the **current design**; anything in the research docs that conflicts with it is stale or reference-only.

Research docs ([overlord-world-compendium.md](overlord-world-compendium.md), [low-level-human-design.md](low-level-human-design.md), the two JSON files) are **source material for mechanics only**. They contain series proper nouns. Nothing from them is copied into the game, the data modules, the UI or the assets without passing §2.

---

## 1. Vision and pillars

A fantasy **action MMORPG** that recreates the *feel of a late-generation, build-heavy full-dive MMO*: huge build space, class stacking, data-driven gear crafting, guild strongholds, and a living world with strong and weak zones. It is **not** an adaptation of any story. There is no protagonist, no canon cast, no canon plot.

| Pillar | Meaning in practice |
|---|---|
| **Build identity** | Characters are defined by *which classes you stacked and in what order*, not by a single class pick. Respecs are rare and costly. |
| **Real-time action** | Moment-to-moment play is dodge, position, time skills. Stats decide *how much*, skill decides *whether*. |
| **Readable power curve** | A level 5 and a level 50 never feel the same. Zones and enemies telegraph danger honestly. |
| **Player-made progress** | Crafting, guild holds, trade and tournaments matter more than loot treadmills. |
| **Roblox-native** | Built to run on phone, tablet, console and desktop, in short sessions, with a mixed-age audience. |

### 1.1 What "faithful" means here
Faithful = **systems and structure**, never content:

| Keep (systems) | Replace (content) |
|---|---|
| Level cap 100 = race levels + class levels; class caps 15 / 10 / 5 | Character names and direct references to unique characters (generic canon names are allowed, §2) |
| 1 spell pick per caster level; spell power in Tiers gated per magic system (§3.2) | Spell/skill names that point at a unique character |
| Items graded by *data capacity* filled with crystals | Items, sets and artifacts that point at a unique character |
| Guild strongholds with an NPC level budget | Every character and event (canon place and faction names are allowed, §2) |
| A native warrior-skill layer powered by *focus* | Technique names that point at a unique character |
| Nine realms as top-level world structure | The source's realm-to-theme pairings (public-domain realm names are fine, §2) |
| Penalty-bearing death, PK flags, tournaments | Any story beats |

---

## 2. Originality and content-safety policy

Hard rules. They apply to code, data, UI text, textures, audio and marketing.

1. **No characters, no events, no plot.** No one in the game may be a recognizable character from the source series, a lookalike, or a renamed copy (same role + same gimmick counts as copying).
2. **Generic canon names are allowed; character names are not.** Generic names from the source series (classes, spells, monsters, systems, terms such as Tier, places, factions, items) may be used. Forbidden: names of characters and direct references to unique characters (a personal name, title, epithet, guild or named group that identifies them). Public-domain names (myth, folklore and history: Midgard, Yggdrasil, goblin, valkyrie, rune) stay fine. Rule 1 still applies: no characters, events or plot.
3. **Mechanics are fair game, expressions are not.** A *rule* (1 spell pick per level) is borrowable; a *stat block, class list, skill list or level table* copied verbatim is not.
4. **Title and key art are original.** "Worldtree" is a placeholder; run a clearance check before any public page uses it.
5. **Norse myth is public domain.** Realm, creature and god names from the myths may be used directly. What stays forbidden is the source's *expression*: its realm-to-theme assignments, its race-to-realm placements, and any character or item built on a myth name the way the source built it.
6. **Every content entry carries provenance** (§7.1): author, origin (original / generic / licensed asset), license, review state. Unreviewed content cannot ship.
7. **Review gate:** a reviewer checks each new content batch against a *forbidden-terms list* kept outside the repo's public data (it holds character names and unique-character references from the series). Reviewer signs off in the content register.

### 2.1 Terminology map (use the right column in all player-facing and internal names)

| Mechanic | Source-game term (allowed since the §2 rule 2 change; project terms stay where already in use) | Project term |
|---|---|---|
| Spell power ranks | "Tier", "Super-Tier" | **Tier** 0–5 in the 1–30 scope (§3.2); higher Tiers and **Apex** rites later |
| Native warrior skill layer | "Martial Arts" | **Disciplines** |
| Resource for Disciplines | — | **Focus** |
| Gear power budget | "Data capacity", "data crystals" | **Capacity**, **Imprints** |
| Gear grades | named list | **Grade I–X**, plus **Singular** (unique, rule-bending, count-capped) |
| Guild fortress | stronghold | **Hold** |
| Class "levels" | job class | **Class** (Callings optional flavor) |
| Race | race | **Heritage** (Human first) |
| Special cap-limited items | "World Items" | **Singular relics** |
| Champion title | World Champion | **Realm Victor** |

---

## 3. Core systems design

All numbers below are **starting points** to be tuned. They live in data modules, never in logic.

### 3.1 Character model
- **Level 1–100** at the data-model level from day one. Launch caps are lower per milestone (§10).
- **Heritage**: Human at launch. Humans have **no heritage levels**; all levels go into classes. Future heritages with heritage levels (stat-heavy, ability-heavy, drawbacks) slot in without schema changes. The character creator lists the three families (Human, Demi-Human, Heteromorph) with every race but Human locked ([character creation](systems/character-creation.md)).
- **Classes**: base cap 15, high cap 10, rare cap 5. Minimum 7 classes to reach 100. Prerequisites gate high/rare classes. Every strong class carries a penalty.
- **Class slots**: a character can hold many classes; UI must show *build path* (order + levels).
- **Stats** (9): HP, MP, Physical Attack, Physical Defense, Agility, Magic Attack, Magic Defense, Resistance, Special. Derived: crit, move speed. Stats never shorten the GCD or cast times; only the `Haste` item affix does (§3.5).
- **Death & progression safety**: see §3.9.

### 3.2 Magic (Tiers)
- **Four magic systems** (casting lines): **Arcane, Divine, Spiritual, Alternative**. Each caster class belongs to one. Caster levels of different systems are tracked independently and never sum.
- **1 spell pick per caster class level** (`SPELL_PICKS_PER_LEVEL`, `Tuning.Magic.SpellPicksPerLevel = 1`), chosen from that class's list. This is the target, not a placeholder.
- **Tier gate per system** (tunable, `Tuning.Magic`): Tier 0 cantrips and Tier 1 at line level 1; Tier *n* ≥ 2 at line level `7 × (n − 1) + 1` (`TierStep = 7`). T1 at line levels 1–7, T2 8–14, T3 15–21, T4 22–28, T5 29–30. `MaxTier = 5` for the 1–30 scope. Levels 1–5 therefore cast Tiers 0–1 only.
- **Tier ceiling follows the system's own line level**, not total level. Levels in an incompatible system cost one Tier (`MixedLinePenalty`, never below Tier 1). This is the main anti-"hybrid cheese" rule.
- The caster-class roster and the spell grimoire live in the design spreadsheet `overlord_yggdrasil_early_game_bestiary_with_classes_and_grimoire.xlsx` (tabs *Caster Classes* and *Grimoire*).
- Tier 0 utility spells exist but cost like Tier 1 (soft sink, flavor).
- **Canon power scale** (owner, 2026-10-30): spells keep their canon names until release and sit at the canon Tier of their power ([Tier spells reference](https://overlordmaruyama.fandom.com/wiki/Tier_Spells)). Tier 1 is weak: Magic Arrow is the basic attack, and elemental damage (fire, ice, lightning) starts at Tier 2 (Thunderlance) and Tier 3 (Fireball, Lightning). Each class list covers at least one spell per tradition available at its Tiers plus the essentials (Light, Light Healing, Create Water). Spells above the gate stay in `Content/Skills` off the class lists.
- Spells deliver through **real-time delivery types**: projectile, cone, ground target, self, ally, summon. Magic damage is not blockable by physical armor; it is reduced by magic defense/resistance.
- Resurrection spells exist, scale with Tier, cost XP/levels/materials.
- Launch content: Tiers 0–3 (alpha), 4–5 (beta). No Apex at launch.

### 3.3 Disciplines (native warrior layer, Human-eligible)
| Rule | Value |
|---|---|
| Resource | **Focus**, separate from MP/stamina; passive drain while Disciplines are active |
| Capacity | `2 + floor(level / 7)` (level 5 → 2; level 29 → 6); overdraw +1 with fatigue penalty |
| Cost | basic 1, advanced 2, signature chains 3 |
| Acquisition | **Taught by trainers and sparring**, not bought from a skill tree: attend training events, win spars, survive hard fights |
| Time to learn | ~1 in-game "season" baseline; "gifted" characters halve it |
| Stacking | Several Disciplines run at once; chains fuse into a combo with one animation |
| Anti-player-skill rule | No Disciplines for heritages flagged *Outsider* (future), a deliberate asymmetry mirroring the source system's design intent |
Disciplines are **toggles and short buffs on top of action combat** (stance, parry window, dash, weapon enchant), not extra hotbar spells.

Starter set (≈12 for the vertical slice, original names TBD): strike power, body hardening, evasion, perception, dash step, shield bash, weapon edge, pain suppression, air blade, counter stance, speed surge, armor-piercing thrust.

### 3.4 Items and Capacity
- Every item has **base grade** and **Capacity**. **Imprints** (modifier shards) consume Capacity. High grades need rare Imprints and rare base materials.
- Item types: weapon, shield, armor, accessory (limited ring slots), consumable, material, scroll, tool.
- **Weapons decide the basic attacks** (Dragon's Dogma-style, each weapon plays differently): fists (default), sword, bow, staff and wand; a shield goes in the off hand of a one-handed weapon. Details: `docs/systems/weapons.md`.
- **Scrolls** require mastery of the matching magic line to use (drives class value).
- **Singular relics**: hard-capped world count, unique, rule-bending; may be lost on death in PvP zones. Launch with **zero**; they arrive in a timed event design, never from random drop tables.
- Metal gear: high defense, low item HP, resists pure energy. Durability exists and is slow.
- **Haste** is an item-only affix: it shortens the GCD and cast times (capped at `Tuning.Combat.Gcd.MaxHaste`). No stat, passive or status grants it.

### 3.5 Combat (action)
- **Client** sends intent (skill id, aim vector, sequence, optional target). **Server** validates and resolves. See §6.4.
- Controls: Mouse 1 (pad R1) light attack chain, Mouse 2 (combat mode; pad R2) heavy, F (pad L2) guard (all from the equipped weapon; the bow aims and draws while heavy is held and shoots on light), skill hotbar (6 slots mobile, 8–10 desktop), dodge, block/parry window. Double-tap W to run (`Tuning.Base.Run`) until W is released or the character stops.
- **Targeting (hybrid)**: an automatic soft target (enemy nearest the screen centre, sticky in crowds) plus an optional lock (Tab / R3 / Target button cycle; tap an enemy on touch). Each delivery uses it differently, so archetypes play differently: melee swings where you face with short-range magnetism; skillshots (`Projectile`) are free-aim with a small touch/pad assist; mage `Target` spells seek the target and cannot miss but have a cast time and stop on walls; `Ground` lands on the screen centre, or on the target off the mouse; support (`Ally`) takes the ally at the screen centre or the wounded ally nearest it, else the caster. AoE has no target cap.
- **Camera**: exploration mode (normal camera) by default; a toggle (Left Alt) switches to combat mode, shift lock third person over the shoulder with the character facing the camera. A target lock frames the locked enemy in either mode. Every attack aims through the screen centre or at the locked target, so the mouse cursor never steers an attack. Menus release the lock while open. Details: `docs/systems/combat.md`.
- **Timing (FFXIV-style)**: spells and weaponskills share a **global cooldown** (GCD, 2.5 s); other class actives are **off-GCD** (oGCD) with their own cooldowns and are woven between GCDs. Every non-basic action has a 0.6 s **animation lock**, giving two weaves per GCD. Cast-time spells are cancelled by moving, except in the last 0.5 s (**slidecast**); a cancelled cast costs nothing and gives the GCD back. A press within 0.5 s of an action becoming ready is queued. Basic attacks (light/heavy) stay outside the GCD but commit the player: each has a windup before the hit and a recovery after it, during which the player is slowed and cannot act, except to dodge-cancel (see combat.md); the light attack is a three-hit chain (jab, cross, heavier finisher) that continues while presses land within 0.8 s of each other. Skills have no combos. Enemies keep per-skill cooldowns. Details: `docs/systems/combat.md`.
- **Damage model**: `(base + stat × ratio) × (1 + bonus) × type multiplier × crit × level gap × 100 / (100 + defense)` (`Shared/Formulas.ResolveDamage`), with damage types (physical, fire, cold, lightning, acid, holy, negative energy, poison, mental) and resist/immune/vulnerable tags.
- **Level gap curve**: strong smoothing instead of a hard wall: ≥10 levels above → large reductions, ≥30 → near-zero without penetration items/skills. The wall is faithful; the smoothness avoids hard-lock frustration.
- **Status effects**: stun, slow, root, silence, fear, charm, burn, poison, bleed. Boss immunity pattern is explicit in data (e.g. "immune: mental").
- **Targeting rule**: party and guild members never take friendly fire.

### 3.6 Progression
- Per-class level curves; slow early levels, long mid-game.
- **Every class level grants one class skill**, either **Active** (hotbar) or **Passive** (always on, applied from data by `StatService`/`SkillService`), plus the class's base stat growth. Caster levels also grant spell picks (§3.2).
- XP sources: monster kills, quests, discovery, crafting, tournaments.
- **Classes unlock via a requirement set**: every requirement must pass. Types: specific class level, category class level (summed levels of tagged classes), total level, kill counts, achievements and quest chains, karma, heritage, item turn-ins. Rare classes are one-per-tournament or event-gated. Roster, requirements and per-class grants: [classes](systems/classes.md).
- Spell/Discipline learning is **not pure grind**: trainers, scrolls, rare drops.

### 3.7 World structure
- **Nine realms** as long-term structure; launch with **one hub + one starter realm**. Starter realm: **Midgard** (first slice: [scope 01](scope/01-midgard-testing-grounds.md), at the Harbor), one continent laid out from the owner's sketch (20,480 studs, built and approved region by region; the Harbor is the starter village): the Holy Kingdom and the Dragon Empire hold most regions, the neutral Adventurers hold the Central Capital and the Harbor, and minor factions (Elves, Dragons, Undead) hold the rest. A seeded generator makes similar but different continents from the template ([world generation](systems/world-generation.md)). Each realm is its own *Place* in one universe eventually; early builds run as zones in one place behind a `ZoneService` abstraction so splitting later is mechanical.
- **Density**: realms are sharded servers (target 40–60 players per server) with instancing for dungeons, strongholds, tournaments.
- Danger **banding by zone** (enemy level ranges, PK rules, loot) so power is legible: safe hub → starter fields → ruins → deep zones.
- **Open world (experiment, branch `exp/open-world`)**: the world runs without the player, in the vein of an open sandbox RPG. Factions (`Content/Factions`) fight and help each other by a relation table; town guards hold posts and patrol in formation, caravans and travelers walk the roads, townsfolk thin out at night, and monsters come from nests that send squads out unseen to roam a territory. Zone bands and the safe village stay. See [open world](systems/open-world.md).

### 3.8 Social, guilds, Holds
- Parties (up to 6), guilds (cap configurable, default 40), friends via Roblox.
- **Hold**: an instanced reserved-server space per guild. Construction budget in currency plus **NPC level budget** (cap per NPC, total pool per Hold tier). Hold NPCs can't leave the Hold. Guild weapon concept = a **Hold Heart** object; destroy it in a siege and the Hold falls. Sieges are scheduled, opt-in, with protections for casual guilds.
- Trading: escrowed, rate-limited, logged; value-capped for new accounts.
- Tournaments: bracketed, instanced, spectatable; the winner of each realm bracket earns a unique cosmetic-plus-gear prize and a title.

### 3.9 Death and penalty (a deliberate deviation)
Faithful rule: lose levels, drop gear, delete at level ≤5. **Rejected as default on Roblox:** short sessions, young audience, and the first minutes would feel punishing. Replacement:

| Mode | Rule |
|---|---|
| **Standard** (default) | XP debt (earn it back), temporary stat penalty, durability loss. Gear drops only in flagged PvP zones. |
| **Ironbound** (opt-in realm/server) | The faithful penalty: level loss + one dropped gear piece. Protected tier: players below level 6 drop to level 1 instead of deletion (no permanent loss). Better rewards/ladders. |
| **Resurrection** | Spell/item based, scaled by Tier, costs materials; a corpse run is available in Standard. |

### 3.10 Economy
Faucets: monsters, quests, vendors (small), tournaments. Sinks: crafting, repairs, Imprints, Hold upkeep, respec items, trainer fees. **No pay-to-win**: money buys time or cosmetics (§9.4). Every currency has a documented source/sink line in the balance sheet.

---

## 4. Early game slice (levels 1–5, Human)

From [low-level-human-design.md](low-level-human-design.md), adapted to this document's terms.

- 5 levels in classes only. Build templates: specialist (5), duo (3+2), dabbler (2+1+1+1).
- First classes: **Fighter, Mage, Healer**. Warrior (melee) and Ranger (ranged) are high-class specializations of Fighter, unlocked at Fighter 5 ([classes](systems/classes.md)). Planned starter set (original names TBD): front-line fighter, evasion fighter, bare-hand adept, scout, healer, spellcaster, apothecary, laborer. Dabbler needs a 4th class.
- Spells: Tiers 0–1 for casters (Tier 2 at casting-line level 8, §3.2); 1 pick per caster level (`SPELL_PICKS_PER_LEVEL`).
- Enemies: Goblin **Rabble** (Lv 1–6, raiding bands, no casters) and the **Skeleton** (Lv 1–3, unarmed undead). Goblin **Warband** (Lv 7+, organized company with casters, healers, riders and a leader) is the next band.
- Disciplines: Focus 2; learn 2 by level 5 via the tutorial trainer.
- Gear: Grade I–II only; no Singular anywhere.
- Death: Standard rules; Ironbound unavailable until post-tutorial.
- Tutorial zone teaches: movement, light/heavy attack, dodge, skill bar, Focus toggle, spells, loot, talk to trainer, party up.

---

## 5. Roblox technical architecture

### 5.1 Toolchain (decisions)
| Concern | Decision | Reason / alternative considered |
|---|---|---|
| Code source of truth | **Rojo 7** project + Git | Reviewable diffs, linting, CI. *Script Sync* is the official alternative but offers less project-file control. Do not run both on the same scripts. |
| UI/instance authoring | Layout objects + templates as declarative Rojo files (`.model.json` for UI, `.rbxmx` for models); re-saved from Studio when a designer restyles them | Never built at runtime (§6). Declarative files diff cleanly and round-trip through Studio. |
| Studio automation | **Studio MCP** for inspection, UI edits, playtesting, Luau probes | Complements Rojo; does not replace it. |
| Toolchain | **Rokit** (`rokit.toml`) pins rojo, stylua, selene, luau-lsp, lune, wally | One `rokit install` reproduces every tool version. |
| Typing & lint | `--!strict` Luau everywhere, `luau-lsp`, `selene`, `stylua` | Catches bugs at edit time. |
| Packages | **Wally** with pinned versions; vendor reviewed copies | No unpinned dependencies. |
| Tests | **Lune** unit tests for pure modules (`tests/specs/*.spec.luau`; `lune run tests/run <text>` filters by spec or test name; `Coverage.spec` fails on a Shared module with no spec), Studio playtests for integration, MicroProfiler. A service's decisions live in a pure Shared function so a spec can reach them; the service keeps the wiring. | Lune runs in CI without Studio. Pure modules take no instance requires so they load in both runtimes. |
| Build/publish | `rojo build` in CI; Open Cloud upload with scoped keys | Keys never in repo. |
| External tools | Blender (bpy headless), Python or Node scripts, Lune | §8. |

Environment note: Studio MCP and Blender MCP tools are available in this workspace (Studio connection to an open place not yet verified). Checked-in `tools/blender/` scripts stay the source of truth; MCP is for interactive work.

### 5.2 Repository layout
```
default.project.json
src/
  ReplicatedFirst/            Loading screen only
  ReplicatedStorage/
    Shared/                   Types, Constants, Util, Net (remote definitions), Signal
    Content/                  Data modules: Classes, Skills, Statuses, Disciplines, Items, Enemies, Zones, Tuning, Strings, Assets (plain tables)
    UiTemplates/              Row/slot/nameplate templates cloned by controllers
    Vfx/                      Effect templates (.model.json) played through ForgeVFX (docs/systems/vfx.md)
    ForgeVFX                  VFX Forge emit module, synced from vendor/ForgeVFX (runtime-only licence)
    Packages/                 Wally output
  ServerScriptService/
    Server/
      Bootstrap.server.luau   Single entry; requires and starts Services in order
      Services/               DataService, StatService, CombatService, SkillService, AIService, SpawnService, ...
  ServerStorage/
    Templates/                Enemy models, hold interiors
    ContentServerOnly/        Drop tables, dev allowlist, formulas players must not see
    WorldGen/                 Terrain applier (Apply.luau) + generated Data/ (tools/terrain/build.luau)
  Workspace/Map.rbxmx         Generated gameplay objects: zones, NPCs, dev yard (tools/world/build.luau)
  StarterPlayer/StarterPlayerScripts/
    Client/
      Bootstrap.client.luau
      Controllers/            InputController, CombatController, UIController, CameraController, ...
  StarterGui/                 Authored ScreenGuis (.model.json)
assets/                       Source art (Blender, PSD, SVG), not synced into the place
tools/                        gate.sh (quality gate), scan.sh, world/build.luau (Map gameplay objects + templates), worldgen/ (world map preview, bake, mesh library upload), terrain/build.luau (old Midgard terrain), Python/Node/Lune/Blender scripts
content/register.json         Content register (§7.1), validated by tests/specs/Register.spec.luau
docs/
tests/                        Lune runner + specs/*.spec.luau
.githooks/                    pre-commit (gate), commit-msg, Git LFS hooks
```

### 5.3 Script standards
- **One entry script per side.** Bootstrap `require`s modules, calls `Init(deps)` on all, then `Start()` on all. No script owns gameplay logic besides bootstrap.
- Modules return a typed table; no `_G`, no `shared`, no global state.
- `task.*` only; never `wait`, `spawn`, `delay`. `Animator`, `TweenService`, `CollectionService` tags and Attributes; no deprecated BodyMovers or `Humanoid:LoadAnimation`.
- **Services/Controllers pattern** (`Service` server, `Controller` client). Cross-module calls through dependency injection at `Init`, not deep `require` webs.
- Cleanup: every connection goes in a Maid/Janitor and is disconnected on teardown.
- Configure instances before parenting; set `Parent` last.
- All cloud calls (`pcall`): DataStore, Marketplace, Http, Teleport.
- Constants and tuning live in `Content/` or `Shared/Constants`. No magic numbers in logic.
- Formatting by `stylua`, lint by `selene`, types by `luau-lsp`; CI blocks on all three.
- Naming: `PascalCase` modules/classes/services, `camelCase` locals/functions, `UPPER_SNAKE` constants, remotes named `Verb` + `Noun` (`UseSkill`, `EquipItem`).
- Every public module function carries a short doc comment stating its contract, and is typed. Comment and logging rules: §5.12. Commit rules: §5.11.

### 5.4 Authority and networking
- **Server authoritative**: stats, inventory, XP, drops, damage, cooldowns, spawns, teleports, currency, Hold state.
- **Client**: input, prediction, camera, UI, cosmetic VFX/audio.
- **Remotes**: declared once in `Shared/Net` (name, payload type, direction, rate limit). Server creates them at startup; the client waits for them. Every handler: schema-validates arguments, checks player state, applies a **per-player per-action rate limiter**, and rejects silently with a counter. No `InvokeClient`, ever.
- **State sync**: replicate display state with **Attributes** on Player/Character/NPC (HP, MP, Focus, status flags) and send bulk/rare data (inventory, quest log) as snapshot + delta remotes on demand. No `Value` objects.
- **Data in remotes** must be small, typed, and use ids not strings of content. Consider a buffer-based codec only after profiling shows need.
- **Network ownership**: players own their character; pushable props/projectiles are server-owned or explicitly assigned and validated.

### 5.5 Combat implementation
1. Client: input → target pick (`TargetController`) → local predicted animation/VFX → `UseSkill(skillId, aim, seq, target?)`.
2. Server: check alive, not stunned, skill known, cast state and animation lock, cooldown and GCD, target (alive, hostile or allied as the delivery needs, in range with rewind), resource cost, cast state, facing tolerance.
3. Server simulates the hit via spatial queries (`GetPartBoundsInRadius`, raycasts, overlap shapes) in the **skill's authoritative timeline**; animation markers are cosmetic cues, never proof of a hit.
4. **Lag compensation**: keep a short ring buffer (~250 ms) of enemy/player positions; rewind within a validated window for hit checks. Cap the rewind; never trust a client timestamp beyond it.
5. Damage → `DamageService` (type, resist, level-gap curve, crit, status). Result replicated; client reconciles prediction (rollback on reject).
6. Skills are **data**: id, class requirement, cost, GCD flag, cooldown, cast time, delivery, hit shape, effects list, animation id, VFX id, sound id.

### 5.6 Enemies and AI
- Server-only AI: state machine (idle, patrol, aggro, position, attack, disrupt, flee, regroup, stagger, return), coordinated per target by `SquadService` (attack tokens; docs/systems/ai-and-spawning.md, Group combat).
- `PathfindingService` with **staggered** recompute (per-NPC jitter), cached agent params, `pcall` around compute, explicit timeouts, blocked-path handling.
- Detection by spatial queries, not per-frame player scans.
- Open-world population (`PopulationService`, `GroupService`, [open world](systems/open-world.md)): faction relations decide hostility; garrisons, patrols in formation, caravans, travelers, townsfolk and hidden monster nests whose squads roam a territory. Groups far from every player are data only and get bodies near players (`Tuning.Population.MaxBodies` caps bodies). `SpawnService` builds the bodies.
- Heavy AI moves to **Actors/parallel Luau** only after profiling shows need.
- Boss mechanics are scripted timelines using the same skill/effect pipeline.

### 5.7 World, streaming, scale
- **StreamingEnabled** on. Client code never hard-references far parts; use `WaitForChild` with timeouts and persistent models for must-have destinations.
- Place split path: hub place + realm places + reserved-server instances (dungeons, Holds, tournaments) via secure server-side `TeleportService:TeleportAsync`. Whitelist destinations, rate-limit teleports, never trust client-supplied place ids.
- **Teleport can't be tested in Studio**; need a published test universe and a checklist.
- Cross-server: `MemoryStoreService` for server directory and short-lived state, `MessagingService` for announcements. No cross-server coordination at launch.
- Chat: `TextChatService`. Names/filtering handled by Roblox; any custom text (guild names, titles) must go through `TextService:FilterStringAsync`.

### 5.8 Data module (stub now, real later)
The real Data module arrives later. Now we build against a **contract** so nothing changes when it lands.

```lua
-- DataService contract (server only)
DataService.Get(player): Profile?                 -- live in-memory table
DataService.Update(player, fn: (Profile) -> ()): ()
DataService.Changed: Signal<(player, path)>       -- change notification
DataService.WaitForProfile(player): Profile?      -- yields until loaded or player leaves
```
Rules from day one:
- **In-memory only**, keyed by `UserId`, no persistence for now.
- Profile is **serializable-only**: numbers, strings, booleans, plain tables; no Instances, functions, metatables, cycles, NaN/inf. Test with `HttpService:JSONEncode`.
- Carries `schemaVersion`; a `Migrate(profile)` function exists even if it is a no-op.
- Separate **persistent** (progress, inventory) from **session** (cooldowns, aggro) state; only persistent lives in the Profile.
- Systems never touch DataStores; only the future Data module does.
- A single `Release(player)` path on leave, so adding save-on-leave later is one change.

### 5.9 Performance budgets (initial targets)
| Area | Target |
|---|---|
| Devices | Stable on low-end phones; test matrix: low phone, mid tablet, console, desktop |
| Frame | 60 fps desktop, ≥30 stable low-end |
| Server | Heartbeat under budget at target player + NPC count (profile with MicroProfiler) |
| Active AI per server | Hard cap per zone, e.g. ≤60 agents, tune after profiling |
| Parts/mesh | Instance budgets per zone, Level-of-detail via streaming |
| UI | Limit transparent overdraw, pool particles, avoid hundreds of live tweens |
| Memory | Track with Developer Console and Scene Analysis; no unparented instance growth |
| Remotes | Rate-limit and batch; track bytes/sec per player |

### 5.10 Security and anti-exploit
- Never trust the client for: position claims in combat, cooldowns, damage, item grants, purchases, teleports.
- Movement sanity checks, remote rate limiting, argument validation, server-owned economy.
- Keep secrets (drop tables, formulas) in `ServerStorage`/`ServerScriptService`; `CanQuery` and collision groups are not confidentiality.
- **Free models and Creator Store assets** are audited (scripts removed or reviewed) before entering the repo; no unreviewed third-party scripts.
- Monetization grants only in `ProcessReceipt`/verified pass callbacks.

### 5.11 Version control and automated commits

**Policy:** work is committed automatically at the end of each completed logical unit; pushing, tagging and releasing stay manual. Where a request conflicts with best practice here, best practice wins and the deviation is stated in the commit body or the decision log (§11).

| Rule | Detail |
|---|---|
| Repository | Git, initialized at M0. `main` is always buildable. After cloning: `rokit install`, `git lfs install --local`, `git config core.hooksPath .githooks`. |
| Branching | Short-lived `feat/…`, `fix/…`, `content/…`, `chore/…` branches off `main`; squash or rebase merge; no long-lived feature branches. |
| Commit unit | One logical change per commit: a feature slice, a fix, a content batch, a refactor. Never mix refactor + behavior change, or code + unrelated content. |
| Trigger | Automatic after a unit passes its gate: format, lint, typecheck, tests, `rojo build`, content validators. A failing gate means no commit and a reported failure. |
| Message format | Conventional Commits: `type(scope): imperative summary` (≤72 chars). Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `content`, `build`, `chore`. Body explains *why*, not what. Closing attribution line as required by the tooling. |
| History lives in Git | Change history, authorship, dates, ticket notes and "what changed" never go in script headers or inline comments (§5.12). `CHANGELOG.md` is generated from commit types at release. |
| Never committed | Place files (`.rbxl`, `.rbxlx`), `sourcemap.json`, build output, Open Cloud keys, cookies, `.env`, Blender autosaves, large raw sources (use Git LFS or external storage for `assets/` binaries). |
| Hooks | Pre-commit runs `tools/gate.sh`: `stylua --check`, `selene`, `luau-lsp analyze`, Lune tests, `rojo build`, raw-print scan, secret scan, forbidden-terms scan (§2). Commit-msg: Conventional Commits validator. Hooks are never bypassed with `--no-verify`. |
| Forbidden-terms list | Outside the repo: `$YGG_FORBIDDEN_TERMS` or `~/.yggdrasil/forbidden-terms.txt`; CI reads the `FORBIDDEN_TERMS` secret. The scan fails closed when the list is missing. Myth names allowed by §2 are not on it. |
| Pushing | Manual only: a human pushes, opens the PR, and merges. No force-push to shared branches. |
| Rewriting | Local unpublished commits may be amended or squashed; published history is not rewritten. |
| Content commits | Content batches reference their register entries (§7.1); assets and the data rows that use them land together so `main` never has dangling ids. |
| Studio-authored work | UI and instances authored in Studio are exported to the repo (`.rbxmx`) and committed in the same unit as the controller that binds them. |

### 5.12 Comment and logging standards

**Comments**
- Comment **what a function promises**, not what each line does. A short doc comment above a public function is encouraged and expected: purpose, parameters, return value, side effects, and error behavior.
- Inline comments only for non-obvious *why* (a hack, a Roblox quirk, a performance trade-off). If a comment restates the code, delete it; if it needs a paragraph, move it to `docs/systems/<name>.md`.
- No commented-out code, no TODO graveyards (a TODO names an owner/issue or does not exist), no banner art, no section dividers made of symbols.
- **No logs of change history in scripts**: no "Edited by", "v1.2 changed X", dates, or revision tables. That is Git's job (§5.11).
- Types and clear names carry the meaning; prefer renaming over commenting.

**Runtime logging**
- Scripts do not scatter `print`/`warn`. Logging goes through one `Logger` module with levels (`debug`, `info`, `warn`, `error`), a category tag per system, and a global level switch; debug is off in production.
- Log lines carry context (ids, not personal data) and are rate-limited for hot paths. No secrets or personal information in logs.
- Gameplay diagnostics, balance data and exploit signals are **telemetry events** (§9.2), not console output.
- Temporary debugging prints are removed before commit; the pre-commit scan flags raw `print(` outside `Logger`.

---

## 6. UI/UX standards

### 6.1 The rule
UI is **authored with Roblox's own services and objects**, then bound to logic. It is **never** assembled instance-by-instance in code.

| Do | Don't |
|---|---|
| Author each screen in Studio as a `ScreenGui` with `Frame`, `CanvasGroup`, `ScrollingFrame` | Spawn dozens of Frames/Labels from a Luau script to "draw" a screen |
| Layout with `UIListLayout`, `UIGridLayout`, `UIPageLayout`, `UIFlexItem`, `AutomaticSize` | Calculate positions by hand |
| Constraints: `UISizeConstraint`, `UIAspectRatioConstraint`, `UIScale`, `UIPadding` | Hard-coded pixel offsets |
| Appearance: `UICorner`, `UIStroke`, `UIGradient`, shared **Style Editor / StyleSheet** | Per-element color/font literals in scripts |
| Repeated items: **template instances** in `ReplicatedStorage` cloned per entry | Constructing a row with `Instance.new` chains |
| Item/spell previews: `ViewportFrame` | Static baked screenshots for 3D items that rotate |
| World prompts: `ProximityPrompt`; nameplates/damage numbers: `BillboardGui` | Custom raycast + hand-built prompts |
| 2D effects: pooled `ImageLabel`s + `TweenService` | `ParticleEmitter` in ScreenGui (does not render) |

### 6.2 Structure
- `StarterGui/<Screen>` holds visual hierarchy only. `Controllers/<Screen>Controller` finds named children (by attribute/tag or a typed lookup table), binds `Activated`, updates text/images, and owns tweens.
- **One `UIController`** manages open/close, layering (`DisplayOrder`), focus, back stack, gamepad navigation, mobile layout.
- **View-model rule**: controllers read replicated Attributes/snapshots and never mutate authoritative state.
- Names are stable contracts: instance names/attributes used by code are prefixed (e.g. `Bind_HpBar`) and validated by a startup check that errors loudly if missing.

### 6.3 Responsive, safe, accessible
- Scale + `AnchorPoint` everywhere; test at phone-portrait-landscape, tablet, 16:9 and ultrawide.
- `ScreenGui.ScreenInsets` set per screen (safe zones, notches); hide default touch controls only if replaced.
- Input: `.Activated`, `ContextActionService` bindings with remap, gamepad focus (`GuiService`) on every interactive screen.
- Accessibility: text scale option, colorblind-safe status palette, flash/shake reduction, subtitle/sound-cue options, hold-vs-toggle options.
- Localization: all strings via `LocalizationTable`/`LocalizationService`; no hardcoded player-facing text in logic; layouts must tolerate +40% text length.

### 6.4 Screens needed (core)
Character creator (race, body, hair, facial hair, outfit, starter class and spell, name), HUD (HP/MP/Focus/XP/hotbar/buffs/minimap), character sheet (classes path), skill/spell book, discipline list, inventory + equipment, item inspector (Capacity bar, Imprint slots), crafting, quest log, map, party/guild, chat, shop/trade, settings, death/respawn, loading/teleport, tutorial prompts, damage numbers, nameplates.

### 6.5 Visual style and floating UI
Dark-navy panels, gold trim, serif headings; palette, fonts, frame recipes and HUD layout in [art/ui-style.md](art/ui-style.md). UI floats in the world where it can: object interactions show a card beside the object (`ProximityPrompt` with the Custom style drawn by `PromptController`), nameplates, damage numbers and XP/loot gains are BillboardGuis; menus (inventory, spellbook, character sheet, trainer) open as panels standing in the world in front of a first-person camera, sized to a share of the view so text stays readable (`UiRigs`); the HUD stays on screen.

---

## 7. Content curation and pipeline

### 7.1 Principles
- **Curated, not generated in bulk.** Every asset and data row has a purpose in the progression plan; quantity is a budget.
- **Data-driven**: content lives in `Content/` tables or JSON/TOML compiled to modules by a tool. Balance edits don't require touching code.
- **Single content register** (`content/register.json`): id, type, owner, origin, license, status (`draft → reviewed → approved → shipped`), notes. Tools fail the build if an `approved` check is missing for referenced content.

### 7.2 Content intake checklist
1. Written spec: role in game, level band, readable fantasy, budget (triangles/texture size/audio length).
2. Originality check (§2) signed off.
3. Asset license verified (original / licensed / Creator Store with terms noted).
4. Technical check: naming, scale, pivot, collision, LOD, texture limits, memory.
5. Safety check: Roblox content policies, violence/gore level, text filtering.
6. Playtest note.
7. Approved in register; only then wired to data.

### 7.3 Asset conventions
`Category_Name_Variant` (e.g. `Icon_Spell_Fire`), Pascal case in-engine, lower-snake on disk. Folders mirror Explorer. Textures power-of-two where possible, minimal resolution that reads on a phone. Audio normalized, loops tested. No asset ids hard-coded in scripts; they live in content data/`Assets` manifest. Animation clips follow [docs/art/animation-pipeline.md](art/animation-pipeline.md): one manifest per set in `content/animations/`, roles in `Content/AnimRoles`, and `tools/anim/anim.py` exports, uploads and writes the ids; every clip is tiered `placeholder` or `final`.

### 7.4 Scope control (curation numbers)
| Milestone | Classes | Spell Tiers | Disciplines | Enemies | Zones | Level cap |
|---|---|---|---|---|---|---|
| M0.5 testing grounds | 3 (Fighter, Mage, Healer) | 0–1 (16 spells) | 2 | 5 Rabble + 1 elite + Skeleton; Warband data-only | 1 dev place (village + fields + camp) | 5 |
| M1 vertical slice | 3 | 0–1 | ~12 | ~6 + 1 boss | tutorial + 1 field | 5 |
| M2 alpha | 8 | 0–3 (~60) | ~30 | ~20 | hub + 3 | 20 |
| M3 beta | ~16 | 0–5 (~120) | ~60 | ~45 | 1 realm | 40 |
| Launch | ~24 | 0–6 | ~90 | ~80 | hub + 2 realms | 60 |
| Post-launch | expand on a published roadmap, never ahead of QA capacity | | | | | to 100 |

### 7.5 Third-party asset sources
**Local CC0 library** (`D:\Projects\CC0 Assets`, 22 Kenney packs, each with a CC0 License.txt):
- Used files are **copied** into `assets/third_party/kenney/<pack>/` together with the pack's License.txt and renamed lower-snake (§7.3). Tools and data never reference the machine-local path.
- One register row per used file (origin: Kenney, license: CC0). Binaries go through Git LFS (§5.11).
- Meshes and images still pass Roblox upload moderation; ids go in the `Assets` manifest only.
- Fits: retro-fantasy-kit (village, walls, palisades), retro-textures-fantasy, prototype-textures (greybox), foliage-sprites, game-icons (+expansion), ui-pack + Kenney Future font, fantasy-ui-borders, input-prompts, crosshair/cursor packs, particle/smoke/light-mask packs, pattern-pack, development-essentials. Audio packs (impact, rpg, interface, ui) are usable once upload quota allows. sci-fi-sounds and digital-audio are off-tone and excluded.

**Local VFX texture library** (`D:\Projects\Games\VFX-Library`, not in git): particle, flipbook, noise and trail packs indexed in its `INDEX.md`. Only CC0 packs may be uploaded to Roblox; same copy, LFS and register rules as above. See [docs/art/vfx-library.md](art/vfx-library.md).

**Toolbox (Creator Store) audio**, used while upload quota is limited:
- Only Roblox-owned or licensed public audio; private user uploads will not play in our place.
- Ids go in the `Assets` manifest and the register (origin: Creator Store, license as listed). Smoke-test each id in Studio; replace failures.
- Toolbox *models* follow §5.10 (scripts stripped or audited).

---

## 8. External tools and asset workflow

### 8.1 Encouraged automation (agent-friendly)
- **Blender (headless/bpy)** for: 2D icon renders from simple 3D meshes, turntable thumbnails, texture bakes, UV/atlas packing, spritesheets, batch re-export, scripted material variants, mesh cleanup/decimation and format conversion. All driven by checked-in scripts in `tools/blender/`.
- **Procedural houses**: `tools/blender/house_generator.py` assembles medieval houses from the Quaternius Medieval Village MegaKit (CC0, `assets/third_party/Medieval Village MegaKit[Standard]/`, not committed): footprint 4-8 m wide by 4-14 m deep from the kit's roof sizes, 1-3 stories, brick or plaster ground floor, half-timbered upper floors, seeded doors, windows, shutters, chimney and vines. Same seed, same house. Runs headless (`--seed --count --width --depth --stories --out --glb --render`) or as a Blender sidebar panel (House tab). Built houses that ship get register rows (§7.1) for the kit files they use.
- **Python/Node/Lune** for: data pipelines (spreadsheet → `Content/` modules), asset manifests, validation (naming, sizes, missing refs), localization table builds, balance simulations.
- **Open Cloud** for uploading assets/places from CI with scoped keys.
- **Studio generators** (mesh/material/texture/procedural model tools) for props and blockouts, followed by a human art pass.

### 8.2 Out of scope for the agent
**No character modeling, no rigging, no skinning, no custom animation authoring by the agent.** Instead:
- Characters use Roblox standard rigs (R15), with accessories/clothing from approved sources.
- Monsters start as **Part-based or simple-mesh rigs** assembled with `Motor6D` in Studio, or licensed/commissioned rigs.
- Animations: Roblox Animation Editor by an animator, or licensed catalog animations that pass §7.2. The agent *wires* animations (priorities, markers, preload), it does not author them.
- Exception (owner request, 2026-10-24): the goblin enemy was an agent-made **placeholder** (`assets/blender/goblin/goblin.blend`). The owner's **Goblin Scout** (2026-10-28, `assets/original/characters/mobs/Goblin Scout`) replaces it as the goblin base for every goblin enemy; its clips are Action Forge (Quaternius, CC0) placeholders mapped in `content/animations/goblin.json` until the owner hands over final clips. Since the owner's Studio import (2026-10-28) the Goblin template is built from `tools/world/goblin_scout_import.rbxm` and the Scout clips are uploaded; the old mesh, palette, `goblin_rig.json` and clip ids are retired.
- Exception (owner approval, 2026-10-25): the agent may author **placeholder combat animations** on the stock Studio R15 rig with the owner's Blender animation toolkit. The rig is serialized from Studio, imported by the Roblox Animations add-on into `assets/blender/combat_r15/combat_r15.blend`, keyed upper-body only so locomotion keeps playing, baked to `.rbxanim`, and converted to KeyframeSequences by `tools/blender/rbxanim_to_keyframes.py`. Clips: `BasicStrike`, `BasicStrike2`, `BasicStrike3` (light chain), `BasicHeavyStrike`, `GuardHold` and `GuardParry`, shared by every class; replace with production animation when available.

### 8.3 Pipeline shape
```
assets/ (source) → tools/ (validate, bake, export) → upload (Open Cloud) → Assets manifest → Content data → place
```
Each step is scriptable and idempotent; manual steps are listed in the content register.

---

## 9. Things the brief did not mention (added)

### 9.1 Platform and legal
- **Experience guidelines / maturity labels**: combat violence stays stylized; set the correct maturity questionnaire answers; PvP flagged.
- **Chat and user text** filtered through Roblox APIs; moderation tools for guild names/titles.
- **Privacy**: collect no personal data; analytics are pseudonymous (`UserId` hashed if stored off-platform).
- **Third-party IP and licenses**: register in §7.1; periodic audit.

### 9.2 Live operation
- Feature flags/remote config (`ConfigService` pattern, MessagingService for hot toggles).
- Safe-shutdown and update flow: announce, save, drain, migrate.
- Telemetry: funnel (tutorial completion), economy faucets/sinks, death hotspots, perf, error rates. Dashboards before launch.
- Incident runbook: dupe exploit response, rollback, ban policy, communication.

### 9.3 Quality
- Test pyramid: unit tests for pure logic (damage, stats, loot), integration tests in Studio with multiple clients, soak tests (bots), device matrix, network simulator (latency/jitter/loss).
- **Playtest checklist per milestone**, regression list for each exploit class.
- CI: lint, typecheck, tests, `rojo build`, content validators.

### 9.4 Monetization (ethical defaults)
- Cosmetic-first, convenience second (storage, a few extra slots, respec tokens on reasonable pricing). **No** power sold directly, **no** paid random power boxes; if any random cosmetic boxes exist, they follow Roblox rules, with disclosed odds.
- Gamepasses/products verified server-side only; revenue never gates class or content access.

### 9.5 Social health
- Report/block flows; party and guild moderation; anti-harassment defaults; **trade scam protections**; new-account limits on trade and guild creation.

### 9.6 Onboarding and retention
- Tutorial under 10 minutes to first class choice; clear first-hour goals; session-length-friendly quests; daily/weekly systems that do not punish absence; return-player catch-up.

### 9.7 Production
- ADRs (decision log) for architecture choices, risk register, milestone exit criteria, cross-discipline ownership, definition of done per feature (design, code, test, content, UI, telemetry, docs).
- Bus factor: every system documented in `docs/systems/<name>.md`.

### 9.8 Accessibility and platforms
Controller parity, touch-first combat tuning, text scaling, remappable keys, reduced-motion mode, language packs.

### 9.9 Server cost and scale planning
Define target concurrency per place, server count per realm, and what happens when a realm is full (queue or overflow instance) before the first public test.

---

## 10. Milestones and exit criteria

| Milestone | Deliverable | Exit criteria |
|---|---|---|
| **M0 Foundations** (done 2026-10-23) | Rojo project, bootstrap, Net layer, Data stub, UI shell, CI | A player joins, a profile loads in memory, HUD shows replicated HP, tests and lint pass, Git initialized with hooks and the auto-commit gate working |
| **M0.5 Testing Grounds** (built 2026-10-24; open items in scope 01 §10) | One dev place in Midgard: Farming Village, fields, goblin camp; Fighter/Mage/Healer to level 5; dev commands ([scope 01](scope/01-midgard-testing-grounds.md)) | Every skill, passive and spell resolves server-side; Tier 2 refused at line level 7 (allowed at 8); Rabble AI states and leash work; dev commands gated; all assets registered |
| **M1 Vertical slice** | Levels 1–5, 3 classes, 12 Disciplines, ~20 spells, 6 enemies + boss, tutorial zone | 30-minute loop playable on phone and desktop; combat feel signed off; no exploit found in rate-limit/validation tests |
| **M2 Alpha** | Hub + 3 zones, 8 classes, crafting v1, parties, trading v1, cap 20 | Soak test with bots at target concurrency; telemetry live |
| **M3 Beta** | Guild Holds v1, tournaments v1, Ironbound realm, cap 40 | Economy balance sheet reviewed; moderation tooling in place |
| **Launch** | Cap 60, 2 realms, monetization v1 | Security review, policy review, content register 100% approved |

---

## 11. Decision log (where the best option differs from the literal ask)

| Topic | Request / source rule | Decision | Why |
|---|---|---|---|
| Death penalty | Faithful rule deletes characters ≤ level 5 | Default is XP debt; faithful rule only in opt-in Ironbound with a level-1 floor | Short sessions, younger audience; keeps the system, removes the churn trigger |
| Scale | 2,000 classes, 700 races, 100 levels | Data model supports it; shipped content is a curated slice (§7.4) | Curation and QA are the bottleneck, not schema |
| MMO feel | "One world" | Sharded servers + instanced content + multiple Places | Roblox server limits; the only scalable shape |
| Hit detection | Players may expect client-side feel | Predicted visuals, **server-resolved** hits, bounded lag compensation | Exploit resistance without losing responsiveness |
| UI | "Not all coded from scratch" | Studio-authored screens + templates + controllers; no code-built screens | Maintainability, localization, designer iteration |
| Tooling | Not specified | Rojo + Git + lint/types/tests; Studio MCP for UI and playtests | Review, CI, repeatability |
| Original naming | "Faithful" | Systems faithful, all names original (§2.1). Superseded 2026-10-28 by *Naming rule* below | IP safety, own identity |
| Data | "Doesn't need to save yet" | In-memory but contract-first and serializable-only | Zero-rewrite swap-in later |
| Characters | Agent shouldn't rig | Standard rigs + licensed/assembled monsters; agent wires, not authors, except the placeholder exceptions in §8.2 (goblin, R15 combat clips) | Quality and scope realism |
| Free models | Convenience | Audit before use | Backdoor risk |
| Commits | "Handle commits automatically" | Auto-commit local logical units behind a green gate; push, PR and release stay manual | Automation without risking secrets, broken `main`, or unreviewed publication |
| History and logs | No logs inside scripts | Change history lives in Git; runtime logging goes through one `Logger`; telemetry for diagnostics | Comments rot, Git does not; one switch controls log noise |
| Best practice vs request | "Always choose the best approach" | When a request conflicts, best practice is applied and the deviation is recorded in the commit body and this log | Keeps decisions auditable |
| Spell picks at M0.5 | 3 spells per caster level (§3.2) | 1 pick per level in M0.5 (`SPELL_PICKS_PER_LEVEL`). Superseded 2026-10-28 by *Spell picks* below | 3 picks would need ≥15 Tier 0–1 spells per class for a placeholder place |
| Circle pacing | Research estimate: levels 1–5 reach tier 2 | Circle 2 unlocks at casting-line level 6. Superseded 2026-10-28 by *Tier step* below | Owner wants Circle 2 later; keeps low levels readable |
| Public-domain names | Old §2 asked for Norse-neutral realm labels | Myth/folklore names allowed (Midgard first); source pairings and coinages still forbidden | Owner decision; myth predates the series |
| Unit tests | §5.1 named TestEZ or Jest-Lua | Lune unit tests for pure modules; Studio playtests for integration | Runs in CI and pre-commit without Studio |
| Toolchain manager | Not specified | Rokit pins every tool, including luau-lsp; Roblox type definitions pinned to the same luau-lsp tag | Reproducible gate on every machine |
| Damage formula | §3.5 wrote `... − mitigation` | Multiplicative mitigation `100 / (100 + defense)` with a 1-damage floor | Subtraction zeroes low-level hits; the level-gap curve already provides the wall |
| UI file format | §5.1 said `.rbxmx` saved from Studio | Hand-authored Rojo `.model.json` with layout objects and templates; no runtime-built UI | Agent cannot save from Studio; declarative JSON diffs cleanly and Studio can re-save over it |
| Greybox world | Kenney meshes listed for the village (§7.5); owner (2026-10-29): replace all decorative greybox with generated models, laid out by the generator around the NPCs and spawners, using the MegaKit house generator once its textures work in Roblox | The Map keeps gameplay objects only. The world generator dresses the pads (`Gen/Settlement`): MegaKit houses and barns on lots facing the roads, terraced field plots with crop rows, an orchard grid and a palisade camp. Kit-textured structures are built for what the kit lacks (well, braziers, scarecrows, palisade, tents). The well and braziers carry the `Purifiable` and `Kindleable` parts. The kit is made Roblox-ready in `tools/blender/village_kit.py`: OpenGL normals, 1024 px textures, the wear material merged, heavy pieces decimated (45k to 20k triangles for the largest house), one MeshPart per material, and colours for untextured materials. `SpawnService` seats enemies on the ground below spawners | Footprints and clearances are checked by tests; the kit is CC0 and already in the repo; per-material parts keep a house to about 8 parts; the axis mapping was measured, not assumed |
| Test automation hook | Dev commands are chat-only | Studio-only `ServerStorage.RunDevCommand` BindableFunction runs the same handlers | Studio MCP cannot send chat from plugin context; the hook is server-side and absent outside Studio |
| Combat feel | §12.8: prototype tab-hybrid and free-aim in M1 | Hybrid soft target + optional lock replaces pure free-aim (2026-10-24); per-delivery aim rules; no AoE target cap; ranged physical class deferred | Owner decision after targeting research (FFXIV, BDO, TERA, Lost Ark, GW2); one system that works on phone, pad and mouse |
| Melee input | §3 controls: tap light, hold heavy | Mouse 1 / R1 light, Mouse 2 (combat mode) / R2 heavy, F guard; bow heavy = aim and draw, light shoots; touch gets a Heavy button (2026-10-30) | Owner decision for slower, deliberate sword-and-shield combat; Mouse 2 rotates the exploration camera so heavy is combat-mode only; hold-to-heavy removed for every weapon |
| Sword clips | §7: agent-made placeholder combat clips | Owner-authored `Sword` set (three slashes, idle, idle without legs, shield block) is final; `sword_slash` windups follow the clips' `Hit` markers (0.68, 0.54, 0.47 s) and the finisher narrows to a 90 degree chop with more reach and damage (2026-10-30) | Owner supplied the clips and asked for slower, deliberate sword and shield combat; `sword_heavy` keeps the fist heavy clip |
| Player-facing text | §6.3: all strings through LocalizationTable | M0.5 keeps strings in `Content/Strings` and content names; LocalizationTable deferred to M1 | Single source table makes the later move mechanical |
| UI look | §6.1: shared Style Editor / StyleSheet | Dark-navy and gold style from the owner's reference (2026-10-24), colours written per element in the `.model.json` files plus `Shared/Theme` for runtime tints; frames built from strokes, gradients and rotated frames instead of uploaded 9-slice art; Accanthis replaces Cinzel (not on Roblox) | StyleSheet rules do not round-trip through hand-authored Rojo JSON yet; procedural frames need no upload or licence and stay sharp at any scale |
| Floating menus | Owner asked for VR-style floating UI, e.g. the inventory in front of the player, with readable text (2026-10-25) | Menus open as a world-space panel in front of a first-person camera (trainer: beside the NPC), placed at the distance where it fills a set share of the view so text stays readable on any screen; movement held while open; HUD stays on screen; loot and XP float over the character | Screens stay ScreenGui-authored and are moved into one SurfaceGui at runtime, so Studio previews and bindings keep working; movement is held by sinking inputs through ContextActionService because the patched PlayerModule is not reachable from PlayerScripts |
| Spellbook and loadout | Owner asked for a spellbook like an MMO blue-magic book with an active set (2026-10-25) | Numbered spell and technique pages with a detail pane; the 8-slot hotbar is the loadout (owner's choice over a separate active set), saved in the profile and server-validated; cells show names, not icons | One layout object to maintain instead of two; no icon art is uploaded yet |
| Skill timing | Real-time action cooldowns per skill; cast speed from Agility | FFXIV-style GCD (2.5 s) / oGCD with animation lock, queue, slidecast and move-cancel replaces per-skill-only timing (2026-10-24); basic attacks and enemies stay off the GCD; only the item affix `Haste` shortens GCD and casts | Owner decision; readable rotation with weaving, gear-driven speed instead of a stat |
| Goblin art | §8.2: no agent modelling, rigging or animation | Owner override for a test (2026-10-24): placeholder skinned goblin replaces the part rig; clips ship as KeyframeSequences registered at runtime until uploaded, and enemy animation plays client-side from a replicated `AnimCue` attribute | Studio's 3D importer is UI-only, so the mesh upload is a manual step; runtime KeyframeSequence registration only works in Studio, so live servers need uploaded ids in `Assets.Animations` |
| Spell power scale | Owner (2026-10-30): trim spells to the canon power scale, canon names until release, at least one spell per school plus Light, Mend and Create Water | M0.5 lists hold canon Tier 0–1 spells only. Mend is shown by its canon name Light Healing (id `mend` kept for profiles and VFX). The cut elemental and support spells moved to their canon-scale Tier (2–3) in `Content/Skills`, off the class lists, VFX kept. Summons left to the summon system | Matches the source scale; nothing above Tier 1 is reachable at level 5, so the move costs nothing and the M1 lists reuse the data |
| Combat animation | §8.2: no agent animation authoring | Owner approval (2026-10-25): agent-made placeholder `strike`/`heavy_strike` clips on the stock R15 rig, upper body only, Action priority; `SkillDef.animation` names the clip; the local client plays it on use, the light swing VFX waits for the `Hit` marker, and the heavy swing keeps coming from the server Resolve | Readable attacks before an animator joins; markers stay cosmetic. Clips are uploaded to the place owner's account through Open Cloud (`tools/anim/anim.py upload`, key from `ROBLOX_OPEN_CLOUD_KEY`), so they replicate and play on live servers |
| Light attack chain | §5 timing: basic attacks are single swings, no combos | Owner request (2026-10-28): the light attack becomes a three-hit chain `strike` → `strike_2` → `strike_3` linked by `SkillDef.chainNext`; a press within `Tuning.Combat.Chain.Window` (0.8 s) of the last hit continues it, otherwise it starts over; each hit waits out the previous hit's cooldown and the finisher (1.5× damage) has a 0.8 s cooldown as its recovery; the server rejects out-of-order hits (`Chain`); chain hits stay off the GCD and set no animation lock. "No combos" still holds for skills | A short melee string reads better than one repeated swing; rules live in `Shared/Chain` so client prediction and server validation cannot drift |
| Guard animation | Brief: GuardHold/GuardParry clips, played on the client | `GuardHold` loops while the server-set `Guarding` attribute is true and `GuardParry` plays when the new `ShowParry(defender, attacker)` remote names the local character, both from `Client/Animation/GuardClips`, not `VfxController`; a guarded (blocked) hit now reaches clients as `ShowDamage` kind `"blocked"` | The attribute is authoritative, so the hold never sticks after a rejected guard; keeping animation out of `VfxController` leaves effects to the VFX work |
| Headless combat clip authoring | Skill protocol: one persistent Blender GUI session over MCP for posing, bake and preview | Chain and guard clips (2026-10-28) were posed by `tools/blender/combat_poses.py`, baked by `tools/blender/combat_bake.py` and rendered by `tools/blender/combat_preview.py` in separate headless Blender 5.2 runs; review used front, side and three-quarter renders of every key pose; `combat_bake.py` follows the skill's `export_rbxanim()` steps directly because its authenticity gate rejects the add-on 3.x layout, and re-baking `Strike` reproduces the committed `.rbxanim` within 3e-5 | The open GUI Blender held another task's unsaved file; scripted poses make the clips reproducible from the repo |
| Combat animation toolchain | Brief named the bundled Roblox Animations add-on 2.6.3 and the Studio plugin's OBJ rig export | Add-on 3.1.2 (latest release; the toolkit and the animation skill were updated to pin it on 2026-10-25, replacing 3.0.1 used for the first bake, whose clips re-export identically), and the R15 rig reaches Blender as an `.rbxm` from `SerializationService`, imported with the add-on's rbxm importer (body meshes fetched with the add-on's saved Roblox login) | The 3.x add-on pairs with the current Studio plugin and 2.6.3 conflicts with it; the OBJ export needs a Studio UI click the agent cannot make |
| Roblox PlayerModule bug | Not specified | Studio 0.744 ships `VRBaseCamera` with a `VRbaseCamera` typo that breaks default player scripts; `EngineFixes` swaps in `vendor/PlayerModulePatch` at server start | Temporary; delete both once Roblox ships the fix |
| Midgard world | Owner (2026-10-28): stylized vertical world in the style of walled fantasy Roblox worlds, Kenshi for scale and variety; generated procedurally and authored in sections; zones separated by verticality instead of walls on every edge; procedural low-poly props that stay cheap; keep 10,240 studs before committing a size | Replaces the eroded voxel world (2026-10-24). A zone graph (`WorldGen/Midgard.luau`) of zones, hidden pockets and typed edges (ramp, stairs, pass, cave, drop, open) is turned into ownership by a weighted Voronoi diagram on warped coordinates, tier floors with terraces, ridges, a rim that climbs in grass-topped ledges, and corridors. Every height step becomes a column of stacked Part blocks with a grass cap; columns are kept off walkable corridors. Props are clones of a 34-variant low-poly mesh library generated by headless Blender and uploaded through Open Cloud (at most two parts per tree, no Model). Each zone has its own seed and rebuilds alone in Studio in seconds, reading and rewriting only its own terrain columns; a locked zone is baked by Lune. The centre section is built; the old generator is still in the repo until per-zone atmosphere moods replace its region bands | Short sight lines and tiers make a world feel larger than its studs and give hidden areas something to hide behind; per-zone seeds make a fast section loop possible; identical meshes instance in one batch, where trees built from Parts would cost about ten times the instances |
| Spell VFX look | Earlier rule: every shape a texture on a ParticleEmitter or Trail; owner set a reference video as the target level (2026-10-25) | Textured curved MeshParts and full-screen effects (high-tier skills only) are allowed; effects become Studio-editable templates played through the VFX Forge emit module the owner owns, with project-generated textures; hits add hitstop, body flash and camera shake | Owner decision; layered, authored effects reach the reference far faster than code recipes, and Forge's licence permits the module inside the game runtime |
| VFX ink layer | Earlier rule: every effect layers a near-black non-additive ink layer for contrast | Ink only on high-tier effects (skills with screen effects: Charge, War Cry, Blink, Overcharge, Smite, Lay On Hands, future ultimates); other effects use earth or element tones (2026-10-25) | Owner decision; keeps the darkest contrast as a marker of the strongest skills |
| Atmosphere and world performance | Owner asked for proper atmosphere (lighting, sky, per-biome mood, day/night) and a performance solution for the 10,240-stud world beyond inverse-sphere fog (2026-10-25) | Authored Lighting effects driven by a client controller that blends a mood per terrain region and a 24-minute shared day clock (6-minute moonlit night); streaming at the recommended 1,024 radius with opportunistic stream-out, haze ending detail near that radius; no SLIM imposters (they stalled play at about 5 fps); single-part props placed without a Model; client culling hides small props past 350 to 450 studs and thins trees to 40% past 600 (Studio: 5 to 56 fps in the start valley, 2026-10-25); generating props on demand only as the last resort | Each pass was measured, kept only if it helped, and shadows-off was rejected for no gain; a clock from server time needs no replication; culling moves hidden props outside the DataModel, so streaming still owns them |
| Skeleton enemy | Owner asked for a Skeleton (Lv 1–3, no weapon, attack Scratch, clips SkeletonWalk/Scratch/Idle/Defeat) and supplied the Studio import and uploaded clips (2026-10-27) | Template rebuilt by `tools/world/build.luau` from the raw import (`tools/world/skeleton_import.rbxm`) with a HumanoidRootPart, R15 Humanoid and Animator; clip keys follow `<AnimSet><Clip>`, so `SkeletonAttack` and `SkeletonDeath` play the Scratch and Defeat clips; KeyframeSequences in the repo are exports of the uploaded clips, with bones that never leave rest dropped; new `Undead` team; `EnemyDef.template` picks the template; sets without a Run clip keep walking | Spawn and the animation controller need the goblin's rig contract; a separate team keeps goblin packs and the goblin bark off skeletons; the register requires a KeyframeSequence file per clip |
| Naming rule | §2 rule 2 forbade every series proper noun; owner changed it (2026-10-28) | Generic canon names (classes, spells, monsters, systems, terms, places, factions, items) may be used; names of characters and direct references to unique characters stay forbidden, as do characters, events and plot; the out-of-repo forbidden-terms list keeps only character names and unique-character references | Owner decision; shared genre vocabulary reads naturally while the source's characters stay out |
| Circle → Tier | Spell power was called "Circle" to avoid the source term | Renamed to **Tier** everywhere: skill field `tier`, `Tuning.Magic.TierStep`/`MaxTier`, `Formulas.TierUnlockLevel`/`TierCeilings`, refusal reason `TierLocked`, UI text | Owner decision (2026-10-28), allowed by the new naming rule |
| Spell picks | Target 3 per caster level, M0.5 at 1 | 1 pick per caster level is the target (`SpellPicksPerLevel = 1`); resolves §12 Q8 | Owner methodology (2026-10-28) |
| Tier step | Circle *n* at line level `6 × (n − 1)`, 10 Circles | Tier *n* ≥ 2 at line level `7 × (n − 1) + 1` (T2 8, T3 15, T4 22, T5 29), `MaxTier = 5` for levels 1–30; Arcane, Divine, Spiritual and Alternative lines counted independently, never summed; incompatible-line penalty kept because the anti-hybrid rule (§3.2) still stands | Owner methodology (2026-10-28); one Tier per 7 line levels across the 1–30 scope |
| Group combat AI | Owner asked for a general, data-driven group AI for every enemy (2026-10-28), plan "IA de combate em grupo" | Attack tokens per player target shared across teams: 2 Melee + 1 Ranged per player (separate Support budget for ally skills); the budget is chosen per skill, not per enemy; FIFO queue per kind with a recovery hold, grant timeout and stale-waiter drop; waiting melee enemies hold outside reach in a new `Position` state; pull-on-damage now only alerts the same team | Budgeting attackers does more for group fights than tuning damage or HP; a per-skill budget keeps mixed kits (Captain: rally + strike) correct; FIFO with a hold stops the last attacker from re-grabbing the token |
| Engagement slots | Plan: rings per slot type with radius = skill reach | One bearing set per ring (6 melee, 8 ranged) shared by every team on that player; each enemy stands on its bearing at its own reach, so mixed reaches share one assignment; greedy cost (walk + switch + congestion) every 0.5 s, wall-blocked bearings skipped, 4-stud separation | Sharing bearings across teams stops goblins and undead from stacking on the same spot; one ring per slot type instead of one per reach keeps the assignment small and stable |
| Disruptor and flank | Plan example: Goblin Slinger as Disruptor; owner rule: only enemies with an interrupting skill (stun or knockback) | Disruptor requires a telegraphed Stun-kind skill (today Goblin Brute and Wolf Rider); the Slinger is Opportunist/Reserve; one interrupt try per player every 8 s across teams; roles are capped per team squad; the director widens the budget by 1 in cast/lock/GCD windows and narrows it by 1 below 25% HP | Knockback never interrupts a player (it only moves NPCs) and the Slinger has no stun, so the example broke the owner's rule; a per-player cooldown stops two teams from chain-interrupting one player |
| Enemy behavior field | Plan: migrate `behavior` into `combat`, keep it for Dummy/Boss | `EnemyDef.behavior` is now optional `"Boss" | "Dummy"`; Melee/Ranged/Trapper/Brute/Caster/Healer/Rider/Leader removed (they had no AI effect); roles, morale, leader and phase summons come from `combat`; the Chieftain's hardcoded phase-2 Raiders and Rally became `combat.summons` with `selfEffects`, keeping the `Phase` attribute and summon tracking; morale is per enemy (`false` for undead, bosses and leaders) with leader bonus, leader-death drop and Flee/Regroup | Owner decision: one general system configured in data; a field that changed nothing is noise |
| Enemy stagger and reach | Plan: generic stagger with poise | Poise is a share of max HP taken within 3 s (default 0.2); a stagger cancels the windup, returns the token and pauses decisions 0.6 s, then 3 s of stagger immunity; melee enemies now stand at their shortest attack reach (was the longest, which left the Brute out of stab range), and a Disruptor holds its interrupt skills for player casts | The immunity stops stun-lock; the reach fix and the held interrupt were found in the Studio playtest, where the Brute had spent its slam before the player cast and could not reach with its stab |
| Animation workflow | Owner asked for one workflow to upload and manage clips, covering required clips, future additions, placeholders and finals; the Goblin Scout replaces the goblin base (2026-10-28) | Manifest per set (`content/animations/<set>.json`) with role, source, tier, hashes, live id and id history; `Content/AnimRoles` holds the enemy role contract that `EnemyAnimationController` and the spec read; `tools/anim/anim.py` (`scan`/`status`/`export`/`upload`/`sync`) replaces `tools/upload/animations.py` and writes the generated block of `Assets.luau` and the register rows; the generic FBX exporter `tools/blender/export_clips.py` replaces `export_goblin.py`; Goblin, Skeleton and Combat migrated with their ids; raw clip FBX folders are git-ignored and tracked by SHA-256; only mapped clips are exported or uploaded, the rest sit in the manifest's `library` | Ids, provenance and tiers had three hand-kept copies; hashes make re-export and re-upload idempotent under a limited upload quota; each Auto-Rig Pro clip FBX carries the whole mesh (about 55 MB, 1.9 GB per character), so committing them would bloat LFS for files the KeyframeSequences already capture; Scout export waits for the Studio import because pose names must match the importer's bones |
| Goblin Scout template | Owner imported `Goblin_Scout.fbx` in Studio (2026-10-28); the Scout replaces the goblin base | The Goblin template keeps the import's ten skinned MeshParts, PBR SurfaceAppearances and bone tree (on an invisible `Rig` part) under a new Humanoid and `HumanoidRootPart`, `BaseScale` 1.05 so a level-1 raider stands about 4 studs; mesh and map ids live in `Assets.Meshes.GoblinScout*` because Lune cannot read them from the import; the import's `InitialPoses`, `AnimationController` and `AnimSaves` are dropped; Scout clips are exported by `export_clips.py`, checked against Studio's own FBX import of the same clips (under 0.0005 degrees) and uploaded | Rebuilding fresh parts keeps the template free of import data Lune cannot round-trip; the per-enemy `color` tint no longer shows on goblins because the Scout's textures carry the colour, so variants differ by scale only until variant textures exist |
| Character creator | Owner asked for a creator with hair, facial hair, gender, shirt + pants combos, name, starter class, race and caster starting spells, blocky R15, BG3 as UI reference only (2026-10-28) | Full-screen locked Creator screen over a torch-lit stage above the village (not a floating world panel); Human playable, other races listed locked; gender = classic face + small body scales; one hair colour for hair and beard; names from a placeholder list (server accepts only listed names); the level-1 class and spell pick are spent in the creator. Characters no longer auto-load: `AvatarService` spawns and respawns every character with `LoadCharacterWithHumanoidDescriptionAsync`, and an uncreated player waits as a parked default character under the stage. Profile schema 3 adds `created`, `name`, `appearance`; `heritage` becomes the id `human` | The creator is a staging scene the camera must frame, which a panel in front of a first-person camera cannot do; spawning from the description hides the Roblox avatar with no flash; the engine copies StarterGui only on spawn, so a player needs a character before any screen exists ([character creation](systems/character-creation.md)) |
| Open world | Owner (2026-10-29): switch from a basic RPG to an open RPG like Kenshi: patrols in formation, town populations, roaming travelers, merchant trade routes; monster areas stay but are less obvious | Experiment on branch `exp/open-world`. `Spawner` parts are gone: nests (data, not parts) hold lairs and send squads out only while no player is within `HiddenRadius`; the leash follows the group. Village safety and zone bands kept (owner choice). Groups far from players are data only (LOD) to fit §5.9 budgets. Caravans can be met and attacked; trading opens the closed vendor panel until a currency and a Studio-authored shop UI exist. Routes stay on the valley floor and generated corridors, checked by a terrain-walk test; the fields–east-terrace ramp ends in a pit, so no route uses it yet | Kenshi-style travel needs routes that are really walkable; data-only groups are the only way a Roblox server holds a living world; owner kept the safe hub and bands |
| Avatar items | §7.3: `Content/Assets` is the only place asset ids live | Marketplace avatar items (Roblox hair and faces; paid third-party UGC beards and medieval shirt/pants, approved by the owner 2026-10-28) are listed by catalog id in `Content/Appearance`, one register row per creator set; they apply without ownership | They are catalog selections, not uploaded project assets; a per-id manifest entry would double ~90 ids. Risk: UGC can be delisted or moderated; the systems doc keeps the audit list and own assets replace them later |
| Factions | Owner (2026-10-29): two main factions, the Holy Kingdom and the Dragon Empire, plus the neutral Adventurers with two cities (a harbor and the mainland capital); the rest are minor factions | Team id `Players` renamed `Adventurers` (players are members). Added `HolyKingdom` and `DragonEmpire` (Hostile to each other, Neutral to Adventurers and civilians), `Elves` (minor nation) and `Dragons` (`monster`: hostile to players, civilians, the Holy Kingdom, goblins and undead; Neutral to the Dragon Empire and Elves). Town, Merchants and Travelers stay as civilian roles | A dragon faction that does not fight players would never be met as a threat; making it neutral to the Dragon Empire gives the empire's name a reason without inventing lore. Empires neutral to Adventurers keeps the player a common adventurer, as asked |
| Midgard continent | Owner (2026-10-29): a world map like the owner's sketch, Kenshi-inspired: the world runs in parallel and treats the player as a common adventurer; replace the zone-graph centre too | `WorldGen/Continent.luau` (template from the sketch: regions with anchors, owners, ridges, lakes, named sites) and a pure generator `Gen/Continent.luau` (warped weighted Voronoi land and regions, ridge mountains, sites, MST + A* roads) on a unit grid; a seed varies coast, borders, minor sites and roads. Removed: the zone graph (`Midgard.luau`, `Gen/Graph, Field, Grid, Cliffs, Props, Bake, Anchors, Plots, Settlement`), the Studio builder `Sections`, `tools/worldgen/map` and `bake`, `WorldGraph.spec`, `Settlement.spec`, the Population route walk test and every Population entry (they lived in the centre section). Kept: the prop and village asset libraries, the Map gameplay objects (placeholder spawn), the open-world services | Template plus seed keeps the owner's layout while every seed stays testable; a unit grid keeps realm size a parameter while it is still provisional. Terrain builds per region are the next step |
| Dev spawns in safe zones | Owner (2026-10-30): `/spawn` mobs must attack in the Dev Yard, which stays safe from everything else | Per-entity `ignoreSafeZone` set by `/spawn`, not a Dev Yard zone flag | The zone stays safe from patrols; testing works in any safe zone |
| Kenshi patrols and attackable people | Owner (2026-10-30): cascading tasks, followers trailing a leader, every outside NPC attackable; monsters Hostile, all other outside NPCs Neutral | `Shared/Tasks` cascade runs only when a brain has no target, on top of GroupService, whose rigid Column/Line/Wedge marching is removed in favour of a loose clump. `tasks` sits on the NPC definition but routes stay in `Population`: the Patrol task walks the goal GroupService gives it. The soft target skips unprovoked people; a lock reaches them | Routes need GroupService's level of detail and per-group data, not per-species data; soft-targeting every bystander would make players start fights by aiming near them |
| Goblin size and footing | Coordinator (2026-10-29): goblin base scale 1.5x and fix HipHeight so goblins stop sinking, scaling HipHeight with the scale; patrols walk slowly | `BaseScale` 1.575; HipHeight is unchanged because `Model:ScaleTo` already scales it, and the sinking came from the skinned mesh rendering 1.75 studs below the import's RootPart, so `tools/world/build.luau` raises the `Rig` by that much. `Tuning.Npc.PatrolSpeedMultiplier` (0.45) applies in Travel as well as Patrol, and `Tuning.Population.AbstractSpeed` drops from 0.7 to 0.4 so a data-only group never outpaces its bodies | Raising HipHeight would float the root and collision box above the visible feet; group patrols walk their routes in Travel, so a Patrol-only multiplier would miss them |
| Region builds | Owner (2026-10-29): the starter village is the Harbor; build the continent one region at a time and approve each; size 20,480 studs; clear the old centre in Studio | The Harbor village is the stud origin, so the Map (spawn, trainers, zones, dev yard) is unchanged; template pads hold its zones flat and dry and a bay keeps the sea beside it. The generator's per-cell math became a point query shared by the grid and the Studio writer, so regions built apart meet exactly. A region owns its land, lakes and near sea; approval is a fingerprint of its build stored in the template and checked by a test, since terrain lives only in the place file. Studio's old centre terrain and `Workspace.World` were cleared | Keeping the origin at the village avoids moving every Map object and dev coordinate; a fingerprint is the only way git can notice an approved region drifting |
| Weapons and shields | Owner (2026-10-30): sword, bow, staff, wand, fists and shields, each distinct like Dragon's Dogma; bow needs aim, positioning and timing; staff grants an attack spell and melees, wand the same without melee | `Content/Weapons` maps each weapon type to its light chain and heavy; bow: hold to draw (over-the-shoulder camera, slowed), release shoots an arrow with gravity and no homing, full draw for full damage, a release in the 0.2 s after full draw is a perfect shot (+50%), hits on the back +50%; staff: melee chain plus a charged arcane bolt on heavy; wand: quick bolt on light, charged blast on heavy; weapon magic costs no MP and sits off the GCD (owner choice). New `offhand` slot: shields block all frontal damage for stamina, parry longer, and attack while guarding bashes (stun). Two-handed weapons (bow, staff) and shields push each other off. Bow and wand cannot guard without a shield. Weapon magic deals `force` damage | Each weapon needs its own verbs to feel different; the free bolt keeps the wand usable without MP; a ranged weapon without a guard keeps dodging as its defense |
| Combat mode and lock-on | Owner (2026-10-30): the camera must not always be shift lock: a combat and non-combat mode toggle; add lock on target; the wand still does not read as a combo, so temporarily give every weapon the punch clips; give the dev player all basic weapons | Replaces the always-on shift lock: `CameraController` exploration mode (default, normal camera) and combat mode (shift lock), toggled by Left Alt / D-pad up / touch Combat button only (no auto-switch), HUD label `Bind_CombatMode`. The existing hard lock (Tab / R3 / tap) now drives the camera in both modes and sends skillshots and Ground at the target; it breaks after 1 s out of sight (`Tuning.Targeting.LockSightGrace`, `Targeting.KeepLock`) as well as on death and range. Every weapon basic plays the fist clips, one per chain step; the wand's closing bolt is drawn larger (`projectileScale`). `DevService` grants dev players one of each basic weapon and the wooden shield | Left Alt is free in the bindings and next to the movement keys; a manual toggle keeps the mode predictable. Lock framing in exploration lets a player lock without committing to the cursor lock |
| Shift-lock aim and wand chain | Owner (2026-10-30): each action must have a meaning; the wand and combat effects must not follow the mouse; default combat mode is shift lock, third person over the shoulder; the wand is a spell chain that slows the player with more range, and its spell has a cast time and cooldown | New `CameraController`: shift lock always on in play (released by menus), character faces the camera yaw. `CombatController.GetAim` casts from the screen centre on every input; melee swings along the facing. Wand light: `wand_bolt` → `_2` → `_3` chain (windup/recovery commit like swings, range 90); wand heavy: `wand_blast` cast (1.2 s cast, 6 s cooldown), off the GCD, no MP; `Content.spec` lets a Basic have a cast time off the GCD. The bow draw camera moved into `CameraController.SetAiming` | Aiming from the cursor let attacks fly sideways from where the character faced; a fixed crosshair ties direction to facing. Bolts that commit make the wand's reach cost mobility, and a cast blast gives it a deliberate big hit that movement can cancel |
| Fighter replaces Warrior | Owner (2026-10-30): the starter Warrior becomes the 15-level Fighter of [classes](systems/classes.md); keep Cleave, Charge and War Cry for the future Warrior high class, delete Hardy and Weapon Training | `fighter` leads `Classes.Order` (default creation class); the Warrior kit stays in `Content/Skills` granted by no class (checked by `Content.spec`); profile schema 4 maps saved `warrior` levels to `fighter` and adds `proficiency`, a weapon type from `Content/Weapons` (locked to the equipped item's `weapon`, else sword, when Weapon Proficiency I is granted; `/proficiency sword\|bow` changes it; the item field `weapon` is the single weapon-type field, no separate family field). Runtime is data-driven: passive `proficiency`/`rhythm`/`critEffects`/`upgrade` fields fold into `Formulas.CollectTraits`; statuses gained `magnitudeStat`, `nextHit`, `exposure`, `fillsRhythm`, `expireSkill`; cooldowns hold `charges`. Defaults the doc left open: Disengage 15 s cooldown and 12-stud leap; every damage bonus is additive into one term (`Formulas.HitBonus`); Battle Trance halves skill Stamina costs only (not dodge or guard); Exposed keeps the last applier as its source; Precise Attack is the equipped weapon's own attack (see *Precise Attack follows the weapon*) | Tier passives must override, not stack, or Weapon Proficiency would reach +60%; data fields keep future classes free of new code. Heightened Senses raises Agility, which also feeds crit and walk speed (derived stats); that is the design's own number, not a speed grant, and no `Haste` key was added. `Tuning.Progression.LevelCap` is still 5, so Fighter 6-15 is reachable only once the cap rises (a scope call) |
| Precise Attack follows the weapon | Owner (2026-10-30): Precise Attack uses the equipped weapon's own attack, an arrow with the bow, keeping 140% damage and +15% crit | Data field `weaponAttack = { scale }`; `Loadout.Attack` builds the use from the weapon's first light hit on server and client, with no Fighter-only branch. With the bow the hotbar slot draws on press and shoots on release, with the normal draw scaling. Its damage type is settled by *Precise Attack is always physical* | Reusing the light attack keeps reach, timing and visuals right for every weapon, including future ones. Hold and release keeps the bow's skill test instead of a free full-draw shot |
| Precise Attack is always physical | Owner (2026-10-30): Precise Attack is always physical damage scaled by PhysAtk, staff and wand included, keeping the weapon's delivery | `weaponAttack` gains `type` and `stat`, which `Loadout.Attack` applies over the light attack's damage; the staff and wand's own attacks stay `force` on MagAtk. Removes the staff and wand exception to Fighter's physical-only rule. Staff and wand still earn no Proficiency, since neither is in `Tuning.Combat.ProficiencyWeapons` | Data fields keep the rule out of the combat code and leave the weapon's base and ratio as the hit's numbers |
| Weapon access by class | Owner (2026-10-30): Fighters cannot equip wands; each class lists its allowed weapon types; any one class allowing a weapon is enough; mage and healer keep everything they could equip | `ClassDef.weapons`, checked by the pure `Loadout.CanEquip` in `InventoryService.equip`, refused with the `WeaponNotAllowed` toast. Only equipping is checked, so the dev kit still grants the wand. Defaults the brief left open: a character with no class can equip no weapon (reachable only through dev commands), and losing the allowing class unequips the weapon (`WeaponUnequipped`) | Checking only at equip would let a dev command leave a character holding a forbidden weapon; a data list keeps future classes free of new code |
| Hunger and thirst API | Brief: `NeedsService.restore(player, kind, amount)` and stats on the server | `NeedsService.Restore(player, "Hunger" \| "Thirst", amount)`; values are session state keyed by `Player`, not `Profile`, replicated as Player attributes | PascalCase matches `StatService.Restore`; `DataService.Update` each tick would fire `Changed` and recompute stats, and profiles are in-memory only until the persistent module lands |
| Summon skills | Owner: summon skills offer base summons plus any other summon of the family the player has discovered; Create Undead spawns a Zombie, and a Skeleton once discovered | `Summon` delivery, families in `Content/Summons`, `discoveries` on the profile (schema 5), rule in `Shared/Summons`. Discovery means kill credit on that enemy type. A summon's kill credits its owner, which also grants them XP and loot | One family table covers later summon skills; the credit rule keeps XP, loot and discovery on one path instead of three |
---

## 12. Open questions (need an owner decision)
1. Final title and clearance process.
2. Ironbound: separate universe/place, or a server flag?
3. Realm theming for the nine realms. Midgard is the starter realm (farmland, goblins); the other eight are open.
4. Who produces rigs and animations (in-house animator, commission, licensed packs)? Partly answered 2026-10-28: the owner authors final clips; Action Forge (Quaternius, CC0) clips are placeholders until then (`docs/art/animation-pipeline.md`).
5. Target concurrency per realm and server cost envelope.
6. Real Data module delivery date. (Schema version starts at 1.)
7. Guild siege schedule and protections for casual players.
8. ~~M1 spell picks~~ Resolved 2026-10-28: 1 pick per caster level is the target (§3.2, §11 *Spell picks*).
9. Climbing: cliffs and ledge routes need a climbing mechanic ([world generation](systems/world-generation.md)).
10. ~~Final Midgard size~~ Resolved 2026-10-29: 20,480 studs (§11 *Region builds*).
11. ~~Starter area placement~~ Resolved 2026-10-29: the Harbor is the starter village (§11 *Region builds*).
