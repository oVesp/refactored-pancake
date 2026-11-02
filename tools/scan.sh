#!/usr/bin/env sh
# Source scans: raw prints, secrets, forbidden terms (docs/game-design.md 2, 5.11, 5.12).
set -eu
cd "$(git rev-parse --show-toplevel)"
failed=0

prints=$(grep -rnE '(^|[^:.A-Za-z_])print\(' src --include='*.luau' | grep -v '^src/ReplicatedStorage/Shared/Logger.luau:' || true)
if [ -n "$prints" ]; then
	printf 'Raw print outside Logger:\n%s\n' "$prints"
	failed=1
fi

secrets=$(grep -rnIiE '_\|WARNING:-DO-NOT-SHARE|ROBLOSECURITY|-----BEGIN [A-Z ]*PRIVATE KEY|x-api-key|api[_-]?key[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/=_-]{16,}' \
	--exclude-dir=.git --exclude-dir=.cache --exclude-dir=build --exclude-dir=Packages --exclude=scan.sh . || true)
if [ -n "$secrets" ]; then
	printf 'Possible secret:\n%s\n' "$secrets"
	failed=1
fi

# The forbidden-terms list lives outside the repo because it holds the source series' character names.
terms="${YGG_FORBIDDEN_TERMS:-$HOME/.yggdrasil/forbidden-terms.txt}"
if [ -f "$terms" ]; then
	hits=$(grep -rnIiwF -f "$terms" src tests || true)
	if [ -n "$hits" ]; then
		printf 'Forbidden term in game content:\n%s\n' "$hits"
		failed=1
	fi
else
	printf 'Forbidden-terms list not found at %s; set YGG_FORBIDDEN_TERMS. Failing closed.\n' "$terms"
	failed=1
fi

exit "$failed"
