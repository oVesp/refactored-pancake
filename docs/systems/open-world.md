# Open world (experiment)

Branch `exp/open-world`. The owner switched the design from a zone-banded RPG to an open sandbox RPG in the vein of Kenshi (2026-10-29): factions live in the world on their own, patrols walk behind their leaders, towns have residents, travelers and merchant caravans use the roads, and monsters come from nests that are not obvious. Village safety and zone danger bands stay (game-design.md §3.7).

## Factions

Data: `Content/Factions.luau`. Logic: `Shared/Relations.luau` (pure, unit-tested in `tests/specs/Relations.spec.luau`).

- Every entity's `team` is a faction id: `Adventurers` (players), `HolyKingdom`, `DragonEmpire`, `Elves`, `Town`, `Merchants`, `Travelers`, `Goblins`, `Undead`, `Dragons`, `Neutral` (training dummies).
- **Great powers**: the Holy Kingdom and the Dragon Empire are at war. The Adventurers are neutral to both; the world treats a player as one more adventurer. Elves are a minor nation. Town, Merchants and Travelers are civilian roles; who owns their settlement comes from the continent template ([world generation](world-generation.md)).
- `Relations` lists each pair that is not Neutral, as `Hostile` or `Allied`; pairs are symmetric and a faction is Allied with itself.
- `EntityService.AreEnemies` is `Relations.Hostile` or a grudge. Faction fights follow the table. Players cannot hurt other players (no PvP), but outside safe zones they can attack any NPC, whatever the standing; that NPC and its squad then fight back ([stances and grudges](ai-and-spawning.md#tasks)). Inside safe zones people are non-combat.
- A faction marked `monster` is hostile to players. Monsters never enter safe zones; civilians do.
- Goblins, Undead and Dragons are monsters: hostile to every people and to each other. Dragons leave the Dragon Empire and the Elves alone.

## People

Data: `Content/Npcs.luau` (same shape as `Content/Enemies`; `Shared/NpcDefs.Get` looks up both). Villager, Guard, Crossbow Guard, Merchant, Caravan Guard, Traveler, Kingdom Soldier, Kingdom Sergeant (placeholders on the Human rig).

- `template = "Human"`: `SpawnService` builds an R15 body from a random `Appearance` look in one of the def's `outfits`, removes its stock Animate script and sets `AnimSet = "Human"`; the display name is a given name from `Content/Names` plus the role.
- Clips: `HumanIdle/Walk/Run` are Roblox stock clips and `HumanAttack/Throw` alias `BasicStrike` (set `Human` in `content/animations/human.json`). `EnemyAnimationController` animates models tagged `Enemy` or `Npc`.
- Civilians (villagers, merchants) have morale always below `fleeBelow`: they run home from any monster they see.
- Merchants carry a `Trade` prompt that opens the vendor panel through the trainer flow; it opens the shop screen ([economy](economy.md)).

## Population

Data: `ServerStorage/ContentServerOnly/Population.luau` (server-only). Services: `GroupService` (groups, formations, LOD) and `PopulationService` (who is out and when). Tuning: `Tuning.Population`.

| Kind | Behaviour |
|---|---|
| Garrison | Stands at a post (`wander` radius); each dead member is replaced after `respawnSeconds`. Town gates and plaza watch. |
| Patrol | Walks a looped route behind its leader, waits at `stops`. Starts mid-route at server start. Re-sent `interval` s after it is wiped out. |
| Caravan | Merchant leading its guards: down the highland stairs, through orchard and fields, a market stop on the plaza, back up. Day only, one at a time. |
| Traveler | Small parties on open routes; they leave the world at the end. |
| Residents | Villagers wandering the village: `day` out by day, `night` at night; extras go indoors once no player is within 140 studs. |
| Nest | Hidden monster source. `stationed` garrisons hold a lair (for example a goblin camp and its Chieftain); `squads` leave behind their first member to roam the `territory` loop, sent only while no player is within `HiddenRadius` of the nest. `time = "Night"` nests (the field barrow's skeletons) recall their squads at dawn, unseen. |

### Groups and level of detail

- A group far from every player is data only: it moves along its route at `AbstractSpeed` × its slowest member's speed and waits at stops.
- Within `MaterializeRadius` of a player it gets bodies around its position (wounds kept as an HP share); beyond `DematerializeRadius` it loses them, never mid-fight. `MaxBodies` caps bodies on the server.
- With bodies, the first member listed leads: its goal is `Lookahead` studs along the route, and the route only advances while it is near it and no follower is more than `FollowLag` from its follow slot. The others run the FollowLeader task, a loose clump behind it ([tasks](ai-and-spawning.md#tasks)). Stations stand in a ring (`Shared/Formation`).
- When a member is hit or sees an enemy, the whole group fights: AI and group combat take over and homes freeze where the fight started. Afterwards the group resumes from the nearest route point (`Route.Nearest`).
- If the leader dies, the first member with `combat.leader` takes over. With none, the squad stops and mills about, and morale decides whether it flees in a fight; once no player is within `HiddenRadius` it disbands and its schedule sends a fresh group after `interval`.
- An open route's group is removed at the end once no player is within half the materialize radius.

### Routes

Points are `{ x, z }`; heights come from a ground raycast. Only goblins roam for now (owner, 2026-10-30): `goblin_camp_patrol` circles the goblin camp (a Brute, nobody to promote), and the nests `goblin_camp`, `orchard_thicket` and `field_burrow` send squads around territory loops on the Verdant Greens pads. Other kinds come back per site and road as regions are built ([world generation](world-generation.md)); routes must then follow generated roads.

## Not done

- `Population` holds only goblin parties until the continent's regions are built.
- No trading (currency and a shop UI are needed), no faction reputation, no player squads, no NPC needs or jobs.
- Monsters cannot raid inside the safe village (owner kept it safe).
