# Roadmap

Where this is, 2026-10-04: phases 0, 1 and 2 are done. Phase 3 is next: see "Phase 3: where to start" below.
- `tools/redis.sh` runs every server in the matrix with TLS on and one ACL user per authentication case.
  `tools/redis.sh smoke` passes all 16 checks on Redis 6.2.24, 7.2.16, 7.4.11, 8.2.10 and 8.10.2, and on Valkey
  7.2.14, 8.1.10 and 9.1.2.
- The pure layers are in, each checked against upstream by script:
  - `redis::resp` against 593 vectors: hiredis's reading of its own tests, of the spec's examples and of what all
    eight servers send.
  - `redis::cluster` key slots against the cluster specification and against `CLUSTER KEYSLOT` on all eight servers.
  - `RedisUrl` against redis-cli and valkey-cli, asked live.
- The connection is in (phase 2): `Config`, `Connection`, `RedisError`, `Command`, `ServerInfo`, the `Transport` and
  `Dialer` contracts.
  - The unit suite's scripted server plays every server's real handshake replies and Envoy's refusals
    (`tools/gen-server-vectors.sh`).
  - `tools/test-integration.sh` is green on all eight servers, debug and release.
- `tools/test.sh` is green, debug and release, on kama 0.9.530.
- Open gaps: KRD-5 (HIGH), a type that holds a collection of itself through a resource no longer compiles, which
  breaks @kama/postgres 0.2.0's build; KRD-6 (LOW). Neither needs a workaround here.

The model is `@kama/postgres` (`../kama-postgres`). Its decisions carry over unless this file says otherwise, and so
does its discipline:
- expected values come from upstream by script, never typed from memory;
- every compiler gap goes into KAMA_GAPS.md the moment it is hit;
- each phase ends green: `tools/test.sh`, and from phase 2 on, the integration suite on the whole server matrix.

| # | phase | state |
|---|---|---|
| 0 | Scaffold: manifest, agent files, unit program (`tools/test.sh`); `tools/redis.sh` + server config + test PKI for Redis 6.2–8.10 and Valkey 7.2–9.1; smoke; CI | **done** |
| 1 | Pure layers. `redis::resp`: a reader and a writer for every RESP2 and RESP3 type (attributes, push, streamed strings and aggregates, big numbers, verbatim strings), bounded and hostile-input safe, with vectors from the RESP specification and hiredis's reader tests, by script. The `redis://`, `rediss://` and `unix://` URL forms. CRC16 key slots and hash tags, with the cluster specification's vectors | **done** |
| 2 | Connection. `Config` from a URL or settings. TCP and Unix sockets, non-blocking with connect and command deadlines, TCP keepalive. `HELLO 3` with `AUTH` and `SETNAME` in one round trip, RESP2 when asked for (`protocol=2`) or when a proxy refuses `HELLO`, `SELECT`. Errors as values, by their code (`ERR`, `WRONGTYPE`, `NOAUTH`, `NOPERM`, `WRONGPASS`, `MOVED`, `ASK`, `LOADING`, `BUSY`, `READONLY`, …). A `Transport` contract and a scripted fake server for every hostile path. Integration suite on the whole matrix | **done** |
| 3 | Commands. Arguments through a `RedisArg` contract with `type adapter`s (as `PgParam` is); the `cmd"SET ${key} ${value} EX 10"` tag, whose holes are always whole arguments, never spliced into text; replies read into typed values through `Deserializable` (`reply::<T>`, as `column::<T>`). Pipelining. `MULTI`/`EXEC`/`WATCH`. Scripts and functions (`EVALSHA`, falling back to `EVAL` on `NOSCRIPT`). `SCAN` cursors. Blocking commands with their own deadlines | next |
| 4 | Server push. Pub/sub on RESP3 push messages beside commands on the same connection, and on a dedicated connection under RESP2. Sharded pub/sub. Client-side caching (`CLIENT TRACKING` invalidations) | |
| 5 | TLS through `@kama/tls`: `rediss://`, verification of the chain and the host name, client certificates, SNI | |
| 6 | Topologies. Cluster: the slot map from `CLUSTER SHARDS` (`CLUSTER SLOTS` before 7.0), `MOVED` and `ASK`, multi-key commands on one slot, reads from replicas. Sentinel: discovery and failover. A multi-node `tools/redis.sh` topology for both | |
| 7 | Pool (cross-isolate), reconnection, examples, hardening (server restart, failover, bounded memory), docs | |
| — | Publish `@kama/redis` 0.1.0 — only on the maintainer's word | |

