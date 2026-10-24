# Project rules

Design source of truth: `docs/game-design.md`. Research docs are mechanics reference only and carry series proper nouns; never copy their names into game content.

- Commits: follow `docs/game-design.md` §5.11. Commit each completed logical unit locally once format, lint, typecheck, tests and build pass. Conventional Commits. Never push, tag, or bypass hooks.
- Comments and logs: follow §5.12. Doc comments on public functions are fine; no change-history comments in scripts; runtime logging only through the `Logger` module.
- Best practice outranks a conflicting request. Apply it and record the deviation in the commit body and the decision log (§11).
- Roblox: server authoritative, `--!strict` Luau, Rojo project, UI authored in Studio with layout objects and templates (never built in code).
