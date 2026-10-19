#!/bin/sh
# test.sh — build and run the hermetic unit tests, debug then release. `kama` is taken from $KAMA or the
# PATH. The integration tests need a live server; tools/redis.sh starts one. The TLS tests read the throwaway PKI
# tools/gen-test-certs.sh writes (it needs openssl, or LibreSSL), through REDISTEST_CERTDIR.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# The version CLIENT SETINFO gives the server (src/connection.kama) is the package's.
want=$(sed -n 's/^  "version": "\([^"]*\)",$/\1/p' "$ROOT/kama.json")
got=$(sed -n 's/^fn string libraryVersion() { return "\([^"]*\)"; }$/\1/p' "$ROOT/src/connection.kama")
[ -n "$want" ] && [ "$want" = "$got" ] || { echo "test.sh: libraryVersion() in src/connection.kama is \"$got\", kama.json's version \"$want\"" >&2; exit 1; }

# A fresh checkout has no .kama/deps: install what kama.lock pins (@kama/tls) before anything reads the manifest.
"$KAMA" pkg install "$ROOT/kama.json" >/dev/null
"$KAMA" check "$ROOT/kama.json"
"$ROOT/tools/gen-test-certs.sh" >/dev/null
REDISTEST_CERTDIR="$ROOT/out/test-certs"; export REDISTEST_CERTDIR
"$KAMA" pkg install "$ROOT/tests/unit/kama.json" >/dev/null
for mode in --debug --release; do
    "$KAMA" build "$ROOT/tests/unit/kama.json" $mode -o "$tmp/unit$mode"
    "$tmp/unit$mode"
done
# The examples build, debug and release; tools/check-examples.sh runs them against a live server.
for manifest in "$ROOT"/examples/*/kama.json; do
    "$KAMA" pkg install "$manifest" >/dev/null
    for mode in --debug --release; do "$KAMA" build "$manifest" $mode -o "$tmp/example" >/dev/null; done
done
echo "test.sh: OK"
