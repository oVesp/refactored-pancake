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
| Level cap 100 = race levels + class levels; class caps 15 / 10 / 5 | All class names except generic fantasy terms |
| 3 spells per caster level; spell power in 10 tiers + a capstone tier | Spell/skill names (original or plainly descriptive) |
| Items graded by *data capacity* filled with crystals | Every named item, set, artifact |
| Guild strongholds with an NPC level budget | Every named location, faction, character, event |
| A native warrior-skill layer powered by *focus* | Every named technique |
| Nine realms as top-level world structure | The source's realm-to-theme pairings (public-domain realm names are fine, §2) |
| Penalty-bearing death, PK flags, tournaments | Any story beats |

---

## 2. Originality and content-safety policy

Hard rules. They apply to code, data, UI text, textures, audio and marketing.

1. **No characters, no events, no plot.** No one in the game may be a recognizable character from the source series, a lookalike, or a renamed copy (same role + same gimmick counts as copying).
2. **No series proper nouns.** Not for places, factions, classes, spells, techniques, items, races, titles, or in-jokes. Generic words (warrior, mage, fireball, healing) are fine; distinctive coinages are not. **Public-domain names are fine even when the source also uses them**: myth, folklore and history (Midgard, Yggdrasil, goblin, valkyrie, rune). The test is whether the name predates the series and appears in public-domain sources. A source-specific spelling, compound or twist on such a name is still a coinage.
3. **Mechanics are fair game, expressions are not.** A *rule* (3 spells per level) is borrowable; a *stat block, class list, skill list or level table* copied verbatim is not.
4. **Title and key art are original.** "Worldtree" is a placeholder; run a clearance check before any public page uses it.
5. **Norse myth is public domain.** Realm, creature and god names from the myths may be used directly. What stays forbidden is the source's *expression*: its realm-to-theme assignments, its race-to-realm placements, and any character or item built on a myth name the way the source built it.
6. **Every content entry carries provenance** (§7.1): author, origin (original / generic / licensed asset), license, review state. Unreviewed content cannot ship.
7. **Review gate:** a reviewer checks each new content batch against a *forbidden-terms list* kept outside the repo's public data (it itself contains series names). Reviewer signs off in the content register.

### 2.1 Terminology map (use the right column in all player-facing and internal names)

| Mechanic | Source-game term (do not use) | Project term |
|---|---|---|
| Spell power ranks 1–10 + capstone | "Tier", "Super-Tier" | **Circle** 1–10, **Apex** rites |
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
- **Heritage**: Human at launch. Humans have **no heritage levels**; all levels go into classes. Future heritages with heritage levels (stat-heavy, ability-heavy, drawbacks) slot in without schema changes.
- **Classes**: base cap 15, high cap 10, rare cap 5. Minimum 7 classes to reach 100. Prerequisites gate high/rare classes. Every strong class carries a penalty.
- **Class slots**: a character can hold many classes; UI must show *build path* (order + levels).
- **Stats** (9): HP, MP, Physical Attack, Physical Defense, Agility, Magic Attack, Magic Defense, Resistance, Special. Derived: crit, move speed. Stats never shorten the GCD or cast times; only the `Haste` item affix does (§3.5).
- **Death & progression safety**: see §3.9.

