# Roadmap

Where this is, 2026-10-02: phase 0 is done. The scaffold builds and its (empty) unit program runs, debug and
release. `tools/redis.sh` runs every server in the matrix with TLS on and one ACL user per authentication case,
and `tools/redis.sh smoke` passes all 16 checks on Redis 6.2.24, 7.2.16, 7.4.11, 8.2.10 and 8.10.2, and Valkey
7.2.14, 8.1.10 and 9.1.2. Phase 1 is next.

The model is `@kama/postgres` (`../kama-postgres`). Its decisions carry over unless this file says otherwise, and so
does its discipline:
- expected values come from upstream by script, never typed from memory;
- every compiler gap goes into KAMA_GAPS.md the moment it is hit;
- each phase ends green: `tools/test.sh`, and from phase 2 on, the integration suite on the whole server matrix.

| # | phase | state |
|---|---|---|
| 0 | Scaffold: manifest, agent files, unit program (`tools/test.sh`); `tools/redis.sh` + server config + test PKI for Redis 6.2–8.10 and Valkey 7.2–9.1; smoke; CI | **done** |
| 1 | Pure layers. `redis::resp`: a reader and a writer for every RESP2 and RESP3 type (attributes, push, streamed strings and aggregates, big numbers, verbatim strings), bounded and hostile-input safe, with vectors from the RESP specification and hiredis's reader tests, by script. The `redis://`, `rediss://` and `unix://` URL forms. CRC16 key slots and hash tags, with the cluster specification's vectors | next |
| 2 | Connection. `Config` from a URL or settings. TCP and Unix sockets, non-blocking with connect and command deadlines, TCP keepalive. `HELLO 3` with `AUTH` and `SETNAME` in one round trip, RESP2 when asked for (`protocol=2`) or when a proxy refuses `HELLO`, `SELECT`. Errors as values, by their code (`ERR`, `WRONGTYPE`, `NOAUTH`, `NOPERM`, `WRONGPASS`, `MOVED`, `ASK`, `LOADING`, `BUSY`, `READONLY`, …). A `Transport` contract and a scripted fake server for every hostile path. Integration suite on the whole matrix | |
| 3 | Commands. Arguments through a `RedisArg` contract with `type adapter`s (as `PgParam` is); the `cmd"SET ${key} ${value} EX 10"` tag, whose holes are always whole arguments, never spliced into text; replies read into typed values through `Deserializable` (`reply::<T>`, as `column::<T>`). Pipelining. `MULTI`/`EXEC`/`WATCH`. Scripts and functions (`EVALSHA`, falling back to `EVAL` on `NOSCRIPT`). `SCAN` cursors. Blocking commands with their own deadlines | |
| 4 | Server push. Pub/sub on RESP3 push messages beside commands on the same connection, and on a dedicated connection under RESP2. Sharded pub/sub. Client-side caching (`CLIENT TRACKING` invalidations) | |
| 5 | TLS through `@kama/tls`: `rediss://`, verification of the chain and the host name, client certificates, SNI | |
| 6 | Topologies. Cluster: the slot map from `CLUSTER SHARDS` (`CLUSTER SLOTS` before 7.0), `MOVED` and `ASK`, multi-key commands on one slot, reads from replicas. Sentinel: discovery and failover. A multi-node `tools/redis.sh` topology for both | |
| 7 | Pool (cross-isolate), reconnection, examples, hardening (server restart, failover, bounded memory), docs | |
| — | Publish `@kama/redis` 0.1.0 — only on the maintainer's word | |

## Proposed, for the maintainer to confirm

These are the scaffold's working assumptions. Each is cheap to change now and expensive after phase 2.

- **Native protocol, not hiredis.** Consumers install nothing, the rule every `@kama` package keeps, and the package
  controls the reader's bounds, pipelining and push messages. This mirrors `@kama/postgres` and libpq.
- **Redis and Valkey both, in one matrix.** They speak the same protocol. Valkey forked from Redis 7.2, and the
  forks have diverged since (Redis 8 adds commands, Valkey 8 and 9 add others). Where they differ, the client
  follows the server it is talking to. The floor is Redis 6.2 and Valkey 7.2: the oldest servers with RESP3, ACL
  users and channel permissions that are still widely deployed.
- **RESP3 by default.** `HELLO 3` gives typed replies (maps, sets, doubles, booleans, nulls) and push messages on the
  same connection. RESP2 stays fully supported, because proxies such as twemproxy and older Envoy speak only RESP2.
- **The reference implementation is the one the server ships.** For PostgreSQL that was libpq, and psql beside
  it. For Redis it is hiredis, and redis-cli beside it, from the server's own repository:
  - the RESP reader and its edge cases follow hiredis's, with its reader tests as vectors;
  - `redis://` and `rediss://` URLs mean what they mean to redis-cli, asked live in the container, as libpq was
    asked;
  - `unix://` follows redis-py and go-redis, which agree on it, since redis-cli has no such form.

  Behaviour that no reference fixes, such as URL options for timeouts, is decided here and written down.
- **Errors carry the server's code**, as a value a caller can match, beside the server's own message. They are
  never parsed for prose.
- **Typed access goes through `Deserializable`**, as in `@kama/postgres`. So a `@generate` struct reads from a
  RESP3 map (`HGETALL`, `XINFO`), and `Uuid` and `Timestamp` need no special case.

## Decided, and why

- **One package for Redis and Valkey, named for Redis.** The protocol and nearly every command are shared, and
  "redis" is the name users search for. Valkey is named everywhere the package says what it supports.