## Phase 3: where to start

The bar stays `@kama/postgres`'s: every form honoured or refused, every failure path against the scripted server, the
whole matrix live, debug and release.

- **Before writing anything**, read the matching parts of `@kama/postgres`:
  - `src/query.kama` (`PgParam`) and `src/types/codec.kama`: arguments through a contract with `type adapter`s. Mind
    KPG-38: two files that use the same adapter fail every release build, so keep each adapter's use in one file
    and test release.
  - `src/rows.kama` and `src/decode.kama`: `column::<T>` through `Deserializable`, `@generate` structs included.
  - `src/pipeline.kama` and `src/batch.kama`: a queue of commands written at once and read in order.
  - `src/transaction.kama`.
- **What phase 2 leaves ready:**
  - `Command` holds a command's arguments as whole bulk strings. `RedisArg` and the `cmd"…"` tag build `Command`s,
    and `Command.encode` already writes any number of them into one `resp::Writer`.
  - `Wire.send` reads while a write waits, so a pipeline's replies cannot deadlock its writes.
    `connection_test`'s jammed server proves it.
  - `Connection.call` returns a `resp::Value`. Typed replies read from it.
  - Push messages are set aside (`pendingPushes()`). Phase 4 decides how they are read.
- **To decide early and write down here,** with what the peers do (redis-rs `ToRedisArgs`/`FromRedisValue`, go-redis
  `Cmd` types, redis-py, Lettuce):
  - **Typed replies across protocols.** RESP2 sends a map as a flat array and a double as a bulk string.
    `reply::<T>` reads both forms into the same T, so a `@generate` struct reads from `HGETALL` either way.
  - **Pipelines.** How a pipeline is built and read; what one failed command does to the rest (nothing: each reply
    stands alone); and the deadline, one for the whole pipeline.
  - **Transactions.** `MULTI`/`EXEC`/`WATCH`, `EXECABORT`, and `EXEC`'s null when a watched key changed.
  - **Scripts.** `EVALSHA`, falling back to `EVAL` on `NOSCRIPT`; `FCALL`.
  - **`SCAN` cursors**, as an iterator.
  - **Blocking commands.** A command's own timeout plus `command_timeout`, so `BLPOP key 30` is not cut off at 5 s;
    and `0`, which means forever.
- **Vectors:** typed replies come from the servers' real replies under both protocols (`tools/gen-server-vectors.sh`
  and `gen-resp-vectors.sh` extended), never typed by hand.

## Decided, and why

### The foundations (confirmed by the maintainer, 2026-10-04)

- **Native protocol, not hiredis.**
  - Consumers install nothing, the rule every `@kama` package keeps.
  - The package controls the reader's bounds, pipelining and push messages.
  - It mirrors `@kama/postgres` and libpq, and it is what redis-rs, go-redis and Lettuce do.
- **One package for Redis and Valkey, named for Redis.**
  - The protocol and nearly every command are shared, and "redis" is the name users search for. Valkey is named
    everywhere the package says what it supports.
  - Both run in one test matrix. Valkey forked from Redis 7.2, and the forks have diverged since (Redis 8 adds
    commands, Valkey 8 and 9 add others). Where they differ, the client follows the server it is talking to,
    identified by `HELLO`. Valkey 7.2 names itself `redis` there, and it is Redis 7.2's code (phase 2, below).
  - The floor is Redis 6.2 and Valkey 7.2: the oldest servers with RESP3, ACL users and channel permissions that
    are still widely deployed.
