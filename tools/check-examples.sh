#!/bin/sh
# check-examples.sh — build every program under examples/ against this package, and run it against a live server.
# Each example is its own executable project (examples/<name>/kama.json, a path dependency on the package) and checks
# its own results: one that does not build, or exits other than 0, fails. The examples read the server from
# REDIS_URL, the TLS one from REDIS_TLS_URL, the Sentinel one from REDIS_SENTINEL_URL and the cluster from
# REDIS_CLUSTER_URL, which this script sets to the test server's ports and PKI, its sentinel topology's plain group, and
# its cluster topology's seeds.
#
#   tools/check-examples.sh                  on redis-8.10
#   tools/check-examples.sh --server S       on the server named (tools/redis.sh list)
#
# `kama` is $KAMA or the PATH. The examples resolve their dependencies from their own kama.lock, which pins the
# newest @kama/tls this package's range admits, as a consumer's would; the package's own tests pin its floor.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KAMA=${KAMA:-kama}
SERVER=redis-8.10
while [ $# -gt 0 ]; do
    case "$1" in
        --server) SERVER=${2:?--server needs a value}; shift 2 ;;
        *) echo "check-examples.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

"$ROOT/tools/redis.sh" up --server "$SERVER" >/dev/null
# shellcheck disable=SC1090
. "$ROOT/out/redistest-$SERVER.env"
REDIS_URL="redis://$REDISTEST_HOST:$REDISTEST_PORT"
REDIS_TLS_URL="rediss://localhost:$REDISTEST_TLS_PORT?tls_ca=$REDISTEST_CERTDIR/ca.crt"
"$ROOT/tools/redis.sh" up --server "$SERVER" --topology sentinel >/dev/null
# shellcheck disable=SC1090
. "$ROOT/out/redistest-sentinel-$SERVER.env"
REDIS_SENTINEL_URL=$REDISTEST_SENTINEL_URL
"$ROOT/tools/redis.sh" up --server "$SERVER" --topology cluster >/dev/null
# shellcheck disable=SC1090
. "$ROOT/out/redistest-cluster-$SERVER.env"
REDIS_CLUSTER_URL=$REDISTEST_CLUSTER_URL
export REDIS_URL REDIS_TLS_URL REDIS_SENTINEL_URL REDIS_CLUSTER_URL
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

failed=""
for manifest in "$ROOT"/examples/*/kama.json; do
    name=$(basename "$(dirname "$manifest")")
    echo "== example $name on $SERVER"
    "$KAMA" pkg install "$manifest" >/dev/null
    if "$KAMA" build "$manifest" --debug -o "$tmp/$name" >/dev/null && "$tmp/$name"; then :; else failed="$failed $name"; fi
done
if [ -n "$failed" ]; then echo "check-examples.sh: FAILED:$failed" >&2; exit 1; fi
echo "check-examples.sh: OK on $SERVER"