### 3.2 Magic (Circles)
- 10 Circles + Apex rites. **3 spells per caster class level**, chosen from that class's list.
- **Circle ceiling follows the deepest compatible casting line**, not total level. Mixed incompatible lines cap lower. This is the main anti-"hybrid cheese" rule.
- **Circle unlock** (tunable, `Content/Magic`): Circles 0–1 at casting-line level 1; Circle *n* ≥ 2 at line level `6 × (n − 1)` (2 → 6, 3 → 12, 6 → 30, 10 → 54). Levels 1–5 therefore cast Circles 0–1 only.
- **Spell picks per caster class level**: `SPELL_PICKS_PER_LEVEL`, a data constant. Target 3; M0.5 uses 1 (§11).
- Zero-Circle utility spells exist but cost like Circle 1 (soft sink, flavor).
- Spells deliver through **real-time delivery types**: projectile, cone, ground target, self, ally, summon. Magic damage is not blockable by physical armor; it is reduced by magic defense/resistance.
- Resurrection spells exist, scale with Circle, cost XP/levels/materials.
- Launch content: Circles 0–3 (alpha), 4–5 (beta). No Apex at launch.

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
- Item types: weapon, armor, accessory (limited ring slots), consumable, material, scroll, tool.
- **Scrolls** require mastery of the matching magic line to use (drives class value).
- **Singular relics**: hard-capped world count, unique, rule-bending; may be lost on death in PvP zones. Launch with **zero**; they arrive in a timed event design, never from random drop tables.
- Metal gear: high defense, low item HP, resists pure energy. Durability exists and is slow.
- **Haste** is an item-only affix: it shortens the GCD and cast times (capped at `Tuning.Combat.Gcd.MaxHaste`). No stat, passive or status grants it.

### 3.5 Combat (action)
- **Client** sends intent (skill id, aim vector, sequence, optional target). **Server** validates and resolves. See §6.4.
- Controls: tap/click light attack chain, hold for heavy, skill hotbar (6 slots mobile, 8–10 desktop), dodge, block/parry window.
- **Targeting (hybrid)**: an automatic soft target (enemy nearest the screen centre, sticky in crowds) plus an optional lock (Tab / R3 / Target button cycle; tap an enemy on touch). Each delivery uses it differently, so archetypes play differently: melee swings where you face with short-range magnetism; skillshots (`Projectile`) are free-aim with a small touch/pad assist; mage `Target` spells seek the target and cannot miss but have a cast time and stop on walls; `Ground` lands on the cursor, or on the target off the mouse; support (`Ally`) takes the ally under the mouse or the wounded ally nearest the centre, else the caster. AoE has no target cap. Details: `docs/systems/combat.md`.
- **Timing (FFXIV-style)**: spells and weaponskills share a **global cooldown** (GCD, 2.5 s); other class actives are **off-GCD** (oGCD) with their own cooldowns and are woven between GCDs. Every non-basic action has a 0.6 s **animation lock**, giving two weaves per GCD. Cast-time spells are cancelled by moving, except in the last 0.5 s (**slidecast**); a cancelled cast costs nothing and gives the GCD back. A press within 0.5 s of an action becoming ready is queued. Basic attacks (light/heavy) stay outside the GCD with short cooldowns of their own; enemies keep per-skill cooldowns. No action combos yet. Details: `docs/systems/combat.md`.
- **Damage model**: `(base + stat × ratio) × (1 + bonus) × type multiplier × crit × level gap × 100 / (100 + defense)` (`Shared/Formulas.ResolveDamage`), with damage types (physical, fire, cold, lightning, acid, holy, negative energy, poison, mental) and resist/immune/vulnerable tags.
- **Level gap curve**: strong smoothing instead of a hard wall: ≥10 levels above → large reductions, ≥30 → near-zero without penetration items/skills. The wall is faithful; the smoothness avoids hard-lock frustration.
- **Status effects**: stun, slow, root, silence, fear, charm, burn, poison, bleed. Boss immunity pattern is explicit in data (e.g. "immune: mental").
- **Targeting rule**: party and guild members never take friendly fire.

### 3.6 Progression
- Per-class level curves; slow early levels, long mid-game.
- **Every class level grants one class skill**, either **Active** (hotbar) or **Passive** (always on, applied from data by `StatService`/`SkillService`), plus the class's base stat growth. Caster levels also grant spell picks (§3.2).
- XP sources: monster kills, quests, discovery, crafting, tournaments.
- **Classes unlock via conditions**: kill counts, quest chains, item turn-ins, other class thresholds. Rare classes are one-per-tournament or event-gated.
- Spell/Discipline learning is **not pure grind**: trainers, scrolls, rare drops.

