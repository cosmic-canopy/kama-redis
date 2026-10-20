#!/bin/sh
# redis.sh — the Redis and Valkey servers the integration tests run against, in containers.
#
#   tools/redis.sh up    [--server S] [--topology T]   start (or reuse) S, wait until every port answers
#   tools/redis.sh down  [--server S] [--topology T]   remove the container
#   tools/redis.sh env   [--server S] [--topology T]   print the REDISTEST_* settings (also written to out/)
#   tools/redis.sh cli   [--server S] [--topology T] [redis-cli args…]   the container's redis-cli
#   tools/redis.sh logs  [--server S] [--topology T]   the servers' logs
#   tools/redis.sh smoke [--server S] [--topology T]   checks of the servers' configuration, with their own redis-cli
#   tools/redis.sh list                 the supported servers
#
# S defaults to redis-8.10. Supported: redis-6.2 redis-7.2 redis-7.4 redis-8.2 redis-8.10, and valkey-7.2
# valkey-8.1 valkey-9.1. T is one of:
#   standalone (the default): one container per server (kama-redis-S) and four host ports, bound to 127.0.0.1 only,
#     so servers can run side by side: the main server in plaintext (the base port), over TLS (base + 100), and the
#     locked server, whose default user has a password (base + 200), over TLS that requires a client certificate
#     (base + 300). Its settings go to out/redistest-S.env.
#   cluster: a cluster of three primaries with a replica each, in a container of its own (kama-redis-cluster-S), each
#     node in plaintext and over TLS (tests/integration/server/cluster.sh). Its settings go to
#     out/redistest-cluster-S.env.
#   sentinel: two groups, each a master, two replicas and three sentinels, one in plaintext and one over TLS whose
#     sentinels take a password (tests/integration/server/sentinel.sh), in kama-redis-sentinel-S. Its settings go
#     to out/redistest-sentinel-S.env.
# A topology's ports are published 1:1 (the container's port is the host's), because its servers name each other's
# addresses to clients (MOVED, CLUSTER SLOTS, GET-MASTER-ADDR-BY-NAME), and an address must mean the same inside the
# container and out. For server k (the base port less 16300), the cluster's nodes take 17000 + 20k + 0..5 in
# plaintext and + 10..15 over TLS; the sentinel topology takes 18000 + 20k: the plain group's servers + 0..2 and its
# sentinels + 3..5, the TLS group's servers + 10..12 and its sentinels + 13..15.
#
# The runtime is $CONTAINER_RUNTIME, else podman, else docker. The image is the official
# docker.io/library/redis:V or docker.io/valkey/valkey:V; REDISTEST_IMAGE overrides. The servers are configured
# from tests/integration/server/ (one ACL user per authentication case, TLS on) and the throwaway PKI from
# tools/gen-test-certs.sh.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVERS="redis-6.2 redis-7.2 redis-7.4 redis-8.2 redis-8.10 valkey-7.2 valkey-8.1 valkey-9.1"
cmd=${1:-}
[ -n "$cmd" ] && shift
SERVER=redis-8.10
TOPOLOGY=standalone
while [ $# -gt 0 ]; do
    case "$1" in
        --server) SERVER=${2:?--server needs a value}; shift 2 ;;
        --topology) TOPOLOGY=${2:?--topology needs a value}; shift 2 ;;
        *) break ;;
    esac
done
case "$TOPOLOGY" in
    standalone|cluster|sentinel) ;;
    *) echo "redis.sh: unsupported topology '$TOPOLOGY' (one of: standalone cluster sentinel)" >&2; exit 2 ;;
esac

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
# seq <from> <count>: the ports from <from> on, space-separated.
seq_ports() { i=0; out=""; while [ $i -lt "$2" ]; do out="$out $(($1 + i))"; i=$((i + 1)); done; echo $out; }
K=$((BASE - 16300))
CB=$((17000 + 20 * K))
CLUSTER_PORTS=$(seq_ports $CB 6)
CLUSTER_TLS_PORTS=$(seq_ports $((CB + 10)) 6)
SB=$((18000 + 20 * K))
PLAIN_DATA=$(seq_ports $SB 3)
PLAIN_SENTINELS=$(seq_ports $((SB + 3)) 3)
TLS_DATA=$(seq_ports $((SB + 10)) 3)
TLS_SENTINELS=$(seq_ports $((SB + 13)) 3)
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

