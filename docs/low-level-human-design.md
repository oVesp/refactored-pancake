# Human Levels 1–5 — Yggdrasil Mechanics + New World Martial Arts

Scope: what a level 1–5 **Human** can be and have. Yggdrasil rules are the base layer; New World additions (martial arts, talents) sit on top. Spoiler cutoff stays at Vol 8; Fandom pages used contain later-volume material, which was left out (§8).

Tags: **[C]** stated in a fetched wiki/source this session; **[K]** recalled; **[~]** design proposal, not canon; **[?]** verify. Data twin: [low-level-human-data.json](low-level-human-data.json).

Canon is thin at low levels: the novels barely show anyone below level 10. Numbers marked [~] are placeholders to tune in playtests, anchored to canon where possible.

---

## 1. Humans in Yggdrasil — hard rules

| Rule | Value |
|---|---|
| Racial levels | **None.** Humanoids (Human, Dwarf, Elf, Half-Elf…) cannot take racial levels; every level goes into job classes [C] |
| Source of power | Entirely job classes and their skills; more classes + more diverse skills = stronger [C] |
| Racial skills | Humans have no Monster Abilities (those come from racial levels) [C] |
| Class cap | Base class 15, high class 10, rare class 5 [C] |
| Multiclass | Free, subject to each class's prerequisites; 1-level dips legal but inefficient [C] |
| Level 100 | needs ≥7 classes [C] |
| Class variety | Humanoids have the widest class access of the three race groups [C] |
| Class balance | Strong classes carry weaknesses/penalties [C] |
| Respec | Racial change item wipes humanoid class skills [C] |
| PvP | Killing humanoids/demi-humans carries penalties; killing heteromorphs does not [C] |
| Death (player) | −5 levels + drop 1 equipment; ≤ level 5 → deleted, player characters instead drop to level 1 [C] |

Consequence for levels 1–5: **a death at level ≤5 is a character reset** in strict Yggdrasil rules. Decide if the game keeps that (hardcore) or softens it (§7).

### 1.1 What a class level gives
- **Skills** from the class; either active (usable at will) or passive (always on). Most are MP-free with per-day or cooldown uses; Magic Strengthening skills cost extra MP [C].
- **Spells**: each level in a casting class lets you pick **3 new spells** from that class list [C]. 5 caster levels = 15 spells. A level-100 caster tops out around 300 spells [C].
- **Spell tier access** is a *separate* system from class-stacking. Mixing incompatible faith classes caps your tier (e.g. a level-100 mixed build reaching only tier 4 where a pure build reaches 6) [C]. Design rule: tier ceiling tracks levels in a *single compatible casting line*, not total character level [C/~].
- **"Genius" prefix** (e.g. (Genius) Fighter): reflects natural talent, slightly more spells known, but never makes someone incredibly strong [C].
- **Class stat contribution**: classes feed the 9 stats HP, MP, Physical Attack, Physical Defense, Agility, Magic Attack, Magic Defense, Resistance, Special [C]. No numeric per-level table in canon [?].

---

## 2. Class menu for a level 1–5 Human

Class names appearing in the Overlord class list [C]. Which are *base* (cap 15) vs high (cap 10) is mostly not stated, so the "likely base" column is [~].

### Warrior line
| Class | Seen on | Likely base? | Notes |
|---|---|---|---|
| Fighter | Brain Unglaus (a "Genius Fighter"), Climb, many NPCs | Yes | Generic weapon class |
| Archer | Bunaz, Neia Baraja | Yes | Ranged |
| Barbarian | A Slane Black Scripture member | Yes | |
| Monk | Sebas, Zenberu, others | Yes | Canon skills below |
| Mercenary | Gazef, Gagaran | Yes | |
| Fencer | Hekkeran Termite, others | Likely | |
| Knight | Gagaran | Likely | |
| Guardian | Climb, Baziwood | Likely | Defensive |
| Champion | Gazef | High/rare? | Not a starter |
| Paladin / Holy Knight | Remedios et al. | High? | Faith + martial hybrid |
| Sword Master / Sword Saint | Brain | High | Not a starter |
| Ki Master, Martial Lord, Striker | Sebas, Yuri | High | Unlock via Monk-type lines |
| Samurai, Ronin, Templar, Crusader | various | High | Max 10 or 15 |