### 3.7 World structure
- **Nine realms** as long-term structure; launch with **one hub + one starter realm**. Starter realm: **Midgard**. First zone set: Farming Village, its fields and a goblin camp ([scope 01](scope/01-midgard-testing-grounds.md)). Each realm is its own *Place* in one universe eventually; early builds run as zones in one place behind a `ZoneService` abstraction so splitting later is mechanical.
- **Density**: realms are sharded servers (target 40–60 players per server) with instancing for dungeons, strongholds, tournaments.
- Danger **banding by zone** (enemy level ranges, PK rules, loot) so power is legible: safe hub → starter fields → ruins → deep zones.

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
| **Resurrection** | Spell/item based, scaled by Circle, costs materials; a corpse run is available in Standard. |

### 3.10 Economy
Faucets: monsters, quests, vendors (small), tournaments. Sinks: crafting, repairs, Imprints, Hold upkeep, respec items, trainer fees. **No pay-to-win**: money buys time or cosmetics (§9.4). Every currency has a documented source/sink line in the balance sheet.

---

## 4. Early game slice (levels 1–5, Human)

From [low-level-human-design.md](low-level-human-design.md), adapted to this document's terms.

- 5 levels in classes only. Build templates: specialist (5), duo (3+2), dabbler (2+1+1+1).
- First classes (M0.5): **Warrior, Mage, Healer**. Planned starter set (original names TBD): front-line fighter, evasion fighter, bare-hand adept, scout, healer, spellcaster, apothecary, laborer. Dabbler needs a 4th class.
- Spells: Circles 0–1 for casters (Circle 2 at casting-line level 6, §3.2); picks per `SPELL_PICKS_PER_LEVEL`.
- Enemies: Goblin **Rabble** (Lv 1–6, raiding bands, no casters). Goblin **Warband** (Lv 7+, organized company with casters, healers, riders and a leader) is the next band.
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
| Tests | **Lune** unit tests for pure modules (`tests/specs/*.spec.luau`), Studio playtests for integration, MicroProfiler | Lune runs in CI without Studio. Pure modules take no instance requires so they load in both runtimes. |
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
    Packages/                 Wally output
  ServerScriptService/
    Server/
      Bootstrap.server.luau   Single entry; requires and starts Services in order
      Services/               DataService, StatService, CombatService, SkillService, AIService, SpawnService, ...
  ServerStorage/
    Templates/                Enemy models, hold interiors
    ContentServerOnly/        Drop tables, dev allowlist, formulas players must not see
  Workspace/Map.rbxmx         Generated greybox world (tools/world/build.luau)
  StarterPlayer/StarterPlayerScripts/
    Client/
      Bootstrap.client.luau
      Controllers/            InputController, CombatController, UIController, CameraController, ...
  StarterGui/                 Authored ScreenGuis (.model.json)
assets/                       Source art (Blender, PSD, SVG), not synced into the place
tools/                        gate.sh (quality gate), scan.sh, world/build.luau (greybox + templates), Python/Node/Lune/Blender scripts
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
- Server-only AI: state machine (idle, patrol, aggro, attack, return, flee).
- `PathfindingService` with **staggered** recompute (per-NPC jitter), cached agent params, `pcall` around compute, explicit timeouts, blocked-path handling.
- Detection by spatial queries, not per-frame player scans.
- Spawning via `SpawnService` with CollectionService tags (`Spawner`), leash radius, respawn timers, global and per-zone active caps.
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
HUD (HP/MP/Focus/XP/hotbar/buffs/minimap), character sheet (classes path), skill/spell book, discipline list, inventory + equipment, item inspector (Capacity bar, Imprint slots), crafting, quest log, map, party/guild, chat, shop/trade, settings, death/respawn, loading/teleport, tutorial prompts, damage numbers, nameplates.

### 6.5 Visual style and floating UI
Dark-navy panels, gold trim, serif headings; palette, fonts, frame recipes and HUD layout in [art/ui-style.md](art/ui-style.md). UI floats in the world where it can: object interactions show a card beside the object (`ProximityPrompt` with the Custom style drawn by `PromptController`), nameplates and damage numbers are BillboardGuis; personal menus stay centred screen windows.

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
`Category_Name_Variant` (e.g. `Icon_Spell_Fire`), Pascal case in-engine, lower-snake on disk. Folders mirror Explorer. Textures power-of-two where possible, minimal resolution that reads on a phone. Audio normalized, loops tested. No asset ids hard-coded in scripts; they live in content data/`Assets` manifest.