if [ "$TOPOLOGY" = standalone ]; then
    NAME="kama-redis-$SERVER"
    ENVFILE="$ROOT/out/redistest-$SERVER.env"
else
    NAME="kama-redis-$TOPOLOGY-$SERVER"
    ENVFILE="$ROOT/out/redistest-$TOPOLOGY-$SERVER.env"
fi

running() { [ "$("$RT" inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null || true)" = "true" ]; }

# hosts <ports…>: "127.0.0.1:P,127.0.0.1:Q,…", a URL's hosts; csv <ports…>: "P,Q,…".
hosts() { out=""; for p in "$@"; do out="$out${out:+,}127.0.0.1:$p"; done; echo "$out"; }
csv() { out=""; for p in "$@"; do out="$out${out:+,}$p"; done; echo "$out"; }

write_env() {
    mkdir -p "$ROOT/out"
    case "$TOPOLOGY" in
        cluster)
            cat > "$ENVFILE" <<EOF
REDISTEST_SERVER=$SERVER
REDISTEST_TOPOLOGY=cluster
REDISTEST_HOST=127.0.0.1
REDISTEST_CLUSTER_PORTS=$(csv $CLUSTER_PORTS)
REDISTEST_CLUSTER_TLS_PORTS=$(csv $CLUSTER_TLS_PORTS)
REDISTEST_CLUSTER_URL=redis://$(hosts $CLUSTER_PORTS)
REDISTEST_CLUSTER_TLS_URL=rediss://$(hosts $CLUSTER_TLS_PORTS)
REDISTEST_CERTDIR=$ROOT/out/test-certs
REDISTEST_ACL_PASSWORD=kr_acl_pw
REDISTEST_RO_PASSWORD=kr_ro_pw
EOF
            return ;;
        sentinel)
            cat > "$ENVFILE" <<EOF
REDISTEST_SERVER=$SERVER
REDISTEST_TOPOLOGY=sentinel
REDISTEST_HOST=127.0.0.1
REDISTEST_SENTINEL_MASTER=kr
REDISTEST_SENTINEL_DATA_PORTS=$(csv $PLAIN_DATA)
REDISTEST_SENTINEL_PORTS=$(csv $PLAIN_SENTINELS)
REDISTEST_SENTINEL_TLS_DATA_PORTS=$(csv $TLS_DATA)
REDISTEST_SENTINEL_TLS_PORTS=$(csv $TLS_SENTINELS)
REDISTEST_SENTINEL_URL=redis-sentinel://$(hosts $PLAIN_SENTINELS)?master_name=kr
REDISTEST_SENTINEL_TLS_URL=rediss-sentinel://$(hosts $TLS_SENTINELS)?master_name=kr
REDISTEST_SENTINEL_USER=kr_sentinel
REDISTEST_SENTINEL_PASSWORD=kr_sentinel_pw
REDISTEST_CERTDIR=$ROOT/out/test-certs
REDISTEST_ACL_PASSWORD=kr_acl_pw
EOF
            return ;;
    esac
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
wait_standalone() {
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

# A cluster is ready when every node says the cluster is ok and knows all six, and every replica's link to its primary
# is up.
wait_cluster() {
    i=0
    while [ $i -lt 90 ]; do
        if "$RT" exec "$NAME" sh -c '
            n=0
            for p in $KR_PORTS; do
                info=$(redis-cli -p "$p" cluster info 2>/dev/null) || exit 1
                case "$info" in *cluster_state:ok*cluster_known_nodes:6*) ;; *) exit 1 ;; esac
                case "$(redis-cli -p "$p" role 2>/dev/null | head -1)" in
                    slave) redis-cli -p "$p" info replication | grep -q master_link_status:up || exit 1; n=$((n + 1)) ;;
                esac
            done
            [ "$n" -eq 3 ]' >/dev/null 2>&1; then
            return 0
        fi
        running || { echo "redis.sh: $NAME exited during startup:" >&2; "$RT" logs "$NAME" 2>&1 | tail -30 >&2; exit 1; }
        sleep 1; i=$((i + 1))
    done
    echo "redis.sh: $NAME not ready after 90 s" >&2
    "$RT" exec "$NAME" sh -c 'tail -n 20 /run/kr/cluster/create.log /run/kr/cluster/node-*.log' >&2 2>/dev/null || true
    exit 1
}

