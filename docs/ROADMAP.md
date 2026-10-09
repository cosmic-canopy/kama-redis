# Roadmap

Where this is, 2026-10-08: phases 0, 1 and 2 are done, and phase 3 has started. "Phase 3: where to start" below is
its session plan, and step 3 is next.
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
- `tools/test.sh` is green, debug and release, on kama 0.9.542 (CI's pin) and on cstar's 0.9.558, and CI is green on
  every server.
- Open gaps here: KRD-7 (MED), filed in phase 3's step 0b: an adapter over a std type cannot name `Command`. KRD-5
  and KRD-6 are fixed (0.9.531, 0.9.533). @kama/postgres's KPG-38 is fixed in 0.9.543, but no tagged release has it,
  and CI stays on `v0.9.542` until one does.

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
whole matrix live, debug and release. The plan was drawn up on 2026-10-08 from primary sources: redis-rs 1.x, go-redis
v9, redis-py 8 and Lettuce 7 source; the redis.io and valkey.io command pages; postgres's `src/query.kama` (the
`PgParam` contract, its adapters, the `pg"…"` tag) and `src/decode.kama` (`column::<T>`, `CellReader`); and kama's
SPEC, prelude and compiler source. Its decisions are under "Decided, and why", "Phase 3". Step 0b confirmed the kama
facts they rest on by repro, on 0.9.542 and on cstar's 0.9.558.

**Two compiler gaps shape it** (KAMA_GAPS.md):
- **KPG-38**: two files that convert the same primitive to the same contract fail a release build. It is fixed in
  0.9.543, but no tagged release has it, and CI stays on `v0.9.542` until one does (the maintainer's decision,
  2026-10-08). Until then:
  - each test program converts primitives to `RedisArg` in exactly one file, `arg_test.kama`;
  - the package itself never converts: adapter bodies and every helper write through `Command`'s `arg*` methods.
- **KRD-7**: an adapter over a std type cannot name `Command` in its signature, on any compiler yet. So the
  `DynamicArray<uint8>`, `DynamicArray<T>` and `Uuid` adapters wait for the fix. Until then bytes, lists and Uuids
  go through `Command.argBytes`, a loop of `add`, and `arg(text: "${id}")`.

When a tag has both fixes: raise the floor and the CI pin, drop the one-file rule, and add the three adapters.

### The session's steps

