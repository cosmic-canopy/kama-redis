#!/bin/sh
# The sentinel topology's command (tools/redis.sh up --topology sentinel): two groups in one container, each a master,
# two replicas and three sentinels monitoring it as "kr". tools/redis.sh passes the ports and publishes each one 1:1 on
# the host's 127.0.0.1, and every server and sentinel announces 127.0.0.1, so the address a sentinel gives
# (GET-MASTER-ADDR-BY-NAME, SENTINEL REPLICAS, +switch-master) is one the host can reach too.
#
# A sentinel names the port it monitors, so a group is plaintext or TLS throughout:
#   - plain: plaintext only; the sentinels take no password.
#   - tls:   TLS only (port 0), replication and the sentinels' links over TLS (tls-replication yes); the sentinels'
#            default user is off, so a client logs in to them as kr_sentinel, and they log in to each other as it
#            (sentinel sentinel-user). The data servers keep the standalone server's users, so a client's
#            credentials for the data servers and for the sentinels differ, as a deployment's do.
# Each server and sentinel runs in a loop, as the standalone server does (start.sh). A test fails a master over with
# SENTINEL FAILOVER, or by holding it past down-after-milliseconds with DEBUG SLEEP.
set -eu
: "${KR_PLAIN_DATA:?}" "${KR_PLAIN_SENTINELS:?}" "${KR_TLS_DATA:?}" "${KR_TLS_SENTINELS:?}"
mkdir -p /run/kr/certs /run/kr/sentinel
cp /certs/ca.crt /certs/server.crt /certs/server.key /certs/client.crt /certs/client.key /run/kr/certs/
chmod 0600 /run/kr/certs/server.key /run/kr/certs/client.key
rm -f /run/kr/stop

debug=""
set -- $(redis-server --version | sed -n 's/^\([A-Za-z]*\) *server v=\([0-9]*\)\..*/\1 \2/p')
case "${1:-}" in
    Redis) if [ "${2:-0}" -ge 7 ]; then debug="enable-debug-command yes"; fi ;;
    *)     debug="enable-debug-command yes" ;;
esac

# The links a server or sentinel opens (replication, the sentinels' own) present the test client certificate, since
# the server's is for serverAuth only.
TLS_FILES="tls-cert-file /run/kr/certs/server.crt
tls-key-file /run/kr/certs/server.key
tls-ca-cert-file /run/kr/certs/ca.crt
tls-client-cert-file /run/kr/certs/client.crt
tls-client-key-file /run/kr/certs/client.key
tls-auth-clients optional"

# data <port> <master-port|-> <tls: yes|no>
data() {
    if [ "$3" = yes ]; then
        printf 'port 0\ntls-port %s\n%s\ntls-replication yes\n' "$1" "$TLS_FILES"
    else
        printf 'port %s\n' "$1"
    fi
    cat <<EOF
bind 0.0.0.0
protected-mode no
dir /run/kr/sentinel
logfile /run/kr/sentinel/data-$1.log
save ""
appendonly no
replica-announce-ip 127.0.0.1
$debug
user default on nopass ~* &* +@all
user kr_acl on >kr_acl_pw ~* &* +@all
EOF
    if [ "$2" != - ]; then printf 'replicaof 127.0.0.1 %s\n' "$2"; fi
}

# watcher <port> <master-port> <tls: yes|no>
watcher() {
    if [ "$3" = yes ]; then
        printf 'port 0\ntls-port %s\n%s\ntls-replication yes\n' "$1" "$TLS_FILES"
        printf 'user default off\nuser kr_sentinel on >kr_sentinel_pw allchannels +@all\n'
        printf 'sentinel sentinel-user kr_sentinel\nsentinel sentinel-pass kr_sentinel_pw\n'
    else
        printf 'port %s\n' "$1"
    fi
    cat <<EOF
bind 0.0.0.0
protected-mode no
dir /run/kr/sentinel
logfile /run/kr/sentinel/sentinel-$1.log
sentinel announce-ip 127.0.0.1
sentinel monitor kr 127.0.0.1 $2 2
sentinel down-after-milliseconds kr 2000
sentinel failover-timeout kr 6000
sentinel parallel-syncs kr 1
EOF
}

# Each server's and sentinel's configuration is written once: a sentinel rewrites its own file as it learns, so a
# restarted one keeps what it knew.
write_group() {  # write_group <data ports, the master's first> <tls>
    tls=$2
    set -- $1
    master=$1
    for p in "$@"; do
        role=$master
        [ "$p" = "$master" ] && role=-
        [ -e "/run/kr/sentinel/data-$p.conf" ] || data "$p" "$role" "$tls" > "/run/kr/sentinel/data-$p.conf"
    done
}
write_sentinels() {  # write_sentinels <sentinel ports> <master port> <tls>
    for s in $1; do
        [ -e "/run/kr/sentinel/sentinel-$s.conf" ] || watcher "$s" "$2" "$3" > "/run/kr/sentinel/sentinel-$s.conf"
    done
}
write_group "$KR_PLAIN_DATA" no
write_sentinels "$KR_PLAIN_SENTINELS" "${KR_PLAIN_DATA%% *}" no
write_group "$KR_TLS_DATA" yes
write_sentinels "$KR_TLS_SENTINELS" "${KR_TLS_DATA%% *}" yes

# loop <config> [--sentinel]: one server or sentinel, made again whenever it stops, until the container is stopped.
loop() {
    ( while [ ! -e /run/kr/stop ]; do
          redis-server "$@" || true
          [ -e /run/kr/stop ] || sleep 0.5
      done ) &
}
trap 'touch /run/kr/stop
      for p in $KR_PLAIN_DATA $KR_PLAIN_SENTINELS; do redis-cli -p "$p" shutdown nosave >/dev/null 2>&1 || true; done
      for p in $KR_TLS_DATA; do redis-cli --tls --cacert /run/kr/certs/ca.crt -p "$p" shutdown nosave >/dev/null 2>&1 || true; done
      for p in $KR_TLS_SENTINELS; do redis-cli --tls --cacert /run/kr/certs/ca.crt --user kr_sentinel --pass kr_sentinel_pw \
          --no-auth-warning -p "$p" shutdown nosave >/dev/null 2>&1 || true; done
      exit 0' TERM INT
for p in $KR_PLAIN_DATA $KR_TLS_DATA; do loop "/run/kr/sentinel/data-$p.conf"; done
for s in $KR_PLAIN_SENTINELS $KR_TLS_SENTINELS; do loop "/run/kr/sentinel/sentinel-$s.conf" --sentinel; done
while :; do sleep 3600 & wait $! || true; done