# A sentinel group is ready when each of its sentinels knows the master, both replicas and the other two sentinels,
# and every replica's link to the master is up.
wait_sentinel() {
    i=0
    while [ $i -lt 90 ]; do
        if "$RT" exec "$NAME" sh -c '
            # flags: the flags of each entry of a SENTINEL REPLICAS or SENTINELS reply, as redis-cli prints it.
            flags() { awk "prev == \"flags\" { print } { prev = \$0 }"; }
            ready() {  # ready <data ports> <sentinel ports> <data options> <sentinel options>
                for s in $2; do
                    redis-cli $4 -p "$s" sentinel get-master-addr-by-name kr 2>/dev/null | grep -q 127.0.0.1 || return 1
                    [ "$(redis-cli $4 -p "$s" sentinel replicas kr 2>/dev/null | flags | grep -cx slave)" -eq 2 ] || return 1
                    [ "$(redis-cli $4 -p "$s" sentinel sentinels kr 2>/dev/null | flags | grep -cx sentinel)" -eq 2 ] || return 1
                done
                for d in $1; do
                    case "$(redis-cli $3 -p "$d" role 2>/dev/null | head -1)" in
                        slave) redis-cli $3 -p "$d" info replication | grep -q master_link_status:up || return 1 ;;
                    esac
                done
            }
            T="--tls --cacert /run/kr/certs/ca.crt"
            ready "$KR_PLAIN_DATA" "$KR_PLAIN_SENTINELS" "" "" &&
            ready "$KR_TLS_DATA" "$KR_TLS_SENTINELS" "$T" "$T --user kr_sentinel --pass kr_sentinel_pw --no-auth-warning"' >/dev/null 2>&1; then
            return 0
        fi
        running || { echo "redis.sh: $NAME exited during startup:" >&2; "$RT" logs "$NAME" 2>&1 | tail -30 >&2; exit 1; }
        sleep 1; i=$((i + 1))
    done
    echo "redis.sh: $NAME not ready after 90 s" >&2
    "$RT" exec "$NAME" sh -c 'tail -n 20 /run/kr/sentinel/*.log' >&2 2>/dev/null || true
    exit 1
}

# publish <ports…>: each one 1:1 on the host's 127.0.0.1.
publish() { for p in "$@"; do printf ' -p 127.0.0.1:%s:%s' "$p" "$p"; done; }

# The cluster's configuration, from inside its container with its own redis-cli: what this client relies on.
smoke_cluster() {
    "$RT" exec -i "$NAME" sh -eu -s <<'EOF'
n=0
ok() { echo "  ok    $1"; n=$((n + 1)); }
wrong() { echo "  WRONG $1"; exit 1; }
among() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }   # among <word> <list>
T="--tls --cacert /run/kr/certs/ca.crt"
set -- $KR_PORTS; P0=$1
set -- $KR_TLS_PORTS; T0=$1
info=$(redis-cli -p "$P0" cluster info)
case "$info" in *cluster_state:ok*) ok "the cluster is ok" ;; *) wrong "the cluster is not ok: $info" ;; esac
case "$info" in
    *cluster_slots_assigned:16384*cluster_known_nodes:6*cluster_size:3*) ok "16384 slots, six nodes, three shards" ;;
    *) wrong "the cluster is not three shards of two: $info" ;;