- **RESP3 by default.**
  - `HELLO 3` gives typed replies (maps, sets, doubles, booleans, nulls) and push messages on the same connection.
  - go-redis v9 and Lettuce 6 default to it as well.
  - RESP2 stays fully supported, because proxies such as twemproxy and older Envoy speak only RESP2.
- **The reference implementation is the one the server ships.** For PostgreSQL that was libpq, and psql beside it.
  For Redis it is hiredis, and redis-cli beside it, from the server's own repository:
  - the RESP reader follows hiredis (phase 1, below);
  - URLs follow redis-cli, and connection behaviour does too;
  - `unix://` has no reference, because Redis defines none (phase 1, below).

  Behaviour that no reference fixes, such as URL options for timeouts, is decided here and written down.
- **Errors carry the server's code**, as a value a caller can match, beside the server's own message. They are
  never parsed for prose.
- **Typed access goes through `Deserializable`**, as in `@kama/postgres`. So a `@generate` struct reads from a
  RESP3 map (`HGETALL`, `XINFO`), and `Uuid` and `Timestamp` need no special case.

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
  - `maxDepth`: 1024, as in hiredis. A reply is walked recursively (dropped, compared, written, deserialized), so
    the depth must fit the stack of whatever isolate walks it. It was 128 while an isolate had the OS's default
    thread stack, on which a 1000-deep compare overflowed (KRD-2). Since kama 0.9.529 an isolate has the main
    thread's 8 MiB, and resp_test.kama walks a 1024-deep reply inside one in a debug build.
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

### Phase 2

What the peer clients do was read from their current source, not remembered: go-redis v9.22.0 (`options.go`,
`redis.go`), redis-py 8.1.0 (`connection.py`, `_defaults.py`), redis-rs 1.7.1 (`connection.rs`), Lettuce 7.8.0
(`RedisURI`, `RedisHandshake`, `SocketOptions`), hiredis and redis-cli (`net.c`, `redis-cli.c`), the servers
(`networking.c`, `acl.c`), Envoy's redis proxy (`command_splitter_impl.cc`, v1.32 to v1.39) and twemproxy 0.5.0
(`nc_redis.c`).

- **The server is identified by `HELLO`, as it states itself.**
  - Redis says `server: redis`. Valkey 8.0 and later say `server: valkey`, with their real version.
  - Valkey 7.2 says `server: redis` with its own version (7.2.14 in the phase 1 vectors). It forked from Redis 7.2.4,
    so following "the server it is talking to" means following Redis 7.2 there.
  - Valkey 8 and 9 with `extended-redis-compatibility yes` say `redis` and `7.2.4`, which is what that setting asks
    for.
  - `INFO` is never used to identify the server.
- **URL options.** Names are snake_case, as go-redis and redis-py name theirs. An option this package does not know
  is refused when the URL is read, as go-redis refuses one. redis-rs, Lettuce and ioredis ignore an unknown option,
  and redis-py fails only at the first connect.

  | option | value | default | the peers |
  |---|---|---|---|
  | `protocol` | `2` or `3` | unset: RESP3, or the RESP2 path when `HELLO` is refused | go-redis and redis-py `protocol`; redis-rs `protocol`, also as `resp2`/`resp3` |
  | `connect_timeout` | seconds, a decimal number; `0` is no limit | 5 | go-redis `dial_timeout` 5 s; redis-py 8 `socket_connect_timeout` 5 s; Lettuce 10 s; redis-cli `-t`, none by default |
  | `command_timeout` | seconds, a decimal number; `0` is no limit | 5 | go-redis `read_timeout` 5 s (3 s before v9.22); redis-py 8 `socket_timeout` 5 s (none before 8.0); Lettuce `timeout` 60 s |
  | `client_name` | bytes from `!` to `~` | none | go-redis and redis-py `client_name`; Lettuce `clientName` |
  | `keepalive` | whole seconds; `0` is off | 15 | hiredis's `redisKeepAlive(interval)` and redis-cli's constant 15; go-redis and redis-py 8: on, 30 s |

  - A value with a unit, a negative value, an empty one or a malformed one is refused, with words that show the
    form (`connect_timeout=2.5`).
  - `db` stays where `RedisUrl` reads it: the path on TCP, `?db=` on `unix://`.
  - There are no environment variables. No Redis client library reads any.
