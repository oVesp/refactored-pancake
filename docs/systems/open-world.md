# Open world (experiment)

Branch `exp/open-world`. The owner switched the design from a zone-banded RPG to an open sandbox RPG in the vein of Kenshi (2026-10-29): factions live in the world on their own, patrols march in formation, towns have residents, travelers and merchant caravans use the roads, and monsters come from nests that are not obvious. Village safety and zone danger bands stay (game-design.md §3.7).

## Factions

Data: `Content/Factions.luau`. Logic: `Shared/Relations.luau` (pure, unit-tested in `tests/specs/Relations.spec.luau`).

- Every entity's `team` is a faction id: `Players`, `Town`, `Merchants`, `Travelers`, `Goblins`, `Undead`, `Neutral` (training dummies).
- `Relations` lists each pair that is not Neutral, as `Hostile` or `Allied`; pairs are symmetric and a faction is Allied with itself.
- `EntityService.AreEnemies` is `Relations.Hostile`, so every hit check, AoE and AI target follows the table. Players are Allied with the civilian factions and cannot hurt them; they cannot hurt other players (no PvP).
- A faction marked `monster` is hostile to players. Monsters never enter safe zones; civilians do.
- Goblins and Undead are hostile to each other.