esac
# A port is a number past the last slot; every one CLUSTER SLOTS names must be the asking connection's kind.
ports() { awk '/^[0-9]+$/ && $1 > 16383'; }
bad=""; for q in $(redis-cli -p "$P0" cluster slots | ports); do among "$q" "$KR_PORTS" || bad="$bad $q"; done
[ -z "$bad" ] && ok "CLUSTER SLOTS names plaintext ports to a plaintext client" || wrong "CLUSTER SLOTS named$bad to a plaintext client"
bad=""; for q in $(redis-cli $T -p "$T0" cluster slots | ports); do among "$q" "$KR_TLS_PORTS" || bad="$bad $q"; done
[ -z "$bad" ] && ok "CLUSTER SLOTS names TLS ports to a TLS client" || wrong "CLUSTER SLOTS named$bad to a TLS client"
# The primary that owns kr:smoke answers SET; each other primary answers MOVED to it, by the asking connection's kind.
owner=""; moved=""; tlsmoved=""
set -- $KR_TLS_PORTS
for p in $KR_PORTS; do
    t=$1; shift
    [ "$(redis-cli -p "$p" role | head -1)" = master ] || continue
    got=$(redis-cli -p "$p" set kr:smoke 1 2>&1)
    case "$got" in
        OK) owner=$p ;;
        *MOVED*) moved="$moved ${got##*:}"; g=$(redis-cli $T -p "$t" get kr:smoke 2>&1); tlsmoved="$tlsmoved ${g##*:}" ;;
    esac
done
[ -n "$owner" ] && ok "the slot's primary takes a write" || wrong "no primary took the write"
bad=""; for q in $moved; do [ "$q" = "$owner" ] || bad="$bad $q"; done
[ -n "$moved" ] && [ -z "$bad" ] && ok "the other primaries answer MOVED to it" || wrong "MOVED pointed at$moved, not $owner"
bad=""; for q in $tlsmoved; do among "$q" "$KR_TLS_PORTS" || bad="$bad $q"; done
[ -n "$tlsmoved" ] && [ -z "$bad" ] && ok "MOVED names a TLS port to a TLS client" || wrong "MOVED named$tlsmoved to a TLS client"
case "$(printf 'SET kr:smoke 2\nWAIT 1 2000\n' | redis-cli -p "$owner")" in
    *OK*1*) ok "a replica acknowledges the write (WAIT)" ;;
    *) wrong "no replica acknowledged the write" ;;
esac
served=0
for p in $KR_PORTS; do
    [ "$(redis-cli -p "$p" role | head -1)" = slave ] || continue
    [ "$(printf 'READONLY\nGET kr:smoke\n' | redis-cli -p "$p" | tail -1)" = 2 ] && served=$((served + 1))
done
[ "$served" -eq 1 ] && ok "the slot's replica serves a read after READONLY" || wrong "$served replicas served the read"
[ "$(redis-cli -c -p "$P0" get kr:smoke)" = 2 ] && ok "redis-cli -c follows MOVED" || wrong "redis-cli -c did not follow MOVED"
[ "$(redis-cli -c $T -p "$T0" get kr:smoke)" = 2 ] && ok "redis-cli -c follows MOVED over TLS" || wrong "redis-cli -c did not follow MOVED over TLS"
case "$(redis-cli -c -p "$P0" --user kr_ro --pass kr_ro_pw --no-auth-warning set kr:smoke 3 2>&1)" in
    *NOPERM*) ok "the read-only user's write is refused" ;; *) wrong "the read-only user wrote" ;;
esac
case "$(redis-cli -p "$P0" debug sleep 0 2>&1)" in OK) ok "DEBUG is enabled (DEBUG SLEEP fails a node over)" ;; *) wrong "DEBUG is not enabled" ;; esac
redis-cli -c -p "$P0" del kr:smoke >/dev/null
echo "  $n checks"
EOF
    echo "redis.sh: smoke OK against $NAME ($("$RT" exec "$NAME" redis-server --version | sed 's/ sha=.*//'))"
}

