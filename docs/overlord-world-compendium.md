# Overlord World Compendium (Yggdrasil + New World) — Game-Design Reference

Scope: rules and world data for a game built on the fictional DMMO-RPG **Yggdrasil** and the **New World** it bleeds into. **Spoiler cutoff: light-novel Vol 8.** Nothing from Vol 9 onward is included: no later nations, later events, later titles or later lore. Nazarick-specific content is excluded except as an example of a generic system.

Machine-readable twin: [overlord-world-data.json](overlord-world-data.json).

Warning: wiki pages linked in §5 are not spoiler-filtered.

## 0. Confidence tags

The Fandom wiki blocked the fetcher, so data comes from Baidu Baike, Wikipedia, Yen Press, a Pathfinder conversion blog, search snippets and recall.

- **[C]** confirmed in a fetched/searched source
- **[K]** recalled from the novels, high confidence, not re-verified
- **[~]** fan-derived heuristic or design suggestion, not canon
- **[?]** unsure, verify before locking

---

## 1. Yggdrasil (the game)

### 1.1 Meta
- Full-dive DMMO-RPG, launched 2126 by a Japanese developer; 12-year run, then shutdown [C]. Developer name "Dwarven Furnace" [K].
- Norse setting, **9 worlds**: Asgard, Alfheim, Vanaheim, Nidavellir, Midgard, Jotunheim, Niflheim, Helheim, Muspelheim [C].
- 2,000+ classes, 700+ races [C]; extreme build freedom, many "trap" builds [K].
- World Champion: 9 titles total, one per world, won via developer-run tournaments, prize equipment [C].
- Cash shop sold convenience/power: permanent item allowing rings on all 10 fingers (rings fixed at purchase), appearance/internal-data/avatar/residence editing tools, XP-loss reducers [C].

### 1.2 Levels, races, classes
| Element | Rule |
|---|---|
| Max level | 100 total = race levels + class levels [C] |
| Race categories | Human (Human, Dwarf, Forest Elf…), Demi-Human (Goblin, Orc, Ogre…; uglier, stronger than Human), Heteromorph (monstrous; highest stats, various drawbacks) [C] |
| Race count | 700+ [C] |
| Class cap | 15 per base class; level 100 needs ≥7 classes [C] |
| Class tiers | Base 15, High 10, Rare 5 (e.g. World Champion, Eclipse) [C] |
| Multiclass | Allowed, free; many 1-level dips are legal but inefficient [C] |
| Race special skills | Unlocked at racial class levels (Demi-Human/Heteromorph) [C] |
| Rare-class gating | Rare classes demand high total level and specific prior classes [C] |

### 1.3 Combat
- Stats: HP, MP, Physical Attack, Physical Defense, Agility, Magic Attack, Magic Defense, Resistance, Special Ability [C].
- Buff/debuff icons visibly float over players [C].
- Undead immune to mental effects, positive and negative [C].
- Guild/party members cannot harm each other [C].
- Damage types, immunities, penetration, status effects: standard MMO-style [K].
- Death penalty: lose 5 levels and drop one equipment piece; at level ≤5 the character is deleted (player characters protected: drop to level 1). Resurrection spells reduce level loss; paid items shrink XP loss. Guild NPCs revive for a level-based guild fee, no penalty [C].

### 1.4 Magic
- **Tier magic**: tiers 1–10; 6,000+ spells total; typical level-100 player knows ~300 [C].
- **Super-Tier**: beyond tier 10, requires level 70+, max-level casters ~4 casts/day [C]. Epic-level equivalent in the Pathfinder conversion [C].
- Three branches: arcane, divine, spiritual [C].
- Metamagic works through a mana pool, not slots (Twin, Maximize, etc.) [C].
- New World benchmarks: ordinary people ≤ tier 2; tier 3 = elite; tier 5 = a nation's strongest; tier 6 = only Fluder Paradyne (Empire); tier 7 = angels summoned by Slane's Sunlight Scripture [C].

