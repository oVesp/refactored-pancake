# Combat and AI balance (proposal)

Status: accepted (2026-10-31), being implemented. It compares the current systems (docs/systems/combat.md, docs/systems/ai-and-spawning.md) with the research and the intent below, and lists what changes. Shipped items move into those two docs and are marked **Done** here. Pure rules live in `Shared/Threat`, `Shared/Poise` and `Shared/Swarm`; numbers in `Tuning.Threat`, `Tuning.Parry`, `Tuning.Swarm.Poise`, `Tuning.Swarm.Ranged`, `Tuning.Swarm.Overwhelm` and `Tuning.Combat.Poise`.

## Intent

- Content is party combat. A lone player can still take on several enemies with the right resources, but it is hard.
- **Melee** holds aggro. **Ranged** is precision and careful positioning. **Spells** have long casts and support the team.
- Melee DPS handles 1 to 3 enemies at once, with difficulty. Tanks handle many more, at the cost of damage.
- **Threat is a base mechanic.** Every entity generates and reads it. Skills that manipulate it belong to a planned class and plug into the base later.
- **Parry is the melee answer to same-level enemies.** Most mobs at the player's level are parriable, and a parry has a visible effect. Elites, brutes and bosses resist it.
- **Animation and VFX tell the player what is coming.** Ground telegraphs are a fallback, not the design.
- Enemies must leave openings.

## Sources and what they say

| Topic | Source | Finding |
|---|---|---|
| Hit severity | Designing Game Feel survey (arXiv 2011.09201); Lin et al. (arXiv 2208.06155) | Hit stop communicates severity. Impact feedback is a set of separable features (hit stop, shake, flash, sound). |
| Hit detection | Coppens, Reactive Melee Combat | Hit pause and animation-driven reactions are design choices; some games skip the pause. |
| Stagger | Skyrim Action Combat mod, GameFAQs thread, G2A glossary (community) | A hidden poise meter gates reactions. Heavy attacks can ignore it. Some bosses drain a gauge instead of flinching. Hitstun length decides whether a follow-up is possible. |
| Stun-lock | Jason de Heras (Sekiro vs DMC5) | Reaction rules, mainly stun-lock prevention, set the tone of combat. |
| Readability | Jason de Heras (3rd-person melee hit feel); DS3 enemy attack anatomy (Game Developer) | Readable animation underpins hit feel. An attack is phases (startup, active, recovery); active frames are few (2 to 4). Oversized reach raises difficulty. |
| Input | itch.io combat demo; Game Design Skills | Buffer windows open partway into an animation; cancel thresholds end it early. Whether an input interrupts an action is a design choice. |
| Group AI | Attack-token write-ups (DOOM 2016 lineage); Sidhvi (Arkham-style) | A token budget controls when enemies attack, slots control where they stand. Enemies without a token still look threatening. Heavy attacks cost more. More tokens means a harder fight. |
| Single AI | Game Wisdom; retro boss behavior tree article | A pool of about five attacks, filtered by distance and recent use, with weighted random choice. Committed attacks. Flat selectors beat deep trees. |

Most single-enemy and stagger sources are practitioner or community material. They support the pattern but are not studies.

## Already matches the sources

- Attack tokens, two slot rings, roles, a director that opens windows while the player is locked or casting, and morale (`Tuning.Swarm`).
- Hard commitment on player melee: windup, recovery, lunge, one buffered press, chain window.
- Poise as damage in a window, with a cooldown after stagger. This is the damage-gated meter the sources describe.
- Hitstop and shake on the local player's melee hits.
- Threat exists: `CombatService.landDamage` adds damage to `target.threat[source]`, and brains pick targets by taunt, threat, then proximity.

## Gaps against the intent