### Thief line
Rogue (replaced "Thief" in the light novel), Ranger, Assassin, Forest Stalker, Bushwhacker. Ninja is gated behind level 60 [C].

### Magic line
Wizard, Sorcerer, Cleric, Priest/Priestess, Druid, Alchemist, Pharmacist, Bard, Illusionist, Necromancer, Elementalist (Air/Earth), Shaman, Medium. Cleric: noted as well versed in melee [C]. Rare/high lines (Eclipse, Forbidden Arts User, High Wizard, Bishop, High Cleric, Hierophant) are not starters [C].

### Production / support
Blacksmith, Armor Smith, Weapon Smith, Cook, Farmer, Sage, Merchant, Doctor, Craftsman. Runesmith is New World only [C]. Healing potions in Yggdrasil were made through skills from certain classes [C].

### Commander / social
Sergeant, Commander, Squire, Noble, Actor, Maid, Prince/Princess, Merchant, Charisma. Squire can convert to other classes under certain conditions [C].

### Non-class mechanics worth a slot
- Fishing: any player can fish, no dedicated fisher class [C]. Hairdresser did not exist [C].
- Temporary classes can be bought from the cash shop (e.g. "Minimum") [C].

---

## 3. Level 1–5 character skeleton

### 3.1 Build templates (5 levels total)
| Template | Layout | Pros / cons |
|---|---|---|
| Specialist | 5 in one class | Fastest class skills; no breadth |
| Duo | 3 + 2 | Hybrid (e.g. Fighter 3 / Cleric 2) |
| Dabbler | 2+1+1+1 | Max skill variety; stats thin (matches "more classes, stronger" theory long-term) |
| Cap note | 15 is the per-class cap | At 5 levels no cap pressure yet |

### 3.2 Class skill examples
Canon names exist for Monk; the others are [~] placeholders to write yourselves.

| Class | Canon-anchored skills [C] | Placeholder skills [~] |
|---|---|---|
| Monk | Iron Natural Weapon (harden claws/fists), Iron Skin (full-body steel), Resistance Massive (disperse Ki to cut magic damage) | Unarmed scaling |
| Fighter | — | Weapon mastery, shield use |
| Rogue | — | Trap sense, stealth, sneak strike |
| Ranger | — | Tracking, ranged bonus |
| Cleric | — | Healing efficiency, Holy bonus |
| Wizard | — | Spell damage, metamagic access later |

Rule: **Magic Strengthening skills** cost extra MP when stacked on a spell [C]; metamagic (Twin, Maximize…) shows up later and isn't a level 1–5 feature [?].

### 3.3 Stat model
Nine stats [C]. Canon gives no numbers for new characters. A reference point: one Pathfinder conversion ranks an elite caster's stats as HP 37 / PhysAtk 25 / Agility 30 / MagAtk 61 at level 63 — a ranking, not a formula [C]. Suggested low-level scale [~]:

| Level | HP | MP | PhysAtk | MagAtk | Agility |
|---|---|---|---|---|---|
| 1 | 8–12 | 0–6 | 4–8 | 0–8 | 4–8 |
| 5 | 25–45 | 0–30 | 10–20 | 0–20 | 8–18 |
Warrior-leaning classes spend toward HP/PhysAtk; casters toward MP/MagAtk.

---

## 4. Magic at levels 1–5

### 4.1 Rules
- 3 spells per class level, picked from that class's list [C].
- Casting uses MP; tiers 1–10 plus Super-Tier; levels 1–5 should sit in **tiers 0–2** [~].
- 0th tier "lifestyle" spells cost as much MP as a 1st-tier spell, so they are rarely used [C].
- Spell damage normally cannot be dodged/blocked by physical armor; purely energy attacks do well against armor and exoskeletons [C]. Resistances, penalties, equipment and stats modify spell effects [C].
- In Yggdrasil, incantations were not required; casters announced names as courtesy [C].
- New World: natives learn spells slowly (some spells take ~8 years; Magic Talent halves it) [C]. A normal human caster tops out around tier 3 [C].
- Actual spell-by-class assignment is unknown in canon; the list below is by **tier** [?].

