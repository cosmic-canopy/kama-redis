#!/bin/sh
# test.sh — build and run the hermetic unit tests, debug then release. `kama` is taken from $KAMA or the
# PATH. The integration tests need a live server; tools/redis.sh starts one.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# The version CLIENT SETINFO gives the server (src/connection.kama) is the package's.
want=$(sed -n 's/^  "version": "\([^"]*\)",$/\1/p' "$ROOT/kama.json")
got=$(sed -n 's/^fn string libraryVersion() { return "\([^"]*\)"; }$/\1/p' "$ROOT/src/connection.kama")
[ -n "$want" ] && [ "$want" = "$got" ] || { echo "test.sh: libraryVersion() in src/connection.kama is \"$got\", kama.json's version \"$want\"" >&2; exit 1; }

"$KAMA" check "$ROOT/kama.json"
"$KAMA" pkg install "$ROOT/tests/unit/kama.json" >/dev/null
for mode in --debug --release; do
    "$KAMA" build "$ROOT/tests/unit/kama.json" $mode -o "$tmp/unit$mode"
    "$tmp/unit$mode"
done
echo "test.sh: OK"