# Both sentinel groups' configuration, from inside their container with its own redis-cli.
smoke_sentinel() {
    "$RT" exec -i "$NAME" sh -eu -s <<'EOF'
n=0
ok() { echo "  ok    $1"; n=$((n + 1)); }
wrong() { echo "  WRONG $1"; exit 1; }
among() { case " $2 " in *" $1 "*) return 0 ;; esac; return 1; }
T="--tls --cacert /run/kr/certs/ca.crt"
AUTH="--user kr_sentinel --pass kr_sentinel_pw --no-auth-warning"
flags() { awk 'prev == "flags" { print } { prev = $0 }'; }
# group <name> <data ports> <sentinel ports> <data options> <sentinel options>: the checks each group passes.
group() {
    g=$1; data=$2; sentinels=$3; dopt=$4; sopt=$5
    master=""
    for s in $sentinels; do
        addr=$(redis-cli $sopt -p "$s" sentinel get-master-addr-by-name kr | tr '\n' ' ')
        port=${addr#* }; port=${port% }
        among "$port" "$data" || wrong "$g: sentinel $s names the master $addr"
        [ -z "$master" ] || [ "$master" = "$port" ] || wrong "$g: the sentinels disagree on the master ($master, $port)"
        master=$port
    done
    ok "$g: every sentinel names the same master, one of the group's servers"
    for d in $data; do
        r=$(redis-cli $dopt -p "$d" role | head -1)
        if [ "$d" = "$master" ]; then [ "$r" = master ] || wrong "$g: the master's ROLE is $r"
        else [ "$r" = slave ] || wrong "$g: a replica's ROLE is $r"; fi
    done
    ok "$g: ROLE says master on the master and slave on the replicas"
    for s in $sentinels; do
        [ "$(redis-cli $sopt -p "$s" sentinel replicas kr | flags | grep -cx slave)" -eq 2 ] || wrong "$g: sentinel $s does not know both replicas, up"
        [ "$(redis-cli $sopt -p "$s" sentinel sentinels kr | flags | grep -cx sentinel)" -eq 2 ] || wrong "$g: sentinel $s does not know the other two, up"
    done
    ok "$g: each sentinel knows both replicas and the other two sentinels, none of them down"
}
plain_sentinels=$KR_PLAIN_SENTINELS; tls_sentinels=$KR_TLS_SENTINELS
group plain "$KR_PLAIN_DATA" "$KR_PLAIN_SENTINELS" "" ""
group tls "$KR_TLS_DATA" "$KR_TLS_SENTINELS" "$T" "$T $AUTH"
set -- $plain_sentinels; S0=$1
set -- $tls_sentinels; TS0=$1
[ "$(redis-cli -p "$S0" role | head -1)" = sentinel ] && ok "ROLE on a sentinel says sentinel" || wrong "a sentinel's ROLE"
case "$(redis-cli -p "$S0" hello 3 2>&1 | tr '\n' ' ')" in *mode\ sentinel*) ok "HELLO 3 on a sentinel says mode sentinel" ;; *) wrong "HELLO 3 on a sentinel" ;; esac
case "$(redis-cli -p "$S0" select 1 2>&1)" in *nknown*) ok "SELECT is an unknown command on a sentinel" ;; *) wrong "a sentinel took SELECT" ;; esac
[ -z "$(redis-cli -p "$S0" sentinel get-master-addr-by-name nosuch)" ] && ok "an unknown name is a null" || wrong "an unknown name answered"
case "$(redis-cli $T -p "$TS0" ping 2>&1)" in *NOAUTH*) ok "tls: a sentinel wants a password" ;; *) wrong "tls: a sentinel took an unauthenticated PING" ;; esac
case "$(redis-cli $T -p "$TS0" --user kr_sentinel --pass wrong --no-auth-warning ping 2>&1)" in *WRONGPASS*) ok "tls: a wrong password is WRONGPASS" ;; *) wrong "tls: a wrong password" ;; esac
case "$(redis-cli -p "$TS0" ping 2>&1)" in *PONG*) wrong "tls: a sentinel took plaintext" ;; *) ok "tls: a sentinel refuses plaintext" ;; esac
set -- $(redis-cli $T $AUTH -p "$TS0" sentinel get-master-addr-by-name kr)
case "$(redis-cli $T -p "$2" --user kr_acl --pass kr_acl_pw --no-auth-warning ping 2>&1)" in
    PONG) ok "tls: the master takes the data servers' own user" ;; *) wrong "tls: the master refused kr_acl" ;;