### 1.5 Items
- Grade (low→high): Low, Middle, High, Top, Rare, Legacy, Relic, Legendary, Artifact, World-Class. Other lists omit Rare/Artifact; order is approximate [C, sources disagree].
- Grade is set by **data size**: larger data capacity → higher tier. Data crystals fill capacity [C].
- Guild Weapons: separate category, not a rung on the ladder; top gear needs many high-rarity crystals and rare metals [C].
- **World Items**: 200 total; 20 ("the Twenty") can alter game settings or delete characters; owning one made a player famous [C].
- Rings: normally one per hand [C].

### 1.6 Guilds and strongholds
- Stronghold of castle rank or above grants guard NPCs and original-NPC creation [C].
- Castle rank: guild may allocate ≥700 levels to NPCs, max 100 per NPC; custom NPCs can carry custom gear [C].
- Stronghold NPCs cannot leave the stronghold [C].
- Guild weapon destroyed → guild collapses [K].

### 1.7 When the game becomes real [K]
- No logout, no GM/General Message; UI mostly gone; NPCs gain minds shaped by their written settings.
- Spells/skills used by intent; senses and emotions real.
- Yggdrasil gear is god-tier loot locally.

---

## 2. New World (through Vol 8)

### 2.1 Nations
| Nation | Notes |
|---|---|
| Re-Estize Kingdom | Monarchy, noble-vs-royalist split. E-Rantel frontier city; Katze Plains annual war with the Empire [K]. Gazef Stronoff: effort+talent cap ~level 29 [C]. |
| Baharuth Empire | Absolute monarchy under Emperor Jircniv Rune Farlord El-Nix [C]; Four Imperial Knights [K]; Fluder Paradyne, only tier-6 human [C]. |
| Slane Theocracy | Human-supremacist; Six Great Gods; Six Scriptures; Sunlight Scripture targets demi-humans [C]. |
| Lizardman tribes | Marshland tribal society (Vol 4) [C title]. |
| Adventurers' Guild | Neutral org; ranked metals [K]. |
| Eight Fingers | Kingdom underworld syndicate [K]. |

### 2.2 Native power ladder [~, anchored by C points]
| Level | Who |
|---|---|
| 1–5 | Commoners, apprentices |
| 5–15 | Guards, Copper→Gold adventurers |
| 15–25 | Platinum/Mithril, elite soldiers |
| ~29 | Human cap by talent+effort (Gazef) [C] |
| 30+ | Hero class [C, boundary estimated] |
| 35–60 | Legendary-tier beings |
| 80–100 | Players |

Adventurer ranks: Copper, Iron, Silver, Gold, Platinum, Mithril, Orichalcum, Adamantite [K]. Pathfinder heuristic: CR = total levels ÷ 4 (e.g. 63 → CR 15) [C].

### 2.3 Local magic
- Tier magic is the dominant system; natives mostly cap at tier 6 or below [C].
- Martial arts and innate talents exist [K].

---

## 3. Volumes 1–8 (world-event view)

Titles [C: Wikipedia, Yen Press]. Beats [K] unless noted.

| Vol | Title | World beats |
|---|---|---|
| 1 | The Undead King | Game ends, world turns real. Carne Village attacked by a Slane covert unit in Empire disguise; Gazef intro. |
| 2 | The Dark Warrior | Adventurer guild in E-Rantel; Eight Fingers crime network. |
| 3 | The Bloody Valkyrie | Adventurer parties and vampire threads [?]. |
| 4 | The Lizardman Heroes | Marshland tribe war. |
| 5 | The Men of the Kingdom Part I | Kingdom politics, underworld, princes' rivalry. |
| 6 | The Men of the Kingdom Part II | Kingdom politics continue; capital unrest [?]. |
| 7 | The Invaders of the Great Tomb | Adventurer/worker raid on a high-level dungeon. |
| 8 | The Two Leaders | Empire–new-power tension [?]. |

