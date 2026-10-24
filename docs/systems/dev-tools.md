# Dev tools

Code: `Server/Services/DevService.luau`, `ServerStorage/ContentServerOnly/DevAllowlist.luau`; client `DebugController`.

- Chat commands (`TextChatCommand`): `/level n`, `/xp n`, `/class add|remove <class>`, `/spawn <enemy> [level] [count]`, `/clear`, `/god`, `/heal`, `/kill`, `/damage n`, `/give <item> [n]`, `/latency ms` (Studio only).
- Allowed in Studio or for allowlisted UserIds; others get a refusal toast and a throttled warning. Commands are rate-limited.
- `ServerStorage.RunDevCommand` (BindableFunction, Studio only) runs the same handlers for automation, such as Studio MCP playtests.
- Dev players receive the damage log stream; F2 opens the overlay and shows AI states on nameplates.
- World regeneration: `lune run tools/world/build` rewrites `src/Workspace/Map.rbxmx` and the Goblin template.
