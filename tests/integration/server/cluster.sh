#!/bin/sh
# The cluster topology's command (tools/redis.sh up --topology cluster): six nodes in one container, three primaries
# with a replica each. tools/redis.sh passes the ports and publishes each one 1:1 on the host's 127.0.0.1, and every
# node announces 127.0.0.1, so the address a node names (CLUSTER SLOTS, MOVED, ASK) is one the host can reach too.
#
# Each node takes plaintext on its port and TLS on its TLS port. The cluster bus is TLS (tls-cluster yes), so every
# server, 6.2 included, gives a plaintext client the plaintext port and a TLS client the TLS port: 6.2 and 7.0 by the
# plaintext port each node announces beside its TLS one (pport, cluster.c's deriveAnnouncedPorts), 7.2 and later by
# the asking client's own connection. Each node runs in a loop, as the standalone server does (start.sh), so a test can
# SHUTDOWN NOSAVE one and watch the cluster carry on; it is back, empty, half a second later, and rejoins from its
# nodes.conf. The cluster is created once, over the TLS ports, since a CLUSTER MEET's bus port is the given port's.
set -eu
: "${KR_PORTS:?}" "${KR_TLS_PORTS:?}"
mkdir -p /run/kr/certs /run/kr/cluster
cp /certs/ca.crt /certs/server.crt /certs/server.key /certs/client.crt /certs/client.key /run/kr/certs/
chmod 0600 /run/kr/certs/server.key /run/kr/certs/client.key
rm -f /run/kr/stop

# DEBUG (DEBUG SLEEP holds a node past cluster-node-timeout, which is how a test fails one over) is off by default
# from 7.0; 6.2 has no setting and refuses one it does not know. Valkey 7.2 names itself "Server".
debug=""
set -- $(redis-server --version | sed -n 's/^\([A-Za-z]*\) *server v=\([0-9]*\)\..*/\1 \2/p')
case "${1:-}" in
    Redis) if [ "${2:-0}" -ge 7 ]; then debug="enable-debug-command yes"; fi ;;
    *)     debug="enable-debug-command yes" ;;
esac

# conf <port> <tls-port>: one node's configuration. A node's links to the others (the bus, replication) present the
# test client certificate, since the server's is for serverAuth only. The ACL users are the standalone server's, so a
# test can pick its authentication case on a cluster too.
conf() {
    cat <<EOF
port $1
tls-port $2
bind 0.0.0.0
protected-mode no
tls-cert-file /run/kr/certs/server.crt
tls-key-file /run/kr/certs/server.key
tls-ca-cert-file /run/kr/certs/ca.crt
tls-client-cert-file /run/kr/certs/client.crt
tls-client-key-file /run/kr/certs/client.key
tls-auth-clients optional
tls-cluster yes
tls-replication yes
cluster-enabled yes
cluster-config-file /run/kr/cluster/nodes-$1.conf
cluster-node-timeout 2000
cluster-announce-ip 127.0.0.1
dir /run/kr/cluster
logfile /run/kr/cluster/node-$1.log
save ""
appendonly no
$debug
user default on nopass ~* &* +@all
user kr_acl on >kr_acl_pw ~* &* +@all
user kr_ro on >kr_ro_pw ~* &* -@all +@read +@connection
EOF
}

set -- $KR_TLS_PORTS
for p in $KR_PORTS; do
    conf "$p" "$1" > "/run/kr/cluster/node-$p.conf"
    shift
done

# A TERM to the container ends every loop, then every node.
trap 'touch /run/kr/stop; for p in $KR_PORTS; do redis-cli -p "$p" shutdown nosave >/dev/null 2>&1 || true; done; exit 0' TERM INT
for p in $KR_PORTS; do
    ( while [ ! -e /run/kr/stop ]; do
          redis-server "/run/kr/cluster/node-$p.conf" || true
          [ -e /run/kr/stop ] || sleep 0.5
      done ) &
done

for p in $KR_PORTS; do
    until redis-cli -p "$p" ping >/dev/null 2>&1; do sleep 0.1; done
done
if [ ! -e /run/kr/cluster/created ]; then
    addrs=""
    for t in $KR_TLS_PORTS; do addrs="$addrs 127.0.0.1:$t"; done
    redis-cli --tls --cacert /run/kr/certs/ca.crt --cluster create $addrs --cluster-replicas 1 --cluster-yes \
        > /run/kr/cluster/create.log 2>&1
    touch /run/kr/cluster/created
fi
while :; do sleep 3600 & wait $! || true; done