### 7.4 Scope control (curation numbers)
| Milestone | Classes | Spell Circles | Disciplines | Enemies | Zones | Level cap |
|---|---|---|---|---|---|---|
| M0.5 testing grounds | 3 (Warrior, Mage, Healer) | 0–1 (16 spells) | 2 | 5 Rabble + 1 elite; Warband data-only | 1 dev place (village + fields + camp) | 5 |
| M1 vertical slice | 3 | 0–1 (count per §12 Q9) | ~12 | ~6 + 1 boss | tutorial + 1 field | 5 |
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
- **Python/Node/Lune** for: data pipelines (spreadsheet → `Content/` modules), asset manifests, validation (naming, sizes, missing refs), localization table builds, balance simulations.
- **Open Cloud** for uploading assets/places from CI with scoped keys.
- **Studio generators** (mesh/material/texture/procedural model tools) for props and blockouts, followed by a human art pass.

### 8.2 Out of scope for the agent
**No character modeling, no rigging, no skinning, no custom animation authoring by the agent.** Instead:
- Characters use Roblox standard rigs (R15), with accessories/clothing from approved sources.
- Monsters start as **Part-based or simple-mesh rigs** assembled with `Motor6D` in Studio, or licensed/commissioned rigs.
- Animations: Roblox Animation Editor by an animator, or licensed catalog animations that pass §7.2. The agent *wires* animations (priorities, markers, preload), it does not author them.
- Exception (owner request, 2026-10-24): the goblin enemy is an agent-made **placeholder** (`assets/blender/goblin/goblin.blend`): low-poly mesh, rig with the reference armature's bone names, and clips retargeted from that armature's library. `tools/blender/export_goblin.py` writes the Roblox bone data and KeyframeSequences; replace with production art when available.

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
| **M0.5 Testing Grounds** (built 2026-10-24; open items in scope 01 §10) | One dev place in Midgard: Farming Village, fields, goblin camp; Warrior/Mage/Healer to level 5; dev commands ([scope 01](scope/01-midgard-testing-grounds.md)) | Every skill, passive and spell resolves server-side; Circle 2 refused at line level 5; Rabble AI states and leash work; dev commands gated; all assets registered |
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
| Original naming | "Faithful" | Systems faithful, all names original (§2.1) | IP safety, own identity |
| Data | "Doesn't need to save yet" | In-memory but contract-first and serializable-only | Zero-rewrite swap-in later |
| Characters | Agent shouldn't rig | Standard rigs + licensed/assembled monsters; agent wires, not authors | Quality and scope realism |
| Free models | Convenience | Audit before use | Backdoor risk |
| Commits | "Handle commits automatically" | Auto-commit local logical units behind a green gate; push, PR and release stay manual | Automation without risking secrets, broken `main`, or unreviewed publication |
| History and logs | No logs inside scripts | Change history lives in Git; runtime logging goes through one `Logger`; telemetry for diagnostics | Comments rot, Git does not; one switch controls log noise |
| Best practice vs request | "Always choose the best approach" | When a request conflicts, best practice is applied and the deviation is recorded in the commit body and this log | Keeps decisions auditable |
| Spell picks at M0.5 | 3 spells per caster level (§3.2) | 1 pick per level in M0.5 (`SPELL_PICKS_PER_LEVEL`) | 3 picks would need ≥15 Circle 0–1 spells per class for a placeholder place |
| Circle pacing | Research estimate: levels 1–5 reach tier 2 | Circle 2 unlocks at casting-line level 6 | Owner wants Circle 2 later; keeps low levels readable |
| Public-domain names | Old §2 asked for Norse-neutral realm labels | Myth/folklore names allowed (Midgard first); source pairings and coinages still forbidden | Owner decision; myth predates the series |
| Unit tests | §5.1 named TestEZ or Jest-Lua | Lune unit tests for pure modules; Studio playtests for integration | Runs in CI and pre-commit without Studio |
| Toolchain manager | Not specified | Rokit pins every tool, including luau-lsp; Roblox type definitions pinned to the same luau-lsp tag | Reproducible gate on every machine |
| Damage formula | §3.5 wrote `... − mitigation` | Multiplicative mitigation `100 / (100 + defense)` with a 1-damage floor | Subtraction zeroes low-level hits; the level-gap curve already provides the wall |
| UI file format | §5.1 said `.rbxmx` saved from Studio | Hand-authored Rojo `.model.json` with layout objects and templates; no runtime-built UI | Agent cannot save from Studio; declarative JSON diffs cleanly and Studio can re-save over it |
| Greybox world | Kenney meshes listed for the village (§7.5) | Generated Part greybox (`tools/world/build.luau`), Roblox materials only | Mesh uploads not available yet; generator is deterministic and re-runnable |
| Test automation hook | Dev commands are chat-only | Studio-only `ServerStorage.RunDevCommand` BindableFunction runs the same handlers | Studio MCP cannot send chat from plugin context; the hook is server-side and absent outside Studio |
| Combat feel | §12.8: prototype tab-hybrid and free-aim in M1 | Hybrid soft target + optional lock replaces pure free-aim (2026-10-24); per-delivery aim rules; no AoE target cap; ranged physical class deferred | Owner decision after targeting research (FFXIV, BDO, TERA, Lost Ark, GW2); one system that works on phone, pad and mouse |
| Player-facing text | §6.3: all strings through LocalizationTable | M0.5 keeps strings in `Content/Strings` and content names; LocalizationTable deferred to M1 | Single source table makes the later move mechanical |
| UI look | §6.1: shared Style Editor / StyleSheet | Dark-navy and gold style from the owner's reference (2026-10-24), colours written per element in the `.model.json` files plus `Shared/Theme` for runtime tints; frames built from strokes, gradients and rotated frames instead of uploaded 9-slice art; Accanthis replaces Cinzel (not on Roblox) | StyleSheet rules do not round-trip through hand-authored Rojo JSON yet; procedural frames need no upload or licence and stay sharp at any scale |
| Skill timing | Real-time action cooldowns per skill; cast speed from Agility | FFXIV-style GCD (2.5 s) / oGCD with animation lock, queue, slidecast and move-cancel replaces per-skill-only timing (2026-10-24); basic attacks and enemies stay off the GCD; only the item affix `Haste` shortens GCD and casts | Owner decision; readable rotation with weaving, gear-driven speed instead of a stat |
| Goblin art | §8.2: no agent modelling, rigging or animation | Owner override for a test (2026-10-24): placeholder skinned goblin replaces the part rig; clips ship as KeyframeSequences registered at runtime until uploaded, and enemy animation plays client-side from a replicated `AnimCue` attribute | Studio's 3D importer is UI-only, so the mesh upload is a manual step; runtime KeyframeSequence registration only works in Studio, so live servers need uploaded ids in `Assets.Animations` |
| Roblox PlayerModule bug | Not specified | Studio 0.744 ships `VRBaseCamera` with a `VRbaseCamera` typo that breaks default player scripts; `EngineFixes` swaps in `vendor/PlayerModulePatch` at server start | Temporary; delete both once Roblox ships the fix |

---

## 12. Open questions (need an owner decision)
1. Final title and clearance process.
2. Ironbound: separate universe/place, or a server flag?
3. Realm theming for the nine realms. Midgard is the starter realm (farmland, goblins); the other eight are open.
4. Who produces rigs and animations (in-house animator, commission, licensed packs)?
5. Target concurrency per realm and server cost envelope.
6. Real Data module delivery date. (Schema version starts at 1.)
7. Guild siege schedule and protections for casual players.
8. M1 spell picks: with Circles 0–1 only at level 5, 3 picks per level needs ≥15 spells per caster class. Grow the lists, or keep picks below 3 until Circle 2?
