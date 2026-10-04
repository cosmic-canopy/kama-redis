#!/bin/sh
# test-integration.sh — the live tests (tests/integration) against each server in the matrix, debug and release.
#
#   tools/test-integration.sh                    every server (tools/redis.sh list)
#   tools/test-integration.sh --server S …       the servers named
#   tools/test-integration.sh --down …           remove each server's container when its run is done
#
# Each server is started (or reused) by tools/redis.sh, which writes its REDISTEST_* settings; this script exports
# them and runs both builds against it. `kama` is $KAMA or the PATH. When a case fails, `tools/redis.sh smoke
# --server S` tells a misconfigured server from a wrong client.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
SERVERS=""
DOWN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --server) SERVERS="$SERVERS ${2:?--server needs a value}"; shift 2 ;;
        --down) DOWN=1; shift ;;
        *) echo "test-integration.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done
[ -n "$SERVERS" ] || SERVERS=$("$ROOT/tools/redis.sh" list)
tmp=$(mktemp -d)
# The socket test's sockets get a short directory of their own: a socket path is at most 103 bytes on macOS.
sockets=$(mktemp -d /tmp/krd.XXXXXX)
trap 'rm -rf "$tmp" "$sockets"' EXIT

"$KAMA" pkg install "$ROOT/tests/integration/kama.json" >/dev/null
for mode in --debug --release; do
    "$KAMA" build "$ROOT/tests/integration/kama.json" $mode -o "$tmp/integration$mode" >/dev/null
done

failed=""
for s in $SERVERS; do
    "$ROOT/tools/redis.sh" up --server "$s" >/dev/null
    for mode in --debug --release; do
        dir="$sockets/$s$mode"; mkdir -p "$dir"
        echo "== $s ($mode)"
        if ( set -a; . "$ROOT/out/redistest-$s.env"; set +a; REDISTEST_SOCKDIR="$dir" "$tmp/integration$mode" ); then :; else failed="$failed $s$mode"; fi
    done
    [ "$DOWN" = 1 ] && "$ROOT/tools/redis.sh" down --server "$s" >/dev/null
done
if [ -n "$failed" ]; then echo "test-integration.sh: FAILED on$failed" >&2; exit 1; fi
echo "test-integration.sh: OK on$(printf ' %s' $SERVERS)"