### 3.1 Reusable dynamics
1. Three-human-state triangle (Kingdom/Empire/Theocracy) around E-Rantel.
2. Slane's anti-demi-human ideology.
3. One or two level-100 entities outweigh nations; politics orbit them.
4. Information asymmetry: natives misunderstand tier magic and levels.

---

## 4. Game-organization mapping [~]

### 4.1 Campaign modes
A. **Late Yggdrasil**: raids, guild sieges, world-item hunts, shutdown finale.
B. **Transfer**: players wake in the New World with Yggdrasil kits.
C. **Native**: adventurers, soldiers, mages inside the political triangle.

### 4.2 Core rules to implement
- Level 100 = race + class levels; classes 15/10/5 tiers; ≥7 classes for 100 [C].
- Death: −5 levels + drop one equipment; ≤5 deletes [C].
- Spells 1–10 + Super-Tier (level 70+, ~4/day) [C].
- Items by data capacity; ten grades; 200 World Items, 20 "Twenty" [C].
- Guild castle: ≥700 NPC levels, ≤100 each, NPCs bound to base [C].
- Level-gap immunity (≥30 below) [~].

### 4.3 Encounter bands [~]
Local 1–10, Regional 10–20, National 20–35, Continental 35–60, Apocalyptic 60–100.

### 4.4 Quest seeds
Border village defense; adventurer rank climb; crime syndicate takedown; annual-war skirmish; dungeon delve against superior defenders; world-item contest; marsh tribe conflict.

### 4.5 Still unverified
Exact grade ladder; Vol 3, 6, 8 beats; developer name; NPC level budget beyond 700/100.

---

## 5. Community resources

| Resource | Type | Value |
|---|---|---|
| [Overlord-to-Pathfinder Conversion](https://myd20path.blogspot.com/2018/02/overlord-to-pathfinder-conversion.html) | Tabletop conversion (PF1e) | CR = levels÷4; tier→spell level map; stat mapping; metamagic [C]. Not PF2e compatible. |
| [Yggdrasil TRPG A115 (Scribd)](https://www.scribd.com/document/542244266/Yggdrasil-TRPG-A115) | Homebrew TRPG | Building tiers (tent→castle), leadership, NPC control, magic [C, details paywalled]. |
| [Baidu Baike: Yggdrasil](https://baike.baidu.com/en/item/Yggdrasil/3375515) | Wiki | Densest mechanics summary [C]. |
| [Overlord Wiki (Fandom)](https://overlordmaruyama.fandom.com/wiki/Overlord) | Wiki | Job Class, World Champion, World Item, Items, Tier Spells pages; blocked from fetcher, **not spoiler-filtered**. |
| [Official RPG Maker MV game (2018)](https://siliconera.com/?p=723727) | Official game | Free, Japanese [C]. |

Gap: no 5e conversion or true fan game surfaced.

---

## 6. Sources
- [Baidu Baike — Yggdrasil](https://baike.baidu.com/en/item/Yggdrasil/3375515)
- [Wikipedia — Overlord (novel series)](https://en.wikipedia.org/wiki/Overlord_(novel_series))
- [Yen Press — Overlord series](https://yenpress.com/series/overlord)
- [Overlord-to-Pathfinder Conversion](https://myd20path.blogspot.com/2018/02/overlord-to-pathfinder-conversion.html)
- [Overlord Wiki — Eclipse](https://overlordmaruyama.fandom.com/wiki/Eclipse), [World Champion](https://overlordmaruyama.fandom.com/wiki/World_Champion), [Tier Spells](https://overlordmaruyama.fandom.com/wiki/Tier_Spells)
- [Sportskeeda — Super-Tier Magic](https://sportskeeda.com/anime/overlord-what-super-tier-magic-explained)
- [Siliconera — official RPG](https://siliconera.com/?p=723727)