### 4.2 Spells appropriate for levels 1–5 (tier 0–2) [C descriptions]
| Tier | Spell | Effect |
|---|---|---|
| 0 | Lifestyle Magic | Warm a bowl of food; costs as 1st tier |
| 0 | (unnamed) | Coarse paper; poor drinking water |
| 1 | Magic Arrow | Mana arrow, auto-hit, tiny damage; higher tier = more arrows |
| 1 | Light Healing | Divine heal |
| 1 | Create Water | Drinkable water, volume scales with caster skill |
| 1 | Destruction Water | Dispel water; harms water elementals |
| 1 | Anti-Evil Protection | Defense vs evil beings |
| 1 | Floating Board | Translucent cargo carrier |
| 1 | Compass | Directions |
| 1 | Clean | Cleans clothes and gear (Widen Magic → whole room) |
| 1 | Odorless | Hides scent |
| 1 | Rabbit Ears / Rabbit Foot | Hearing / luck buff |
| 1 | Bunny Tail | Lowers aggression toward caster |
| 1 | Lesser Mind Protection | Mental defense |
| 1 | Summon Monster 1st | Short-lived lesser elemental |
| 1 | Summon Undead 1st | Zombie animals |
| 1 | Camouflage, Quick March, Repair, Sleep | Web Novel only |
| 2 | Acid Arrow | Single-target acid bolt |
| 2 | Thunderlance | Lightning lance |
| 2 | Shock Wave | Invisible blast, crushes plate |
| 2 | Silence | No sound in an area |
| 2 | Invisibility | Invisible |
| 2 | Hawk Eye | Far sight |
| 2 | Lesser Strength / Lesser Dexterity | Stat buffs |
| 2 | Mass Compass | Group directions |
| 2 | Protection Energy – Negative | Resist negative energy |
| 2 | Temperature Change | Warm/cool water or room |
| 2 | Message | Long-range talk (Web Novel: 2nd tier) |
| 2 | Cure Disease | Cures non-cursed disease (Web Novel) |
| 2 | Summon Angel 2nd | Angel Guardian |

Reference ladder for growth: tier 3 gives Fireball, Lightning, Fly, Haste, Slow, Animate Dead; tier 5 gives Raise Dead (revive, −4 levels) and Teleportation [C]. Resurrection scales: Raise Dead tier 5; Resurrection tier 7; True Resurrection tier 9 [C].

### 4.3 Karma
Holy spells scale with karma: Shining Burst does more against low-karma targets [C]; Uriel only reaches full damage for max-positive karma casters [C]. Include a karma/alignment value for divine casters [~].

---

## 5. New World martial arts (human-only layer)

### 5.1 Concept
- Martial arts are native New World warrior skills that did not exist in Yggdrasil; players and Yggdrasil monsters cannot learn them. Ainz calls them "the magic of warriors" [C].
- Yggdrasil's analogous warrior skills are plain class skills; martial arts are separate, learned, and bought with *focus*.
- Several arts can run at once; arts can be chained into one combo [C].

### 5.2 Mechanics [C unless noted]
| Rule | Value |
|---|---|
| Resource | **Focus**: each art consumes focus scaled to its strength; extended use causes mental and physical fatigue |
| Capacity | A strong warrior (Gazef) runs 6 arts at once, 7 under extreme pressure; Gazef sits at about level 29, the practical human cap by talent+effort [C] |
| Cost reference | Sixfold Slash of Light costs as much focus as ~3 regular arts [C] |
| Learning time | A novice typically needs about a year, via real battle, healing between fights, fighting stronger foes under enhancement magic, sparring partners |
| Other ways to learn | Facing killing intent from a stronger opponent (Climb); copying another user's art (Brain); geniuses can learn arts above their level; a Talent (Increase in Focus Capacity) lets someone run arts above their level |
| Limits | Non-humans can learn them too (Hamsuke, Go Gin, a lizardman, others), but Yggdrasil players and Death Knights cannot |

