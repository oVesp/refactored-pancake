# Dev tools

Code: `Server/Services/DevService.luau`, `ServerStorage/ContentServerOnly/DevAllowlist.luau`; client `DebugController`.

- Chat commands (`TextChatCommand`): `/level n`, `/xp n`, `/class add|remove <class>`, `/spawn <enemy> [level] [count]`, `/clear`, `/god`, `/heal`, `/kill`, `/damage n`, `/give <item> [n]`, `/latency ms` (Studio only).
- Allowed in Studio or for allowlisted UserIds; others get a refusal toast and a throttled warning. Commands are rate-limited.
- `ServerStorage.RunDevCommand` (BindableFunction, Studio only) runs the same handlers for automation, such as Studio MCP playtests.
- Dev players get one of each basic weapon and the wooden shield on join when their profile lacks it (`docs/systems/weapons.md`, Dev kit).
- Dev skills (`Content/Skills`, `source = "Dev"`, delivery `Dev`): Fly, Life Essence, Mana Essence, Discern Enemy, Detect Life and Gate. Never stored in the profile: `SkillService.KnownActives(profile, isDev)` adds them through `Shared/DevSkills` for players `DevService.IsDev` allows, so the server check, the snapshot's `actives`, the hotbar and chat casting agree, and non-devs are refused as `Unknown`. Effects run server-side in `Server/DevSkillEffects` (re-checks dev): Fly toggles the character's `Flying` attribute and `DevSpellController` drives a `LinearVelocity` (Space up, Ctrl down; the movement check skips fliers); Life/Mana Essence toast the target's (else your own) HP/MP; Discern Enemy toasts kind, level, faction, HP and attack/defense; Detect Life sends `ShowDetectedLife` and the client highlights up to 30 living entities within 150 studs for 10 s; Gate teleports to a zone named by id or name (`Gate goblin camp`, chat only) or, with no argument, to the respawn point. Cast them from the hotbar or by typing the name in chat.
- Dev players receive the damage log stream; F2 opens the overlay and shows AI states on nameplates.
- World regeneration: `lune run tools/world/build` rewrites `src/Workspace/Map.rbxmx` and the Goblin template.
- Terrain regeneration: `lune run tools/terrain/build` rewrites `src/ServerStorage/WorldGen/Data` and `build/terrain-preview.ppm`; then in Studio (Edit mode) `require(game.ServerStorage.WorldGen.Apply).Apply()`. See `docs/systems/world-generation.md`.