Each step ends green before its commit:
- `tools/test.sh`, debug and release, on `v0.9.542` (CI's) and on cstar's newest build;
- the live tests on the matrix.

0. **Done.** KPG-38 is cited, KRD-7 is filed, the repros are run, and the decisions are written under "Decided, and
   why".
1. **Vectors** (`tools/gen-server-vectors.sh`, one run; the existing cases' bytes must not change):
   - **Typed RESP2/RESP3 pairs.** For each protocol, a fresh connection, FLUSHALL and the same setup, with the
     setup's arguments written out so expected values derive from them. Cases: GET (hit, missing, big, binary),
     MGET, INCRBYFLOAT, HGETALL, HMGET, SMEMBERS, SMISMEMBER, ZRANGE WITHSCORES, ZSCORE, XRANGE, XREAD, LPOS, CONFIG
     GET, EXISTS, TYPE, EVAL.
   - **Transactions:** MULTI's `+OK` and a `+QUEUED`; EXEC's null after a broken WATCH, under each protocol; a
     queue-time error.
   - **An error inside a reply:** EVAL returning `redis.pcall`'s error inside an array. It becomes `call`'s "an error
     inside a reply stays a value" case, which EXEC can no longer serve once `call` refuses EXEC.
   - **Scripts:** SCRIPT LOAD SHAs, an EVALSHA hit, an EVAL.
   - **SCAN pages:** SCAN, SSCAN, HSCAN, ZSCAN.
   - **BLPOP:** its null and a success, under each protocol, and the server's refusal of the timeouts `abc` and `-1`.
   - **Blocking:** `ACL CAT blocking` on every server, and `COMMAND DOCS` of each @blocking command on 7.0 and later.
     Redis 6.2 has the category (eight commands) but no COMMAND DOCS, so its commands are classified from the 7.x
     data. ACL CAT lists in hash order, so the generator sorts it; COMMAND DOCS is reduced to each argument's name,
     type, token, flags and child count.

   Every capture must come out the same on every run, or `git diff` after a rerun is not empty:
   - stream IDs are explicit (`XADD k 1-1 …`);
   - sets hold integers, so they are intsets (6.2 orders a hashtable by a per-process seed);
   - SCAN runs on a database of one key;
   - a SCAN of several pages is tested live only.

   The resp vectors' live captures are not true pairs: they are de-duplicated, and the RESP3 run follows the RESP2
   run on the same data.
2. **`RedisError::Value` and the refused commands**, all but MULTI, EXEC and DISCARD:
   - `Command` gets a private `trouble`, a public `refuse(detail:)`, and a friend-granted way to read them.
   - `src/wire/known.kama` (internal) holds the table, and `call` checks it before writing.
   - `fake_server.kama` gets `Step::ExpectBytes` for binary arguments.
   - A refused command must leave the script's next `Expect` matching, which proves nothing was sent.
3. **`RedisArg` and `cmd`** (`src/arg.kama`; `Command.add(value:)` and `argFloat(value:)`), with the primitives' and
   string's adapters (KRD-7). Tests in one conversion file per program:
   - every tag form and refusal;
   - all 256 byte values live, through `argBytes`;
   - the int64 and uint64 extremes;
   - floats (0.1, 1e21, 5e-324, -0.0, inf, -inf) round-tripped through ZADD and ZSCORE under both protocols. They are
     compared raw here, and step 4 adds the typed check.
4. **Typed replies** (`src/reply.kama`, on postgres's `decode.kama` model). The reader owns a flat pre-order list of
   nodes, moved out of the consumed Value. Tests:
   - every typed pair reads the same under both protocols, equal to the setup;
   - every resp vector read as each of 7 types is Ok or Err, never a panic;
   - the edges: odd maps, overflow, non-UTF-8 text, Null, EXEC's error element, a 1024-deep reply.

   It can split into 4a (scalars, arrays, `replyOpt`/`replyOpts`) and 4b (maps, structs, records).
5. **Pipelines** (`src/pipeline.kama`): 1000 commands through the jammed server, an error in the middle, a push in the
   middle, a late reply, a hangup, a refused command, an empty pipeline; live, 1000 INCRs with a WRONGTYPE mixed in.
   The deadline's plumbing goes in here, and every command counts as not blocking until step 6.
6. **Blocking deadlines.**
   - Unit: the table covers every `ACL CAT blocking` name and agrees with COMMAND DOCS. A new `Step::Patient` holds a
     reply until the client waits with at least a stated time left.
   - Live, with `command_timeout=0.5`: `BLPOP k 1` returns Null, `BLPOP k 0` is released by a second connection,
     and `XREAD BLOCK 800`.
   - Phase 2's two BLPOP checks in `timeout_test.kama` assert the old limitation, and they become these checks.
     "A call that outlasts `command_timeout` times out and closes the connection" moves to a command the server
     holds up: a second connection sends `CLIENT PAUSE 1000 WRITE`, then `SET` runs under 0.3 s. DEBUG is off on the
     test servers.
7. **Transactions** (`src/transaction.kama`): commit, a conflict from a second connection, EXECABORT, an error inside
   EXEC, `watched` retrying.
   - MULTI, EXEC and DISCARD join the refused commands in this step, not in step 2. Until `transact` exists, phase 2's
     MULTI/EXEC checks (`connection_test.kama`, `failure_test.kama`) need `call`.
   - Those checks move onto `transact` in the same commit.
8. **Scripts** (`src/script.kama`): `sha1()` equals every server's SCRIPT LOAD; NOSCRIPT then EVAL, then a hit;
   `_RO` from 7.0. The live test sends SCRIPT FLUSH first, since the debug and release runs share the server.
9. **SCAN** (`src/scan.kama`): captured pages; live, 1000 keys come back whole with MATCH, COUNT and TYPE;
   SSCAN, HSCAN and ZSCAN; NOVALUES only on Redis 7.4+ and Valkey 8.0+.
10. **Close phase 3:** ROADMAP, AGENTS.redis.md, README examples compiled against a live server, CHANGELOG, the
    `src/redis.kama` header, and the whole matrix in debug and release.

**If the session runs long:**
- The minimum is steps 0–5, then 6 (it removes phase 2's written-down BLPOP limitation), then 7.
- Wherever it stops, end with a "where this is" commit naming the next step.

**Carried past phase 3, by decision:**
- `Command.addFields(value: Serializable)` for HSET from a struct (no adapter can cover every struct);
- a `<Map>` adapter;
- measuring the per-byte typed read of `DynamicArray<uint8>` before asking cstar for a bulk read;
- once a tag has KPG-38's and KRD-7's fixes: the `DynamicArray<uint8>`, `DynamicArray<T>` and `Uuid` adapters, and
  lifting the one-conversion-file rule.

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
  - Blocking commands get deadlines of their own in phase 3 (step 6). Until then a `BLPOP` longer than
    `command_timeout` needs it raised.
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

### Phase 3

Drawn up 2026-10-08 (see "Phase 3: where to start" for the sources). Step 0b's repros, run on 0.9.542 and 0.9.558,
confirmed the kama facts underneath, and are listed at the end.

- **Refusals:**
  - `RedisError::Value(detail)` is an argument the client refuses, or a reply that does not convert.
  - A malformed tag literal or a refused command is `Usage`.
  - Both are refused before anything is written, and the connection stays usable.
- **Arguments:** `type contract RedisArg for value, resource, enum, intrinsic { const fn void writeRedisArg(ref
  Command into); }`. A value writes itself with `Command`'s `arg`/`argBytes`/`argInt`/`argFloat`. (Not
  `ref Serializer`: it has no bulk-bytes write, and it gives an empty byte array and an empty list the same arity.)
  - **The adapters:**

    | type | becomes |
    |---|---|
    | int8 to int64, isize, uint16 to uint64 | decimal |
    | float32, float64 | shortest round-trip, `inf`/`-inf`; NaN refused (the server rejects it too) |
    | string | its bytes |
    | `DynamicArray<uint8>` | exactly one binary argument, even when empty (after KRD-7) |
    | `DynamicArray<T: RedisArg>` | one argument per element, so an empty list is none (after KRD-7) |
    | Uuid | its text (after KRD-7) |

    The last three wait for KRD-7's fix in a tagged compiler. Until then a caller writes them through `Command`:
    `argBytes`, a loop of `add`, `arg(text: "${id}")`.

  - **No adapter, so each is a compile-time refusal:**
    - bool and char: redis-py refuses bool; redis-rs and go-redis send 1/0;
    - Optional: redis-rs drops a None; go-redis sends "";
    - uint8, Timestamp, Date and Duration: no single meaning (EXPIREAT wants seconds, PEXPIREAT milliseconds).
  - **Coherence:** `<DynamicArray<uint8>>` beside `<DynamicArray> when [T: RedisArg]` is coherent only because uint8
    has no adapter, since the compiler checks `when` per instance (SPEC, "Adapters"). This is confirmed by repro
    when KRD-7 lets either be written.
- **`cmd"…"`** is `fn Command cmd(Template<RedisArg> t)`.
  - Its literal splits on ASCII whitespace into whole arguments, and each hole is one argument, or several for a list.
  - It is refused for: text touching a hole (`user:${id}`: a hole is never spliced into text), two holes side by
    side, a quote in the literal, and an empty command.
- **Commands a connection cannot carry.** `call` and `run` refuse these before sending, by name, case-insensitively:
  - SUBSCRIBE, PSUBSCRIBE, SSUBSCRIBE and the three UNSUBSCRIBEs (phase 4);
  - MONITOR, SYNC, PSYNC, CLIENT REPLY, HELLO, RESET, QUIT;
  - SCRIPT DEBUG, which turns the next EVAL into a debugging session rather than a reply;
  - MULTI, EXEC and DISCARD, since `transact` is the one way. They join the table in the same step as `transact`.

  WATCH and UNWATCH stay allowed. The table lives in the internal `redis::wire` module (`known.kama`), so it is not
  public API.
- **Typed replies:** `reply::<T>`, `replyOpt::<T>` and `replyOpts::<T>` (MGET; `Optional<T>` is not
  `Deserializable` on its own), each consuming a `Result<Value, RedisError>`. So `reply::<T>(result:
  conn.call(command: c))` is the one way, for `call`, pipeline and transaction replies alike. One rule set covers
  both protocols:

  | asked for | read from |
  |---|---|
  | integers | Integer, a strict decimal string, an integral Double that fits, a BigNumber that fits |
  | floats | Double, Integer, BigNumber, or text (inf and nan included) |
  | bool | Boolean, or Integer 0 or 1, nothing else |
  | string | Bulk, Simple, Verbatim (its text), Integer, Double, BigNumber; not UTF-8 is refused, pointing at `DynamicArray<uint8>` |
  | `DynamicArray<uint8>` | the string kinds |
  | `DynamicArray<T>` and Set | an Array, a Set, or a Map flattened to key, value, … |
  | structs | by name, from a Map or a top-level even Array; by position, from an Array inside another reply |
  | std Map, or a two-field object inside an array | a positional pair: a 2-element Array element, or element plus the next item |

  - **Records.** An Array inside a reply is read by position, because there it is a record: XRANGE's `[id, fields]`,
    XPENDING's entries, XINFO STREAM's `first-entry`. Reading it by name would take a value for a key. At the top a
    flat Array is read by name (HGETALL and CONFIG GET under RESP2). `replyRecord::<T>` reads a top-level Array by
    position instead (BLPOP's `[key, value]`, LMPOP). One case is lost: a struct from a RESP2 flat map nested inside
    another reply (XINFO GROUPS' elements). Those still read into a `Map<string, string>`, and under RESP3 they are
    Maps.
  - A struct with a `string` field is a `type resource` (it owns), so its fields are private, and the caller gives it
    accessors.
  - Null reads only into an Optional, and `readNull` consumes it, as std's JSON reader does (postgres's does not,
    because a cell is not a cursor). Attributes are unwrapped.
  - An Error element that is read fails as `Server` with its code.
  - A reader failure is `Value`, naming the path and what was asked.
  - Peers: redis-rs reads a map from a Map or an even Array, a float from a parsed bulk, and a bool from a non-zero
    Int. go-redis reads a map from a map or an even array, and a bool from "OK"/"1"/"true".
- **Pipelines:** `Connection.run(pipeline:) → Replies`, each reply taken once (`take(index:)`).
  - One write.
  - One deadline: `command_timeout` plus the blocking commands' own timeouts.
  - Each reply stands alone.
  - I/O, protocol errors or a timeout fail the whole call and close the connection.
  - No size limit, as none of the peers has one.
- **Blocking commands:** the deadline is the command's own timeout plus `command_timeout`; a timeout of 0 sets no
  deadline. (go-redis adds 10 s. redis-py and redis-rs cut BLPOP off at their socket timeout.)

  | commands | timeout |
  |---|---|
  | BLPOP, BRPOP, BRPOPLPUSH, BLMOVE, BZPOPMIN, BZPOPMAX | last argument, seconds |
  | BLMOVEM (Redis 8.10) | 5th argument, seconds; a COUNT or EXACTLY and OBO or BULK may follow it |
  | BLMPOP, BZMPOP | first argument, seconds |
  | XREAD, XREADGROUP | `BLOCK`, milliseconds |
  | WAIT | 2nd argument, milliseconds |
  | WAITAOF | 3rd argument, milliseconds |

  - **Checked against the servers.** Every name in each server's `ACL CAT blocking` must be in the table. That covers
    eight commands on Redis 6.2, and WAIT and WAITAOF from Redis 7.4 and Valkey 8.1 on. Each position and unit must
    match `COMMAND DOCS` on 7.0 and later: an integer is milliseconds, a double is seconds.
  - **XREAD and XREADGROUP.** `BLOCK` is found by stepping over each option before `STREAMS` by its arity:
    - GROUP takes two;
    - COUNT, MAXCOUNT, MAXSIZE (8.10) and CLAIM (8.4) take one each;
    - NOACK takes none.

    The server's own parser steps the same way, and COMMAND DOCS lists every option on every server, so a new one
    fails the unit test when the vectors are regenerated.
- **Transactions:** `transact(pipeline:)` writes MULTI, the commands and EXEC in one write. It reads every reply before
  it decides, so the connection stays in step with the server.
  - Its outcome is `TxOutcome { Committed(Replies), WatchConflict }`. EXEC's null is `WatchConflict`, an outcome
    rather than an error (go-redis `TxFailedErr`, redis-py `WatchError`, redis-rs `None`).
  - EXECABORT is `Server`, carrying the first queue-time error.
  - The deadline is `command_timeout` alone, since nothing blocks inside MULTI.
  - `watched(keys:, body: TxBody, attempts:)` retries a bounded number of times, which the caller states. Peers retry
    without bound (redis-rs, redis-py) or leave it to the caller (go-redis).
- **Scripts:** `Script` computes its SHA-1 client-side (`std::digest::sha1`), and `ScriptCall` carries the call.
  - `eval` sends EVALSHA, and on NOSCRIPT, EVAL (go-redis's way; redis-py and redis-rs SCRIPT LOAD first). That is
    safe, because NOSCRIPT means the script never ran.
  - A read-only script uses the `_RO` forms (7.0+).
  - Inside pipelines and transactions, EVAL (redis.io: NOSCRIPT cannot be handled there).
  - FCALL needs nothing special.
- **SCAN** is a page API, not an Iterator: an iterator cannot borrow a Connection, has no error channel, and would need
  a hand-back.
  - `Scan.next(conn:)` returns every page, empty ones included, so no call makes an unbounded number of round trips.
  - The cursor is opaque bytes (Valkey 9.1's CLUSTERSCAN has string cursors, and Lettuce keeps a String).
  - Repeats are documented.

- **What step 0b's repros showed** (in the session's scratchpad; each on 0.9.542 and 0.9.558, debug and release):
  - `RedisArg`'s adapters for the integers, `isize` (`cast<int64>(this)`), `uint64`, the floats and `string` build,
    and a value passes `ref this` to its contract method.
  - A `cmd"…"` with holes, and `cmd"PING"` with none, both build and read their parts.
  - Two application files that convert fail release on 0.9.542 (KPG-38) and pass on 0.9.558.
  - The adapters over `DynamicArray<uint8>`, `<DynamicArray> when [T: RedisArg]` and `Uuid` are refused on both:
    KRD-7.
  - A custom `Deserializer` reads, through a `via::<T>(result: call())` generic:
    - a `@generate` struct by name from a map, keys in any order, with an Optional field's Null consumed;
    - a struct by name from a top-level flat array;
    - structs by position (`FieldKey::Position` follows declaration order) from nested arrays;
    - std `Map<string, int64>` from a map, a flat array and an array of pairs.
  - `DynamicArray<Optional<int64>>` is refused as `Deserializable`, so `replyOpts` is needed.
  - `RedisError::Value` beside an imported `resp::Value` does not clash.
  - A `type value` element mutates in place through `frames[k].x = …`.
  - add, swap and pop take an element out of a `DynamicArray`.