1. **Done.** **Threat is damage only and has no rules around it.** No healing threat, no target-switch hysteresis, no decay, no tuning table, no hook for skills. A tank that deals less damage cannot hold aggro, and a healer is invisible to enemies.
2. **Done.** **Parry has no visible effect on the enemy.** `CombatService` applies a `stun` status for 0.6 s (`PARRY_STAGGER`). `AIService` does not read stun (it only knows its own `Stagger` state), and no hit-reaction cue plays, so the only feedback is the damage `parried` marker and the defender's clip. A parry should visibly knock the attacker back.
3. **Done.** **Parry ignores poise and level.** The same stun applies to every attacker. Intent: most same-level mobs break, elites and bosses do not.
4. **Telegraphs carry the readability.** The per-skill `telegraph` flag is the only readability tool for several enemy skills (the light player attacks already use `telegraph = false` with animation and VFX instead).
5. **Tank capacity equals DPS capacity.** The token budget is flat per player: 2 Melee, 1 Ranged, 1 Support.
6. **The Slinger never plants.** After a throw (0.4 s windup, 2.2 s cooldown) the `keepDistance` branch retreats it 10 studs whenever the player is within 18 studs, so a chasing melee player never gets an opening.
7. **Enemy ranged attacks have no recovery.** Enemy melee swings have windups; ranged enemies are never punishable.
8. **Players have no poise.** A heavy hit does not interrupt a long cast unless it stuns, which makes long-cast spells either unsafe or untouchable depending on the enemy.

## Proposed design

### 1. Threat as a base mechanic

**Done** (2026-10-31): [combat](combat.md), Threat. Still open: a class skill that *sets* threat to the current top plus a margin (the planned tank class).

### 2. Parry as the melee core

**Done** (2026-10-31): [combat](combat.md), Poise and parry; [AI](ai-and-spawning.md), Stagger. Still open:
- Art: a `Parried` reaction clip per enemy set (goblin, skeleton; the role is optional and falls back to `Hit`, which the Skeleton and Human sets also lack) and a dedicated break VFX template; today the break is a gold body flash, a particle burst and hitstop.
- Heavy attacks' distinct windup VFX colour (white-gold parriable, red unparriable).
- Stamina refund on a parry that does not break, and a riposte window on a leader's flinch.

### 3. Telegraphs are a fallback

- Readability comes from authored animation (anticipation pose before the active frames), weapon or body VFX during windup, and sound. A skill with `telegraph = false` shows no ground marker.
- Per-skill rule: a skill loses its telegraph when its clip has a readable anticipation and a windup VFX. Until then it keeps the telegraph.
- Area attacks (the Brute slam, Chieftain stomp) keep a ground marker for now because their reach cannot be read from a body pose. Revisit when those clips and VFX ship.
- Consistency: one colour for parriable windup VFX (white-gold), one for unparriable (red). The player learns the vocabulary once.
- `Swarm.Interrupts` and the Disruptor still use the telegraphed stun skills; only the display changes.

### 4. Roles

| Role | Job | Hold aggro | Capacity | Damage |
|---|---|---|---|---|
| Tank (melee) | Draw the pack, block, parry | Base threat plus later class modifiers | Many enemies (more melee tokens, strong block and parry) | Lowest |
| Melee DPS | Parry, riposte, burst on staggered enemies | Loses threat to a tank | 1 to 3 enemies with difficulty | High |
| Ranged | Precision, kiting, punishing planted shooters and casters | Low threat | Few | Medium, positional |
| Spell | Long casts, support, heal | Healing creates threat, so supports get targeted | Needs protection | Utility |

### 5. Group combat

- Budget scales with the party, as now. Add `Budget.TankBonus` (+1 to +2 Melee tokens) to a target flagged as a holder (guarding, wearing a shield, or with a taunt status), so the whole pack can attack the one built to take it. A DPS keeps the base 2.
- Enemies without a token keep threatening (circling, pacing, shouting), so a pull is readable and does not look like a queue.
- Packs are the unit of design: melee rabble, one or two ranged, at most one high-poise enemy. A lone DPS handles two or three; a tank handles the pack.
- Scale damage taken for outnumbering lightly (a small `Overwhelm` factor per enemy beyond the token budget), so the pack cannot be ignored by taking hits.

