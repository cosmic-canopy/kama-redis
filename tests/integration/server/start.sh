#!/bin/sh
# The container's command (tools/redis.sh up). The PKI is mounted read-only from out/test-certs; the servers
# read their copy in /run/kr/certs. The locked server runs in the background. The main one runs in a loop, so a test
# can stop it (SHUTDOWN NOSAVE, from a connection) and watch a client ride its restart (docs/ROADMAP.md, "Phase 7a");
# a TERM to the container ends the loop, and the server with it. redis-server is Valkey's name for its server too.
set -eu
mkdir -p /run/kr/certs
cp /certs/ca.crt /certs/server.crt /certs/server.key /run/kr/certs/
chmod 0600 /run/kr/certs/server.key
# A client certificate logs in as the ACL user its CN names (tls-auth-clients-user) on the servers that have the
# setting, Redis 8.6 and Valkey 9.0 and later. A server without it is never given it: Redis 8 passes a setting it does
# not know to its modules and fails only after daemonizing. Valkey 7.2 names itself "Server".
by_cert=""
set -- $(redis-server --version | sed -n 's/^\([A-Za-z]*\) *server v=\([0-9]*\)\.\([0-9]*\).*/\1 \2 \3/p')
case "${1:-}" in
    Redis)  if [ "$2" -gt 8 ] || { [ "$2" -eq 8 ] && [ "$3" -ge 6 ]; }; then by_cert="--tls-auth-clients-user CN"; fi ;;
    Valkey) if [ "$2" -ge 9 ]; then by_cert="--tls-auth-clients-user CN"; fi ;;
esac
redis-server /kr/locked.conf --daemonize yes $by_cert
stopping=0
pid=""
trap 'stopping=1; [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null' TERM INT
while [ "$stopping" = 0 ]; do
    redis-server /kr/redis.conf &
    pid=$!
    wait "$pid" || true
    pid=""
    # A moment down, as a real restart has: the port refuses until the server is back.
    [ "$stopping" = 0 ] && sleep 0.5
done
