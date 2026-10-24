#!/usr/bin/env sh
# Quality gate (docs/game-design.md 5.11). Run by the pre-commit hook and CI.
set -eu
cd "$(git rev-parse --show-toplevel)"

DEFS_URL="https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
DEFS=".cache/globalTypes.d.luau"

step() { printf '\n== %s\n' "$1"; }

step "format"
stylua --check src tests

step "lint"
selene src
(cd tests && selene .)

step "typecheck"
mkdir -p .cache
[ -f "$DEFS" ] || curl -fsSL -o "$DEFS" "$DEFS_URL"
rojo sourcemap default.project.json --output sourcemap.json
luau-lsp analyze --platform=roblox --definitions="@roblox=$DEFS" --sourcemap=sourcemap.json src

step "unit tests"
lune run tests/run

step "build"
mkdir -p build
rojo build default.project.json --output build/place.rbxlx

step "scans"
sh tools/scan.sh

printf '\nGate passed.\n'