### 6. Single-enemy behavior

- Each enemy has an attack pool with distance and recent-use filters and weighted random choice. `skills` order already filters; add `weight`.
- Every attack has anticipation, active and recovery. The recovery is the opening.
- **Tempo.** Enemies alternate pressure and reposition phases (`combat.tempo = { pressure, pause }` seconds), so even a lone enemy gives a rhythm: attack, step back or circle, attack. Pause lengths vary per enemy.
- **Ranged enemies plant.** After a shot a Slinger stays put for a recovery (0.6 to 1.0 s), then repositions. It retreats only when a melee player is inside `keepDistance` and no shot is ready, and retreats are capped (one per 3 s, 6 studs) so a chasing player reaches it. A reach advantage that is also a weakness: punishable while planted.
- **Hit reactions in tiers.** Flinch (visual only, no cancel), stagger (cancels the windup, short), break (long, riposte), knockdown (elites, rare). Only stagger and above interrupt.
- **Poise per tier.** Rabble: one parry or two hits. Elites: several. Bosses: no flinch, a gauge with a long break window.

### 7. Players and poise

- Casters get an interrupt threshold: a hit under `CastPoise` damage only pushes the cast back slightly (pushback), a heavy hit interrupts. Melee and tank stances grant hyper-armor while guarding.
- Players have a short invulnerability after being staggered, so a pack cannot chain-stun a player to death.
- Light, heavy and parry carry `poiseDamage`, so melee has a way to open enemies. Hit stop scales with poise damage dealt, so a break reads differently from a normal hit.

### 8. Tuning and tests

- A pure-Lune simulation of `Swarm` and the new threat module can answer the balance questions directly: how many same-level Rabble can a DPS or a tank fight with given gear before dying, and how long is the opening after a Slinger shot. Treat "DPS survives 1 to 3, tank survives 5 to 8" as test targets.
- All new numbers live in `Tuning.Threat`, `Tuning.Swarm.Poise` and `Tuning.Parry`, not in code.
- Log through `Logger` only; add counters for parry breaks, aggro switches and times at full token budget, so tuning has data.

## Decisions (2026-10-31)

1. Poise is a separate pool (`poiseMax`) that refills after a delay without hits; the 3 s stagger cooldown stays as the stun-lock guard.
2. Healing threat is split across every enemy in combat with the healed ally.
3. Tank bonus is a fixed `Budget.TankBonus` (+1 Melee token) for a target that guards or taunts.
4. Basic enemy melee and projectile skills whose windup already plays an Attack or Throw clip lose the ground marker first; area attacks keep it.
5. The riposte bonus applies to the first melee hit only.

## Blast radius if accepted

- `CombatService`: threat gains a modifier path and healing threat; `PARRY_STAGGER` goes, replaced by poise damage and a break/flinch reaction; parry tests need updating.
- `AIService`: target selection uses switch ratio, proximity and decay; new `Parried` and flinch states with `AnimCue`; ranged plant and tempo logic; `keepDistance` branch rewritten.
- `Tuning.Swarm.Stagger`: reshaped or kept as the stun-lock guard only. New `Tuning.Threat` and `Tuning.Parry`.
- `Content/Enemies`: `poise` becomes `poiseMax` and `parry` class; `tempo` and `weight` fields (Types.luau).
- `Content/Skills`: `poiseDamage`, `threat`, `parry`; `telegraph` removed from skills as their clips and VFX are ready; War Cry keeps the taunt and gains a threat field.
- `SquadService`, `Tuning.Swarm.Budget`: holder bonus.
- Client: `Parried` and flinch clips and VFX in `EnemyAnimationController` and `VfxController`; new clips and effects for the animation and VFX pipelines.
- Docs: combat.md (Damage, parry, Cast) and ai-and-spawning.md (Stagger, Group combat, Brains) updated when items are accepted.