esac
echo "  $n checks"
EOF
    echo "redis.sh: smoke OK against $NAME ($("$RT" exec "$NAME" redis-server --version | sed 's/ sha=.*//'))"
}

case "$cmd" in
    up)
        "$ROOT/tools/gen-test-certs.sh" >/dev/null
        case "$TOPOLOGY" in
            standalone)
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
                    wait_standalone
                    echo "redis.sh: $NAME ready on 127.0.0.1:$PORT (TLS $TLS_PORT, locked $LOCKED_PORT, locked TLS $MTLS_PORT): $("$RT" exec "$NAME" redis-server --version)"
                fi ;;
            cluster)
                if running; then
                    echo "redis.sh: $NAME already running on 127.0.0.1 ports $CLUSTER_PORTS (TLS $CLUSTER_TLS_PORTS)"
                else
                    "$RT" rm -f "$NAME" >/dev/null 2>&1 || true
                    # shellcheck disable=SC2046
                    "$RT" run -d --name "$NAME" $(publish $CLUSTER_PORTS $CLUSTER_TLS_PORTS) \
                        -e KR_PORTS="$CLUSTER_PORTS" -e KR_TLS_PORTS="$CLUSTER_TLS_PORTS" \
                        -v "$ROOT/out/test-certs:/certs:ro" \
                        -v "$ROOT/tests/integration/server:/kr:ro" \
                        --entrypoint /kr/cluster.sh \
                        "$IMAGE" >/dev/null
                    wait_cluster
                    echo "redis.sh: $NAME ready on 127.0.0.1 ports $CLUSTER_PORTS (TLS $CLUSTER_TLS_PORTS): $("$RT" exec "$NAME" redis-server --version)"
                fi ;;
            sentinel)
                if running; then
                    echo "redis.sh: $NAME already running: plain servers $PLAIN_DATA, sentinels $PLAIN_SENTINELS; TLS servers $TLS_DATA, sentinels $TLS_SENTINELS"
                else
                    "$RT" rm -f "$NAME" >/dev/null 2>&1 || true
                    # shellcheck disable=SC2046
                    "$RT" run -d --name "$NAME" $(publish $PLAIN_DATA $PLAIN_SENTINELS $TLS_DATA $TLS_SENTINELS) \
                        -e KR_PLAIN_DATA="$PLAIN_DATA" -e KR_PLAIN_SENTINELS="$PLAIN_SENTINELS" \
                        -e KR_TLS_DATA="$TLS_DATA" -e KR_TLS_SENTINELS="$TLS_SENTINELS" \
                        -v "$ROOT/out/test-certs:/certs:ro" \
                        -v "$ROOT/tests/integration/server:/kr:ro" \
                        --entrypoint /kr/sentinel.sh \
                        "$IMAGE" >/dev/null
                    wait_sentinel
                    echo "redis.sh: $NAME ready: plain servers $PLAIN_DATA, sentinels $PLAIN_SENTINELS; TLS servers $TLS_DATA, sentinels $TLS_SENTINELS: $("$RT" exec "$NAME" redis-server --version)"
                fi ;;
        esac
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
        case "$TOPOLOGY" in
            standalone) exec "$RT" exec -i "$NAME" redis-cli -p 6379 "$@" ;;
            cluster)    exec "$RT" exec -i "$NAME" redis-cli -c -p "${CLUSTER_PORTS%% *}" "$@" ;;
            sentinel)   exec "$RT" exec -i "$NAME" redis-cli -p "${PLAIN_SENTINELS%% *}" "$@" ;;
        esac
        ;;
    logs)
        case "$TOPOLOGY" in
            standalone) exec "$RT" logs "$NAME" ;;
            cluster)    exec "$RT" exec "$NAME" sh -c 'tail -n 40 /run/kr/cluster/create.log /run/kr/cluster/node-*.log' ;;
            sentinel)   exec "$RT" exec "$NAME" sh -c 'tail -n 40 /run/kr/sentinel/*.log' ;;
        esac
        ;;
    smoke)
        case "$TOPOLOGY" in cluster) smoke_cluster; exit 0 ;; sentinel) smoke_sentinel; exit 0 ;; esac
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
        sed -n '2,/^set -eu$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
