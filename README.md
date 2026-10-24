# Yggdrasil

Roblox action MMORPG. Design: [docs/game-design.md](docs/game-design.md). Current scope: [docs/scope/01-midgard-testing-grounds.md](docs/scope/01-midgard-testing-grounds.md).

## Setup

```sh
rokit install
git lfs install --local
git config core.hooksPath .githooks
```

The source scan needs the forbidden-terms list outside the repo at `~/.yggdrasil/forbidden-terms.txt` (or `$YGG_FORBIDDEN_TERMS`). Ask the content reviewer for it.

## Work

- `rojo serve` and connect the Studio plugin to sync `src/` into the place.
- `sh tools/gate.sh` runs format, lint, typecheck, unit tests, build and scans. The pre-commit hook runs it too.