Focus pool proposal [~]: `Focus = 2 + floor(level / 7)`; level 1–5 characters get **2**, level 29 gets 6 (Gazef), +1 emergency overdraw with fatigue. Basic art costs 1, Greater/Fortress-type 2, signature chains 3.

### 5.3 Arts, tiered by suitability
Tier grouping is [~]; names and effects are [C] from the wiki list. Arts clearly tied to later plot are excluded (§8).

**Tier A — basic, plausible at levels 1–5**
| Art | Effect |
|---|---|
| Ability Boost | Raises overall body strength |
| Body Strengthening | Raises body defense |
| Reinforce Defense | Raises defense |
| Reinforce Hide | Hardens skin |
| Evasion | Better dodging |
| Strengthen Perception | Sharper awareness of surroundings |
| Strong Strike | More power on strike attacks |
| Heavy Blow | Crushing capability; battering vs hard armor |
| Smash | Blunt attack |
| Slashing Strike | Powerful slash |
| Piercing Strike | Piercing attack |
| Front Cut | Direct cut with the weapon front |
| Vertical Strike / Oblique Strike | Directional strikes |
| Iron Fist | Hardens fist to strike |
| Dull Pain | Dulls own pain perception |
| Pace of the Wind | Increases speed |
| Air Slash | Slash that throws an air blade |
| Cutting Edge | Gathers air for an extra edge |
| Shield Bash | Shield impact and knockback |
| Strong Assault | More damage against heavily armored |

**Tier B — advanced, level ~10+**
| Art | Effect |
|---|---|
| Greater Ability Boost / Greater Evasion / Greater Reinforce Defense | Upgraded versions |
| Fortress | Absorbs/offsets attacks; works with shield, weapon, armor or bare hands; timing is exact |
| Flow Acceleration | Speeds nerve activity: faster attacks/movement; brain exhaustion |
| Focus Battle Aura | Normal weapons gain magic-weapon properties (can pierce angel defenses) |
| Magical Weapon Enchantment | Activates a magic weapon's enchantments |
| Instant Counter | Snap back to stance after being thrown off balance; strains body |
| Possibility Sense | Detects chance of victory |
| Sense Weakness | Detects target weaknesses |
| Double Air Slash | Two air blades |
| Piercing Dragon Tusk | Double piercing attack with elemental damage |
| Fatal Edge | Pours energy into the blade for a heavy slash |
| Fourfold Slash of Light | Four slashes in one swing, light-fast |

**Tier C — signature / elite (show aspiration, not starters)**
Field (perceive everything within ~3 m; a Brain original), Sixfold Slash of Light, Limit Breaker: Mind (removes brain-imposed limits, tears muscle).

### 5.4 Design hooks
- **Teacher required**: arts need sparring partners [C]. Gate learning on a mentor NPC.
- **One-year baseline**: scale by game time; geniuses halve it [~].
- **Talents**: 1 in 200 born with one; fixed at birth; useless if mismatched to your class [C]. Roll d200 at creation for a Talent; most are minor [C].
- **Equipment synergy**: Fortress and Magical Weapon Enchantment interact with gear; give weapons "art slots" [~].

