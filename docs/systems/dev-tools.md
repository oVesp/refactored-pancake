# Dev tools

Code: `Server/Services/DevService.luau`, `ServerStorage/ContentServerOnly/DevAllowlist.luau`; client `DebugController`.

- Chat commands (`TextChatCommand`): `/level n`, `/xp n`, `/class add|remove <class>`, `/spawn <enemy> [level] [count]`, `/clear`, `/god`, `/heal`, `/kill`, `/damage n`, `/give <item> [n]`, `/latency ms` (Studio only).
- Allowed in Studio or for allowlisted UserIds; others get a refusal toast and a throttled warning. Commands are rate-limited.
- `ServerStorage.RunDevCommand` (BindableFunction, Studio only) runs the same handlers for automation, such as Studio MCP playtests.
- Dev players get one of each basic weapon and the wooden shield on join when their profile lacks it (`docs/systems/weapons.md`, Dev kit).
- Dev players receive the damage log stream; F2 opens the overlay and shows AI states on nameplates.
- World regeneration: `lune run tools/world/build` rewrites `src/Workspace/Map.rbxmx` and the Goblin template.
- Terrain regeneration: `lune run tools/terrain/build` rewrites `src/ServerStorage/WorldGen/Data` and `build/terrain-preview.ppm`; then in Studio (Edit mode) `require(game.ServerStorage.WorldGen.Apply).Apply()`. See `docs/systems/world-generation.md`.
