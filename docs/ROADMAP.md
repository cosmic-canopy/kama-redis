# Roadmap

Where this is, 2026-10-03: phases 0 and 1 are done. Phase 2 is next.
- `tools/redis.sh` runs every server in the matrix with TLS on and one ACL user per authentication case.
  `tools/redis.sh smoke` passes all 16 checks on Redis 6.2.24, 7.2.16, 7.4.11, 8.2.10 and 8.10.2, and on Valkey
  7.2.14, 8.1.10 and 9.1.2.
- The pure layers are in, each checked against upstream by script:
  - `redis::resp` against 593 vectors: hiredis's reading of its own tests, of the spec's examples and of what all
    eight servers send.
  - `redis::cluster` key slots against the cluster specification and against `CLUSTER KEYSLOT` on all eight servers.
  - `RedisUrl` against redis-cli and valkey-cli, asked live.
- `tools/test.sh` is green, debug and release, on kama 0.9.523.

The model is `@kama/postgres` (`../kama-postgres`). Its decisions carry over unless this file says otherwise, and so
does its discipline:
- expected values come from upstream by script, never typed from memory;
- every compiler gap goes into KAMA_GAPS.md the moment it is hit;
- each phase ends green: `tools/test.sh`, and from phase 2 on, the integration suite on the whole server matrix.

| # | phase | state |
|---|---|---|
| 0 | Scaffold: manifest, agent files, unit program (`tools/test.sh`); `tools/redis.sh` + server config + test PKI for Redis 6.2–8.10 and Valkey 7.2–9.1; smoke; CI | **done** |
| 1 | Pure layers. `redis::resp`: a reader and a writer for every RESP2 and RESP3 type (attributes, push, streamed strings and aggregates, big numbers, verbatim strings), bounded and hostile-input safe, with vectors from the RESP specification and hiredis's reader tests, by script. The `redis://`, `rediss://` and `unix://` URL forms. CRC16 key slots and hash tags, with the cluster specification's vectors | **done** |
| 2 | Connection. `Config` from a URL or settings. TCP and Unix sockets, non-blocking with connect and command deadlines, TCP keepalive. `HELLO 3` with `AUTH` and `SETNAME` in one round trip, RESP2 when asked for (`protocol=2`) or when a proxy refuses `HELLO`, `SELECT`. Errors as values, by their code (`ERR`, `WRONGTYPE`, `NOAUTH`, `NOPERM`, `WRONGPASS`, `MOVED`, `ASK`, `LOADING`, `BUSY`, `READONLY`, …). A `Transport` contract and a scripted fake server for every hostile path. Integration suite on the whole matrix | next |
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
  - `unix://` has no reference, because Redis defines none: see "Decided", phase 1.

  Behaviour that no reference fixes, such as URL options for timeouts, is decided here and written down.
- **Errors carry the server's code**, as a value a caller can match, beside the server's own message. They are
  never parsed for prose.
- **Typed access goes through `Deserializable`**, as in `@kama/postgres`. So a `@generate` struct reads from a
  RESP3 map (`HGETALL`, `XINFO`), and `Uuid` and `Timestamp` need no special case.

## Decided, and why

### Phase 1

- **The RESP reader's reference is hiredis v1.4.1.** That is the reader redis-cli and the server's own tests use.
  - This reader accepts what hiredis accepts and refuses what it refuses, and each error's message is hiredis's own
    errstr.
  - `tools/resp-dump.c` compiles hiredis from its pinned sources, so every expectation is hiredis's actual reading.
- **Where it goes past hiredis**, each difference is written in `tools/gen-resp-vectors.sh` with its reason:
  - RESP3's blob errors are read.
  - Streamed strings (`$?`, `;N`, `;0`) are read, and so are streamed aggregates (`*?`, `%?` and `~?`, ending in
    `.`).
  - An attribute attaches to the value it describes (`Value::Attributed`). hiredis returns it as a reply of its
    own, and loses its place inside an aggregate.
  - The CRLF after a payload is checked.
  - Nothing is allocated from a declared count.
  - `#\0` is not a bool. hiredis's `strchr` finds the terminating NUL and reads it as false.
- **Limits** (`resp::Limits`):
  - `maxBulk`: 512 MiB, the server's own default.
  - `maxElements`: 2³²−1, as in hiredis.
  - `maxReplyBytes`: 1 GiB, counted as wire bytes plus `sizeof(Value)` per value, so a flood of tiny elements is
    bounded by what it costs.
  - `maxDepth`: **128, not hiredis's 1024**. A reply is walked recursively (dropped, compared, written,
    deserialized). An isolate gets the OS default thread stack, 512 KiB on macOS and 128 KiB with musl (KRD-2). A
    recursive compare of a 1000-deep reply overflows a macOS isolate in a debug build. Drop alone survives 4000.
    hiredis's own depth cases run at 1024 on the main thread.
- **Payloads are bytes.** A RESP string is binary, and a kama `string` must be UTF-8. `Value::Error` holds both
  `-` and `!`, and the writer picks `!` when the text has a line break.
- **The reader is incremental, and phase 2 reads the socket straight into it** (`spare`/`commit`).
  - A line is searched once.
  - A payload leaves the buffer as it arrives.
  - Open aggregates are plain frames over one value stack.
  - The first error is final.
- **URLs: the same reading as the reference, or a clear refusal.**
  - `redis://` and `rediss://` mean what they mean to redis-cli 8.10, and `valkey://` and `valkeys://` what they
    mean to valkey-cli 9.1. Each was asked live, URL by URL.
  - Where a CLI reads a URL into something other than what it says, the URL is refused, with words that say how
    to write it: `atoi` on a port or database, the first `@` ending the password past the host, `user:@` dropping
    the user.
  - valkey-cli still sends an empty user or password, as redis-cli did before 8.10. This package follows 8.10.
- **`unix://` is this package's own**, because Redis defines none: `unix://[user[:password]@]/path?db=N`, the form
  redis-py and go-redis both document.
  - A host, which both libraries silently drop, is refused, and so is redis-py's `?password=`.
  - Being strict means that if Redis ever defines its own form, adapting is accepting more, never changing what an
    accepted URL means.
- **The query is read and kept, in order, but not interpreted**: phase 2's `Config` decides which keys it honours.
  A duplicate key, `password`, `user` and, on TCP, `db` are refused at parse.
- **Modules:** `redis::resp` and `redis::cluster` are public, and `RedisUrl` is in the root module beside the
  coming `Config`.

- **One package for Redis and Valkey, named for Redis.** The protocol and nearly every command are shared, and
  "redis" is the name users search for. Valkey is named everywhere the package says what it supports.