### 5.5 Known Talents (for the d200 roll)
Combat-relevant: Increase in Focus Capacity (run arts above your level); Magic Item Affinity (use any magic item, top-10 talent); Spell Copy (copy one seen spell, top-10); Psychometry (use skills via touching someone's items, top-10); Intuition (sense malice); Enhanced Summoned Monster (+stats on summons). Minor/lifestyle: Magic Talent (halves spell-learning time), Float, Water Step (5 steps on water), Meteorologist (70% weather accuracy), Harvest speed-up, hot-water temperature sense. All-Seeing Eyes: sees arcane caster tier/power [C]. Most offensive-talent holders become adventurers [C].

---

## 6. Gear and economy at levels 1–5

### 6.1 Item grades
Grades are set by **data size** and filled via data crystals: Low, Middle, High, Top, then Legacy, Relic, Legendary, Divine; Artifact outside the ladder; World Items above all [C]. Levels 1–5 gear is **Low class** at best [C]. Trading magic items happened as data crystals [C]. Metal armor has high defense but low HP and resists pure energy damage [C].

### 6.2 Low-level gear list
| Slot | Items [C] |
|---|---|
| Weapons | Short Sword, Broadsword, Great Sword, Rapier, Scimitar, Falchion, Claymore, Katana, Kukri, Combat Knife, Long Spear, Morningstar, Mallet, Sling, Composite Bow, Crossbow, Hammer Axe |
| Body | Scale Mail, Banded Armor, Tower Shield, plain clothing |
| Magic gear | Ring of Protection, Ring of Deflection, Ring of Resistance, Boots of Silence, Belt of Constitution, Amulet of Health, Gauntlets of Strength/Endurance |
| Consumables | Minor Healing Potion (Low class), Blue Potion, Potion of Lesser Strength, Potion of Lesser Dexterity, Stamina Potion, Magic Weapon Oil, scrolls (use requires mastery of the matching magic system unless a Talent bypasses it) |
| Utility | Pitcher of Endless Water (Low class), Fishing Rod, Telescope, Bear Trap |

### 6.3 Crafting
Yggdrasil healing potions were skill-made by certain classes [C]; Alchemist/Pharmacist/Sage are the in-world analogues. Runecraft (dwarf) and Wild Magic are New World crafting systems, not human starting options.

---

## 7. Level-1–5 rule recommendations [~]

1. **Death**: keep Yggdrasil's −5 levels / drop 1 item for level 6+; at level ≤5, treat as reset-to-level-1 *with* a "mercy" option (corpse run) if the game is too punishing [C base rule].
2. **Class cap awareness**: show cap 15 per base class so players see the long game.
3. **Spell choice**: 3 per level, pick-from-list; free respec removed to preserve identity.
4. **Martial arts**: Focus 2 at start; unlock arts via training events; one art costs 1.
5. **Talent**: optional d200 table; ~0.5% hit; ensure it's roleplay-flavored.
6. **Natives reference**: commoners ~1–3, guards/Copper adventurers ~5–10, Gazef's talent+effort cap ~29 [C/~].
7. **Penalty balance**: give every strong class a drawback to mirror Yggdrasil's design [C].

---

## 8. Spoiler hygiene
The Fandom pages queried (Job Class, Martial Arts, Tier Spells, Race, Talent, Skill, Items) carry material past Vol 8. Excluded: later nations and characters, signature arts tied to later events (the "Nail Clipper" family, "Wind of the Great Forest", God Flash, Shukuchi line, Void Cutter, Showdown Declaration), high-tier spell showcases, and later-volume talent holders. Tier A/B art names are generic technique names and carry no plot content. Everything else is Yggdrasil system design or Vol 1–8 information; where uncertain it is tagged [?].

## 9. Sources (fetched this session)
- [Overlord Wiki — Job Class](https://overlordmaruyama.fandom.com/wiki/Job_Class)
- [Overlord Wiki — Martial Arts](https://overlordmaruyama.fandom.com/wiki/Martial_Arts)
- [Overlord Wiki — Tier Spells](https://overlordmaruyama.fandom.com/wiki/Tier_Spells)
- [Overlord Wiki — Race](https://overlordmaruyama.fandom.com/wiki/Race)
- [Overlord Wiki — Talent](https://overlordmaruyama.fandom.com/wiki/Talent)
- [Overlord Wiki — Skill](https://overlordmaruyama.fandom.com/wiki/Skill)
- [Overlord Wiki — Items](https://overlordmaruyama.fandom.com/wiki/Items)
- [Overlord-to-Pathfinder Conversion](https://myd20path.blogspot.com/2018/02/overlord-to-pathfinder-conversion.html)
- [Baidu Baike — Yggdrasil](https://baike.baidu.com/en/item/Yggdrasil/3375515)
