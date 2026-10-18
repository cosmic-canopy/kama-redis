#!/bin/sh
# redis.sh — the Redis and Valkey servers the integration tests run against, in containers.
#
#   tools/redis.sh up    [--server S]   start (or reuse) server S, wait until it answers on every port
#   tools/redis.sh down  [--server S]   remove the container
#   tools/redis.sh env   [--server S]   print the REDISTEST_* settings (also written to out/redistest-S.env)
#   tools/redis.sh cli   [--server S] [redis-cli args…]   the container's redis-cli, against the main server
#   tools/redis.sh logs  [--server S]   the main server's log
#   tools/redis.sh smoke [--server S]   one check per authentication case and transport, with the container's redis-cli
#   tools/redis.sh list                 the supported servers
#
# S defaults to redis-8.10. Supported: redis-6.2 redis-7.2 redis-7.4 redis-8.2 redis-8.10, and valkey-7.2
# valkey-8.1 valkey-9.1. Each server gets its own container (kama-redis-S) and four host ports, bound to
# 127.0.0.1 only, so servers can run side by side: the main server in plaintext (the base port), over TLS
# (base + 100), and the locked server, whose default user has a password (base + 200), over TLS that requires a
# client certificate (base + 300).
#
# The runtime is $CONTAINER_RUNTIME, else podman, else docker. The image is the official
# docker.io/library/redis:V or docker.io/valkey/valkey:V; REDISTEST_IMAGE overrides. The server is configured
# from tests/integration/server/ (one ACL user per authentication case, TLS on) and the throwaway PKI from
# tools/gen-test-certs.sh.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVERS="redis-6.2 redis-7.2 redis-7.4 redis-8.2 redis-8.10 valkey-7.2 valkey-8.1 valkey-9.1"
cmd=${1:-}
[ -n "$cmd" ] && shift
SERVER=redis-8.10
if [ "${1:-}" = "--server" ]; then SERVER=${2:?--server needs a value}; shift 2; fi

case "$SERVER" in
    redis-6.2)  BASE=16301 ;;
    redis-7.2)  BASE=16302 ;;
    redis-7.4)  BASE=16303 ;;
    redis-8.2)  BASE=16304 ;;
    redis-8.10) BASE=16305 ;;
    valkey-7.2) BASE=16311 ;;
    valkey-8.1) BASE=16312 ;;
    valkey-9.1) BASE=16313 ;;
    *) echo "redis.sh: unsupported server '$SERVER' (one of: $SERVERS)" >&2; exit 2 ;;
esac
PORT=$BASE
TLS_PORT=$((BASE + 100))
LOCKED_PORT=$((BASE + 200))
MTLS_PORT=$((BASE + 300))
case "$SERVER" in
    redis-*)  IMAGE=${REDISTEST_IMAGE:-docker.io/library/redis:${SERVER#redis-}} ;;
    valkey-*) IMAGE=${REDISTEST_IMAGE:-docker.io/valkey/valkey:${SERVER#valkey-}} ;;
esac

if [ "$cmd" = list ]; then echo "$SERVERS"; exit 0; fi

if [ -n "${CONTAINER_RUNTIME:-}" ]; then RT=$CONTAINER_RUNTIME
elif command -v podman >/dev/null 2>&1; then RT=podman
elif command -v docker >/dev/null 2>&1; then RT=docker
else echo "redis.sh: neither podman nor docker found (set CONTAINER_RUNTIME)" >&2; exit 1
fi

NAME="kama-redis-$SERVER"
ENVFILE="$ROOT/out/redistest-$SERVER.env"

running() { [ "$("$RT" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)" = "true" ]; }

write_env() {
    mkdir -p "$ROOT/out"
    cat > "$ENVFILE" <<EOF
REDISTEST_SERVER=$SERVER
REDISTEST_HOST=127.0.0.1
REDISTEST_PORT=$PORT
REDISTEST_TLS_PORT=$TLS_PORT
REDISTEST_LOCKED_PORT=$LOCKED_PORT
REDISTEST_MTLS_PORT=$MTLS_PORT
REDISTEST_CERTDIR=$ROOT/out/test-certs
REDISTEST_KEY_PASSWORD=kr_client_key_pw
REDISTEST_CERT_USER_PASSWORD=kr_cert_pw
REDISTEST_DEFAULT_PASSWORD=kr_default_pw
REDISTEST_ACL_PASSWORD=kr_acl_pw
REDISTEST_RO_PASSWORD=kr_ro_pw
REDISTEST_OFF_PASSWORD=kr_off_pw
EOF
}

# Ready means every listener answers: plaintext, TLS, and the locked server in plaintext and over TLS, from inside
# the container.
wait_ready() {
    i=0
    while [ $i -lt 60 ]; do
        if "$RT" exec "$NAME" sh -c 'redis-cli -p 6379 ping && redis-cli -p 6380 --tls --cacert /run/kr/certs/ca.crt ping && redis-cli -p 6381 -a kr_default_pw --no-auth-warning ping && redis-cli -p 6382 --tls --cacert /run/kr/certs/ca.crt --cert /certs/client.crt --key /certs/client.key -a kr_default_pw --no-auth-warning ping' 2>/dev/null | grep -c PONG | grep -qx 4; then
            return 0
        fi
        running || { echo "redis.sh: $NAME exited during startup:" >&2; "$RT" logs "$NAME" 2>&1 | tail -30 >&2; exit 1; }
        sleep 1; i=$((i + 1))
    done
    echo "redis.sh: $NAME not ready after 60 s" >&2; "$RT" logs "$NAME" 2>&1 | tail -30 >&2; exit 1
}

case "$cmd" in
    up)
        "$ROOT/tools/gen-test-certs.sh" >/dev/null
        if running; then
            echo "redis.sh: $NAME already running on 127.0.0.1:$PORT (TLS $TLS_PORT, locked $LOCKED_PORT, locked TLS $MTLS_PORT)"
        else
            "$RT" rm -f "$NAME" >/dev/null 2>&1 || true
            # The entrypoint is replaced by start.sh, so the servers run as the container's root user.
            "$RT" run -d --name "$NAME" \
                -p "127.0.0.1:$PORT:6379" -p "127.0.0.1:$TLS_PORT:6380" -p "127.0.0.1:$LOCKED_PORT:6381" -p "127.0.0.1:$MTLS_PORT:6382" \
                -v "$ROOT/out/test-certs:/certs:ro" \
                -v "$ROOT/tests/integration/server:/kr:ro" \
                --entrypoint /kr/start.sh \
                "$IMAGE" >/dev/null
            wait_ready
            echo "redis.sh: $NAME ready on 127.0.0.1:$PORT (TLS $TLS_PORT, locked $LOCKED_PORT, locked TLS $MTLS_PORT): $("$RT" exec "$NAME" redis-server --version)"
        fi
        write_env
        ;;
    down)
        "$RT" rm -f "$NAME" >/dev/null 2>&1 || true
        rm -f "$ENVFILE"
        echo "redis.sh: $NAME removed"
        ;;
    env)
        write_env
        cat "$ENVFILE"
        ;;
    cli)
        exec "$RT" exec -i "$NAME" redis-cli -p 6379 "$@"
        ;;
    logs)
        exec "$RT" logs "$NAME"
        ;;
    smoke)
        # One check per case, from inside the container, so this checks the SERVER's configuration
        # independently of the kama client. Each expectation is a shell pattern over redis-cli's output.
        "$RT" exec -i "$NAME" sh -eu -s <<'EOF'
