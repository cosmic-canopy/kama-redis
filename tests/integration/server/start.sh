#!/bin/sh
# The container's command (tools/redis.sh up). The PKI is mounted read-only from out/test-certs; the server
# reads its copy in /run/kr/certs. The locked server runs in the background, and the main one in the
# foreground, so the container lives as long as it does. redis-server is Valkey's name for its server too.
set -eu
mkdir -p /run/kr/certs
cp /certs/ca.crt /certs/server.crt /certs/server.key /run/kr/certs/
chmod 0600 /run/kr/certs/server.key
redis-server /kr/locked.conf --daemonize yes
exec redis-server /kr/redis.conf