- **Timeouts.**
  - `connect_timeout` bounds each address: its TCP connect and, once connected, the handshake, as libpq bounds
    each. Resolving a name blocks and is not bounded, as in libpq and hiredis.
  - `command_timeout` is one deadline per call, from the first byte written to the last byte of the reply. When it
    passes, the connection closes: Redis has no way to cancel a command, and a late reply cannot be told from the
    next one. go-redis and redis-py close the connection too.
  - Blocking commands get deadlines of their own in phase 3. Until then a `BLPOP` longer than `command_timeout`
    needs it raised.
- **Keepalive.** One number, as hiredis takes it: idle N seconds, probes every N/3, and 3 probes before the connection
  is dropped. redis-cli always uses 15, which is the default here. TCP_NODELAY is always on, as in hiredis,
  go-redis and Lettuce.
- **The handshake is one round trip.** One write carries:
  - `HELLO <2|3> [AUTH <user> <password>] [SETNAME <name>]`, with the user `default` when only a password is given;
  - `SELECT <db>`, when a database is given;
  - `CLIENT SETINFO LIB-NAME kama-redis` and `CLIENT SETINFO LIB-VER <version>`, unless identity is off.

  Then `HELLO`'s reply decides the outcome:
  - **A map** (a flat array under RESP2) is the server's `ServerInfo`. Its `proto` must be the one asked for.
    - A `SELECT` error fails the connect.
    - A `CLIENT SETINFO` error does not: the command's own documentation tells clients to ignore it, because a server
      before 7.2 does not have it.
  - **`WRONGPASS` or `NOPERM`** fails the connect with that error. So does **`NOAUTH`** to a `HELLO` that carried
    no `AUTH`: the server wants a password and none was given.
  - **`NOAUTH` to a `HELLO` that carried `AUTH`** means the peer did not read `HELLO`'s `AUTH`. A server never
    answers that way. Envoy 1.32 and 1.37 to 1.39 do, when they require a password, because they check it before
    they look at `HELLO`. With `protocol` unset, the connection takes the RESP2 path, which sends `AUTH` alone.
  - **Any other error reply, with `protocol` unset,** means `HELLO` is not supported. The connection takes the
    RESP2 path. That error is told by its code, never by its words:
    - Redis before 6 says `ERR unknown command`;
    - Envoy up to 1.32 says `unsupported command`;
    - Envoy 1.33 to 1.36 says `ERR unknown command`;
    - Envoy 1.37 to 1.39 says `NOPROTO` to `HELLO 3`, and `ERR` to `HELLO` with `AUTH` or `SETNAME`.

    go-redis falls back on every error, which hides a wrong password and sends it twice. Lettuce looks for the word
    "unknown" in the message. redis-py and redis-rs do not fall back at all.
  - **Any other error reply, with `protocol=3`,** fails the connect.
  - **A hangup during `HELLO`** fails the connect. Its note says that a proxy which does not know `HELLO` (twemproxy)
    closes the connection, and that `protocol=2` connects to it.

  The replies after a failed `HELLO` are read and dropped.