n=0
try() {  # try <pattern> <what> <redis-cli args…>
    want=$1; what=$2; shift 2
    got=$(redis-cli --no-auth-warning "$@" 2>&1 || true)
    case "$got" in
        $want) echo "  ok    $what"; n=$((n + 1)) ;;
        *) echo "  WRONG $what (expected $want): $got"; exit 1 ;;
    esac
}
refused() {  # refused <what> <redis-cli args…>: anything but a PONG (TLS 1.3 refuses a client after its handshake)
    what=$1; shift
    got=$(redis-cli --no-auth-warning "$@" 2>&1 || true)
    case "$got" in
        *PONG*) echo "  WRONG $what (expected a refusal): $got"; exit 1 ;;
        *) echo "  ok    $what"; n=$((n + 1)) ;;
    esac
}
CA="--cacert /run/kr/certs/ca.crt"
try PONG          "default user, no password"           -p 6379 ping
try "*proto*3*"   "HELLO 3 (RESP3)"                     -p 6379 hello 3
try PONG          "ACL user and password"               -p 6379 --user kr_acl --pass kr_acl_pw ping
try "*WRONGPASS*" "ACL user, wrong password"            -p 6379 --user kr_acl --pass wrong ping
try 0             "read-only user reads"                -p 6379 --user kr_ro --pass kr_ro_pw exists kr:none
try "*NOPERM*"    "read-only user writes"               -p 6379 --user kr_ro --pass kr_ro_pw set kr:k v
try "*WRONGPASS*" "disabled user"                       -p 6379 --user kr_off --pass kr_off_pw ping
try PONG          "nopass user, any password"           -p 6379 --user kr_nopass --pass anything ping
try "*NOAUTH*"    "locked server, no password"          -p 6381 ping
try PONG          "locked server, AUTH <password>"      -p 6381 -a kr_default_pw ping
try "*WRONGPASS*" "locked server, wrong password"       -p 6381 -a wrong ping
try PONG          "TLS, server verified"                -p 6380 --tls $CA ping
try PONG          "TLS, client certificate"             -p 6380 --tls $CA --cert /certs/client.crt --key /certs/client.key ping
try "*Could not*" "TLS, server's CA not trusted"        -p 6380 --tls --cacert /certs/other-ca.crt ping
refused           "TLS, client certificate untrusted"   -p 6380 --tls $CA --cert /certs/other-client.crt --key /certs/other-client.key ping
CERT="--cert /certs/client.crt --key /certs/client.key"
try PONG          "TLS, client certificate required, given"   -p 6382 --tls $CA $CERT -a kr_default_pw ping
refused           "TLS, client certificate required, missing" -p 6382 --tls $CA -a kr_default_pw ping
# start.sh gives tls-auth-clients-user CN to the servers that have it; on the others a certificate logs no one in.
case "$(redis-cli --no-auth-warning -p 6381 -a kr_default_pw config get tls-auth-clients-user 2>&1)" in
    *CN*) try kr_cert  "TLS, a certificate logs in as its CN"      -p 6382 --tls $CA $CERT acl whoami ;;
    *)    try "*NOAUTH*" "TLS, a certificate logs no one in"       -p 6382 --tls $CA $CERT acl whoami ;;
esac
try PONG          "Unix socket"                         -s /run/kr/redis.sock ping
echo "  $n checks"
EOF
        echo "redis.sh: smoke OK against $NAME ($("$RT" exec "$NAME" redis-server --version | sed 's/ sha=.*//'))"
        ;;
    *)
        sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
