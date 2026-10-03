#!/bin/sh
# test.sh — build and run the hermetic unit tests, debug then release. `kama` is taken from $KAMA or the
# PATH. The integration tests need a live server; tools/redis.sh starts one.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

"$KAMA" check "$ROOT/kama.json"
"$KAMA" pkg install "$ROOT/tests/unit/kama.json" >/dev/null
for mode in --debug --release; do
    "$KAMA" build "$ROOT/tests/unit/kama.json" $mode -o "$tmp/unit$mode"
    "$tmp/unit$mode"
done
echo "test.sh: OK"
