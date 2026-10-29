# Open world (experiment)

Branch `exp/open-world`. The owner switched the design from a zone-banded RPG to an open sandbox RPG in the vein of Kenshi (2026-10-29): factions live in the world on their own, patrols march in formation, towns have residents, travelers and merchant caravans use the roads, and monsters come from nests that are not obvious. Village safety and zone danger bands stay (game-design.md §3.7).

## Factions

Data: `Content/Factions.luau`. Logic: `Shared/Relations.luau` (pure, unit-tested in `tests/specs/Relations.spec.luau`).

- Every entity's `team` is a faction id: `Adventurers` (players), `HolyKingdom`, `DragonEmpire`, `Elves`, `Town`, `Merchants`, `Travelers`, `Goblins`, `Undead`, `Dragons`, `Neutral` (training dummies).
- **Great powers**: the Holy Kingdom and the Dragon Empire are at war. The Adventurers are neutral to both; the world treats a player as one more adventurer. Elves are a minor nation. Town, Merchants and Travelers are civilian roles; who owns their settlement comes from the continent template ([world generation](world-generation.md)).
- `Relations` lists each pair that is not Neutral, as `Hostile` or `Allied`; pairs are symmetric and a faction is Allied with itself.
- `EntityService.AreEnemies` is `Relations.Hostile`, so every hit check, AoE and AI target follows the table. Adventurers are Allied with the civilian factions and cannot hurt them; they cannot hurt other players (no PvP).
- A faction marked `monster` is hostile to players. Monsters never enter safe zones; civilians do.
- Goblins, Undead and Dragons are monsters: hostile to every people and to each other. Dragons leave the Dragon Empire and the Elves alone.

## People

Data: `Content/Npcs.luau` (same shape as `Content/Enemies`; `Shared/NpcDefs.Get` looks up both). Villager, Guard, Crossbow Guard, Merchant, Caravan Guard, Traveler.

- `template = "Human"`: `SpawnService` builds an R15 body from a random `Appearance` look in one of the def's `outfits`, removes its stock Animate script and sets `AnimSet = "Human"`; the display name is a given name from `Content/Names` plus the role.
- Clips: `HumanIdle/Walk/Run` are Roblox stock clips (`Assets.Stock`), `HumanAttack/Throw` alias `BasicStrike` (`Assets.AnimAliases`). `EnemyAnimationController` animates models tagged `Enemy` or `Npc`.
- Civilians (villagers, merchants) have morale always below `fleeBelow`: they run home from any monster they see.
- Merchants carry a `Trade` prompt that opens the vendor panel through the trainer flow; it answers *VendorClosed* until there is a currency and a Studio-authored shop UI.

## Population

Data: `ServerStorage/ContentServerOnly/Population.luau` (server-only). Services: `GroupService` (groups, formations, LOD) and `PopulationService` (who is out and when). Tuning: `Tuning.Population`.

| Kind | Behaviour |
|---|---|
| Garrison | Stands at a post (`wander` radius); each dead member is replaced after `respawnSeconds`. Town gates and plaza watch. |
| Patrol | Walks a looped route in formation, waits at `stops`. Starts mid-route at server start. Re-sent `interval` s after it is wiped out. |
| Caravan | Merchant plus guards in a column: down the highland stairs, through orchard and fields, a market stop on the plaza, back up. Day only, one at a time. |
| Traveler | Small parties on open routes; they leave the world at the end. |
| Residents | Villagers wandering the village: `day` out by day, `night` at night; extras go indoors once no player is within 140 studs. |
| Nest | Hidden monster source. `stationed` garrisons hold a lair (the goblin camp and its Chieftain); `squads` leave in formation to roam the `territory` loop, sent only while no player is within `HiddenRadius` of the nest. `time = "Night"` nests (the field barrow's skeletons) recall their squads at dawn, unseen. |

### Groups and level of detail

- A group far from every player is data only: it moves along its route at `AbstractSpeed` × its slowest member's speed and waits at stops.
- Within `MaterializeRadius` of a player it gets bodies at its formation slots (wounds kept as an HP share); beyond `DematerializeRadius` it loses them, never mid-fight. `MaxBodies` caps bodies on the server.
- With bodies, the leader's goal is `Lookahead` studs along the route; the route only advances while the leader is near it and no follower is more than `FollowLag` from its slot. Followers' goals and homes are their slots (`Shared/Formation`: Column, Line, Wedge, Ring).
- A fight breaks the formation: AI and group combat take over and homes freeze where the fight started. Afterwards the group resumes from the nearest route point (`Route.Nearest`).
- An open route's group is removed at the end once no player is within half the materialize radius.

### Routes

Points are `{ x, z }`; heights come from a ground raycast. The data is empty since the continent replaced the centre section (2026-10-29); entries come back per site and road as regions are built ([world generation](world-generation.md)). Routes must then follow generated roads.

## Not done

- No live Studio check yet (no Studio was connected when this landed).
- `Population` is empty until the continent's regions are built.
- No trading (currency and a shop UI are needed), no faction reputation, no player squads, no NPC needs or jobs.
- Monsters cannot raid inside the safe village (owner kept it safe).