- **The RESP2 path** is taken with `protocol=2`, and after the fallback above. It is redis-py's and redis-rs's
  handshake for protocol 2: `AUTH [user] password`, `CLIENT SETNAME`, `SELECT`, each only when needed, in one write.
  Each reply must be OK.
  - No `HELLO` is sent, so the server is not identified.
  - No `CLIENT SETINFO` is sent: twemproxy closes the connection on any `CLIENT` command.
  - A user and a password always send the two-argument `AUTH`. redis-py and redis-rs retry the one-argument form
    for servers before 6.0, which are below the floor.
- **Identity.** lib-name is `kama-redis` and lib-ver is the package version, as go-redis, redis-py, redis-rs and
  Lettuce all identify themselves. `Config.setIdentity(on: false)` turns it off. There is no URL option for it.
- **Closing** shuts the transport down. It sends no `QUIT`, which has been deprecated since 7.2.
- **`RedisError`** has these variants:
  - `Config`;
  - `Io` (a server that hung up is `UnexpectedEof`, in hiredis's words "Server closed the connection");
  - `Timeout`;
  - `Protocol` (the bytes broke RESP);
  - `Unexpected` (a well-formed reply the exchange does not allow, such as a `HELLO` reply that is not a map);
  - `Server`;
  - `Connect`;
  - `Closed`;
  - `Usage`.

  Phase 3 adds `Value`, and phase 5 adds `Tls`.
  - Only a failed TCP or socket connect moves on to the next address a name resolves to. Once connected, the
    handshake's outcome is final, so a wrong password is a `Server` error, not one attempt among several.
  - `Connect` keeps every address tried, each in redis-cli's words without the product's name, which is not known
    before `HELLO`: `Could not connect to 127.0.0.1:6379: Connection refused`.
- **A server error's code** is read as the server itself reads it for its error statistics (`afterErrorReply` in
  networking.c). It is the text before the first space, when that space falls within the line's first 32 bytes,
  the `-` included; otherwise the server counts the error as `ERR`, and so does this client.
  - `ServerCode` has a variant for every code the matrix's servers send (the generator reads them from each server's
    source), and `Other` for the rest: a module's or a script's codes, or a proxy's.
  - The code is a value to match, beside the server's message. The message is never parsed.
  - A byte that is not UTF-8 is shown as `\xNN`, as redis-cli shows it.
  - go-redis types a dozen codes by prefix, redis-py fifteen, and redis-rs fourteen, with the rest as an extension
    code. This package names them all.
- **Push messages** (RESP3's `>`) that arrive in place of a reply are set aside in arrival order, and never taken for
  the reply. Phase 4 decides how they are read.
- **TLS** (`rediss://`, `valkeys://`) is refused until phase 5, never connected in plaintext.
- **What building it settled:**
  - A connect attempt holds the `IoError` that ended it, not a `RedisError`. Only I/O ends an attempt, and this also
    keeps `RedisError` clear of KRD-5.
  - The library's version for `CLIENT SETINFO` is `redis::libraryVersion()`, which `tools/test.sh` checks against
    kama.json's. go-redis has `redis.Version()` too.
  - `Command` is phase 2's whole command surface: a name and whole arguments. Phase 3 builds on it, and adds no
    second way.
  - The scripted server (`tests/unit/src/fake_server.kama`) is an in-memory `Transport`, as postgres's is. It reads
    each command with `resp::Reader`, and plays only bytes from the generated vectors. Its steps:
    - `Expect`, `Any` and `Late` answer the next command;
    - `Send` sends bytes of the server's own accord, as soon as the script reaches it;
    - `Silent` leaves the next command unanswered;
    - `Close` reads the next command, then closes, as twemproxy does;
    - `Hangup` closes as soon as the script reaches it.
  - The error codes come from the servers' own binaries: each string literal `-CODE message`, plus MOVED and ASK
    from cluster.c's format. The source tarballs would have needed eight more pins, and the binaries are exactly
    what the matrix runs.
