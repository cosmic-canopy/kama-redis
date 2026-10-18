# Roadmap

Where this is, 2026-10-18: phases 0 to 3 are done, on kama v0.9.667. **The goal now is releasing 0.1.0**, a complete
client for one server. "The release plan" below says what each release holds. Phase 4 (pub/sub) is next, and "Phase 4:
where to start" is its session plan. Phases 5 (TLS) and 7a (reconnection, examples, hardening, docs) follow, each with
an outline, and then 0.1.0.
- `tools/redis.sh` runs every server in the matrix with TLS on and one ACL user per authentication case.
  `tools/redis.sh smoke` passes all 16 checks on Redis 6.2.24, 7.2.16, 7.4.11, 8.2.10 and 8.10.2, and on Valkey
  7.2.14, 8.1.10 and 9.1.2.
- The pure layers are in, each checked against upstream by script:
  - `redis::resp` against 593 vectors: hiredis's reading of its own tests, of the spec's examples and of what all
    eight servers send.
  - `redis::cluster` key slots against the cluster specification and against `CLUSTER KEYSLOT` on all eight servers.
  - `RedisUrl` against redis-cli and valkey-cli, asked live.
- The connection is in (phase 2): `Config`, `Connection`, `RedisError`, `Command`, `ServerInfo`, the `Transport` and
  `Dialer` contracts. The unit suite's scripted server plays every server's real replies and Envoy's refusals
  (`tools/gen-server-vectors.sh`).
- Commands are in (phase 3):
  - `RedisArg` and the `cmd"…"` tag;
  - typed replies (`reply::<T>` and its kin);
  - pipelines, blocking deadlines, transactions (`transact`, `watched`), scripts and `Scan`.
  The unit suite reads every typed pair from all eight servers under both protocols, and builds each blocking
  command from every server's COMMAND DOCS. `tools/check-readme.sh` runs the README's programs live.
- Gates: `tools/test.sh` is green, debug and release, on kama 0.9.667 (the floor and CI's pin, 2026-10-18) and cstar's
  0.9.668; `tools/test-integration.sh` on all eight servers on 0.9.667; the README's programs live.
- Open gaps here: none. KRD-7, KRD-8 and KPG-38 were fixed upstream and tagged in v0.9.573 (2026-10-13): the floor
  and CI pin moved there, `RedisArg` gained its bytes, list and Uuid adapters, the one-conversion-file rule is gone,
  and the reply reader implements 0.9.569's `Deserializer` (`DeErrorKind`, a missing field named by its path).

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
| 3 | Commands. Arguments through a `RedisArg` contract with `type adapter`s (as `PgParam` is); the `cmd"SET ${key} ${value} EX 10"` tag, whose holes are always whole arguments, never spliced into text; replies read into typed values through `Deserializable` (`reply::<T>`, as `column::<T>`). Pipelining. `MULTI`/`EXEC`/`WATCH`. Scripts and functions (`EVALSHA`, falling back to `EVAL` on `NOSCRIPT`). `SCAN` cursors. Blocking commands with their own deadlines | **done** |
| 4 | Server push. Pub/sub on a `Subscriber` that owns its connection, under RESP3 and RESP2 (every peer gives pub/sub its own connection). Sharded pub/sub. **0.1.0.** Client-side caching (`CLIENT TRACKING` invalidations, RESP3, a cache per connection) moves to **0.3.0**. See "Phase 4: where to start" | next |
| 5 | TLS through `@kama/tls`: `rediss://`, verification of the chain and the host name, client certificates, SNI. **0.1.0** | |
| 6 | Topologies. Cluster: the slot map from `CLUSTER SHARDS` (`CLUSTER SLOTS` before 7.0), `MOVED` and `ASK`, multi-key commands on one slot, reads from replicas. Sentinel: discovery and failover. A multi-node `tools/redis.sh` topology for both. **0.2.0** | |
| 7a | Reconnection (a connection's, and a subscriber's resubscribing), examples, hardening (a server restart, bounded memory under load), docs. **0.1.0** | |
| 7b | Pool (cross-isolate), and hardening across a failover. **0.3.0**, with client-side caching | |
| — | Publish 0.1.0 after 4, 5 and 7a; 0.2.0 after 6; 0.3.0 after 7b and client-side caching. Each only on the maintainer's word | |

### The release plan (decided by the maintainer, 2026-10-18)

The roadmap is unchanged; its releases are phased. Each release is held to the same bar as the rest:
- every form it covers is honoured or refused;
- every failure path is tested against the scripted server;
- the whole matrix passes live, debug and release.

Anything not in a release yet is refused clearly rather than half there. Today `rediss://` is refused by name, a
cluster's MOVED comes back as `Server` with its code, and `CLIENT TRACKING` will be refused (phase 4, step 2).

- **0.1.0, a complete client for one server:**
  - what phases 0–3 built;
  - pub/sub and sharded pub/sub (phase 4, without client-side caching);
  - TLS (phase 5);
  - reconnection, examples, hardening and docs (phase 7a).

  The order: phase 4 (its session plan is below), then 5, then 7a, then the release.
- **0.2.0, topologies:** Cluster and Sentinel (phase 6).
- **0.3.0, scale:** a pool shared across isolates, and hardening across a failover (phase 7b), and client-side caching
  (phase 4's research and decisions, kept below).
- **Carried, to be placed in a release:**
  - `Command.addFields(value: Serializable)` (HSET from a struct);
  - a `<Map>` adapter;
  - measuring the typed read of `DynamicArray<uint8>`, byte by byte, before asking cstar for a bulk read.
- **Each release** (AGENTS.package.md, "Publishing"):
  - the CHANGELOG's Unreleased section becomes the version, kept in step with `kama.json` and `libraryVersion()`
    (`tools/test.sh` checks the two);
  - CI green on the pinned tag;
  - `kama publish kama.json --dry-run` lists no certificates and no agent files;
  - `./ops publish ../kama-redis/kama.json` from `../kama-registry`, only on the maintainer's word, since a version is
    permanent.
- **Neighbours, as of 2026-10-18:**
  - `@kama/tls` 0.1.2 is on the registry, and checks clean on v0.9.667. It is phase 5's.
  - `@kama/postgres` 0.2.0, the model, no longer builds on v0.9.667 (`DeError`'s kinds, a non-exhaustive
    `Interest`). That is its repository's to fix, but it means postgres's code is a model to read, not one to build
    against.
  - `@kama/http` is seeded, with nothing usable yet. The UI packages (`ui`, `rmlui`, `freetype`) do not touch this one.

## Phase 4: where to start

The plan for the next session, drawn up on 2026-10-13 from primary sources:
- **The peers' source:** go-redis v9.23.0 (`pubsub.go`, `csc_*.go`), redis-py 8.1.0 (`client.py`'s `PubSub`,
  `cache.py`), redis-rs 1.7.1 (`connection.rs`, `aio/pubsub.rs`, `caching/`), Lettuce 7.9.0 (`PubSubEndpoint`,
  `ClientSideCaching`), and rueidis (`pipe.go`, `lru.go`), the most complete client-side cache.
- **The servers:** Redis 8.10.2's and Valkey 9.1.2's own source (`pubsub.c`, `tracking.c`, `server.c`), and the
  redis.io and valkey.io pub/sub and client-side caching pages.
- **Probes:** every probe below, run live on all eight servers, in throwaway containers.
- **The model:** @kama/postgres's `waitForNotification`.

The bar is phase 3's: every form honoured or refused, every failure path against the scripted server, the whole matrix
live, debug and release.

**A gap in today's code, fixed first.** `CLIENT TRACKING` and `CLIENT CACHING` are not refused. Under RESP3, a caller
can turn tracking on through `call`, and the invalidations then pile up in the connection's set-aside pushes, unread
and unbounded.

### What the servers do (probed on all eight; the generator will capture each as vectors)

The probe scripts lived in a session's scratch directory and are gone. What they found is below, server by server
where servers differ, and step 1 writes each capture into `tools/gen-server-vectors.sh` from it.
- **Confirmations.** SUBSCRIBE, PSUBSCRIBE and SSUBSCRIBE get one confirmation per name, and no other reply:
  `[subscribe, name, count]`.
  - Under RESP3 a confirmation is a push (`>3`); under RESP2 it is an array.
  - A name subscribed twice is confirmed twice, with the count unchanged.
- **Unsubscribing.**
  - UNSUBSCRIBE with names: one confirmation per name, a name never subscribed included.
  - With no names: one confirmation per subscribed name, **in hash order, which differs by server**, so they are
    matched by name, never by position.
  - With nothing subscribed: one confirmation with a null name (`$-1`, or `_` under RESP3).
- **Counts.** A SUBSCRIBE or PSUBSCRIBE count covers channels and patterns; an SSUBSCRIBE count covers shard channels
  alone. A connection leaves RESP2's subscribed mode only when both reach 0.
- **Messages:** `[message, channel, payload]`, `[pmessage, pattern, channel, payload]` and `[smessage, channel,
  payload]`. A message that both a channel and a pattern match arrives twice.
- **RESP2's subscribed mode.**
  - Only `(P|S)SUBSCRIBE`, `(P|S)UNSUBSCRIBE`, PING, QUIT and RESET are allowed. Anything else, HELLO included, is
    refused with the server's own text (6.2's names `(P)SUBSCRIBE`). EXEC is refused as EXECABORT.
  - PING answers `["pong", ""]`, in lower case.
  - Under RESP3, any command runs while subscribed, PING answers `+PONG`, and pushes interleave with replies (a
    message arrived during a `BLPOP`).
- **Ordering.**
  - **A RESP3 client that PUBLISHes to a channel it is subscribed to** gets the reply first and then the message on
    7.2 and later; on 6.2, the pushes come first.
  - **SUBSCRIBE inside MULTI** is QUEUED. Under RESP3, EXEC's array then holds the push (`*1 >3 subscribe …`).
- **Sharded pub/sub** (7.0 and later; 6.2 answers `unknown command`).
  - A standalone server accepts SSUBSCRIBE across slots. A cluster answers CROSSSLOT, or MOVED for a slot elsewhere.
  - When a slot moves away, the server sends a `sunsubscribe` of its own, and a RESP2 connection whose counts reach
    0 leaves subscribed mode.
  - A plain PUBLISH does not reach a shard subscriber.
- **RESET** drops every subscription and tracking silently, with no unsubscribe pushes, and reverts to RESP2.
  `HELLO 2` on a RESP3 subscriber keeps the subscriptions, now in RESP2's subscribed mode.
- **Invalidations.**
  - **Shape.** RESP3 sends `>2 invalidate [keys]`. Default mode sends one key per push, and an MSET or EXEC sends a
    push per key. A FLUSHALL or FLUSHDB sends `>2 invalidate _` to every tracking client.
  - **Order.** A connection's own write gets its reply first, then the push, on all eight. A push can arrive before
    an unrelated reply.
  - **Options.** NOLOOP drops the push for the connection's own writes, and still forgets the key. OPTIN tracks only
    a read after `CLIENT CACHING yes`, and inside MULTI that covers the whole transaction. A key is forgotten once
    invalidated, so it must be read again to be tracked.
  - **Under RESP2,** `CLIENT TRACKING on` without REDIRECT answers `+OK`, and **nothing is ever delivered**. With
    REDIRECT, the target must be subscribed to `__redis__:invalidate`.
  - The server's errors for each misuse (BCAST switching, overlapping prefixes, CACHING outside OPTIN/OPTOUT, a
    REDIRECT to a missing client) are exact strings; the generator captures them.
- **The server's limits.**
  - `client-output-buffer-limit pubsub 32mb 8mb 60` disconnects a subscriber that falls behind.
  - `tracking-table-max-keys` (1,000,000) evicts keys as invalidations.
  - Delivery is at most once.

### What the peers do
- **Pub/sub.**
  - **All four give pub/sub a connection of its own, under RESP3 as under RESP2,** although RESP3 would allow
    sharing. redis-rs alone subscribes on a command connection, and only under RESP3.
  - On a command connection, a pub/sub push is logged and dropped (redis-py) or goes to a generic push callback
    (Lettuce, redis-rs).
  - **Waiting.** go-redis's `ReceiveTimeout` and redis-py's `get_message(timeout)` block, up to a time. A background
    reader (go-redis `Channel()`, redis-py `run_in_thread`) is offered beside them.
  - **Confirmations are typed results with their counts.** Several peers take the first confirmation as the
    command's reply and pair the rest wrongly.
  - **Resubscribing.** go-redis, redis-py and Lettuce resubscribe from client-side sets on a reconnect.
  - **Health checks.** go-redis pings every 3 s and redis-py on an interval. redis-rs and Lettuce never ping.
  - **Bounds.** go-redis alone has one: 100 messages, then a drop after 60 s. redis-py is pull-based, and redis-rs and
    Lettuce's default are unbounded.
  - **Sharded pub/sub:** redis-py is the most complete, with a connection per node and reconciliation when a slot
    moves. The others route by the first channel.
- **Client-side caching.**
  - **Maturity.** Lettuce's is deprecated, and go-redis's and redis-rs's are experimental. redis-py's refuses RESP2,
    and refuses Valkey too.
  - **Under RESP2,** every peer refuses caching or leaves it out.
  - **rueidis is the model:**
    - a cache per connection, so values and invalidations come down one ordered stream;
    - OPTIN, with `CLIENT CACHING YES, MULTI, PTTL key, command, EXEC`, so a value comes back with its server TTL;
    - a pending entry before sending;
    - an allow-list of about 70 cacheable commands;
    - an LRU bounded in bytes.
  - **Commonly missed:** the null flush (redis-rs), the server TTL (redis-py, go-redis, Lettuce), a pending marker
    (Lettuce, redis-rs), a flush on disconnect (Lettuce), and reading one's own writes.

### Proposed decisions (step 0 confirmed the kama facts by repro; "Decided, and why", "Phase 4", holds them as decided)
- **Pub/sub runs on a `Subscriber`, which owns its connection, under both protocols,** as every peer does. The
  ROADMAP's earlier "beside commands on the same connection under RESP3" is dropped, for three reasons:
  - a connection belongs to one isolate, and waiting for messages blocks it;
  - under RESP2 a subscribed connection takes no other commands;
  - it is one way for both protocols.

  `Connection.call` keeps refusing the (un)subscribe commands, which get no reply of their own.
  - **Making one.** `Subscriber.over(connection:)` takes a connection whole. `Subscriber.connect(config:)` opens one.
    `release()` unsubscribes everything, waits until every count reaches 0, and hands the connection back.
  - **(Un)subscribing.** `subscribe`, `psubscribe`, `ssubscribe`, `unsubscribe`, `punsubscribe` and `sunsubscribe`
    each take the names as a `RedisArg` (a list, or none for "all").
    - Each writes one command and reads until every confirmation it causes has come, matched by name.
    - The three subscription sets follow the server's confirmations, as redis-py's and Lettuce's do.
    - A message read on the way is queued.
  - **Waiting.** `next(timeout: Optional<Duration>) -> Result<Optional<Delivery>, RedisError>` gives the oldest
    queued delivery, else the next to arrive. None means the time passed. The connection stays open: nothing was
    asked of the server, and a message half-read stays in the reader for the next call (postgres's
    `waitForNotification`).
  - **`Delivery`:**
    - `Message(Message)`, for message, pmessage and smessage alike. A `Message` has its kind, channel, pattern and
      payload; the payload is bytes, with a `text()` that refuses non-UTF-8.
    - `Unsubscribed(kind, channel)`, for a `sunsubscribe` the server sent of its own accord (a slot moved).
    - Confirmations are not deliveries: the call that caused them consumes them.
  - **`ping()`** reads both shapes, RESP2's `["pong", ""]` and RESP3's `+PONG`. RESET and HELLO are refused on a
    subscriber, since they would silently drop the subscriptions or change the protocol.
  - **Bounds.** Delivery is pull-based: unread messages wait in the socket and the server's buffer, where the server
    disconnects a subscriber that falls behind. The one queue on this side holds what arrives while a call waits for
    its confirmations. It is bounded in bytes (`resp::Limits.maxReplyBytes`, 1 GiB), and past that the subscriber
    fails and closes rather than drop anything silently.
  - **Out of scope here.** Cluster routing of shard channels is phase 6. Resubscribing after a reconnect, and a
    health check, are phase 7, which the kept sets make possible. Delivery is at most once, and the docs say so.
  - **PUBLISH, SPUBLISH and PUBSUB** are ordinary commands (`reply::<int64>`). The count PUBLISH returns covers the
    node it was sent to.
- **A connection's other pushes:**
  - `takePushes()` hands over the set-aside pushes, oldest first.
  - The set-aside list is bounded (1024). Past that the oldest is dropped and counted (`droppedPushes()`), never
    silently.
  - `call` refuses `CLIENT TRACKING` and `CLIENT CACHING` with `Usage`: caching is `enableCache`'s alone.
- **Client-side caching follows rueidis.** (**0.3.0**, by the release plan. The research and the decisions stay here,
  so that release starts from them.)
  - **Scope.** RESP3 only. Under RESP2 `enableCache` is `Usage`, since the server would answer `+OK` and then drop
    every invalidation.
  - **One cache per connection.** `Connection.enableCache(config: CacheConfig)` sends `CLIENT TRACKING ON OPTIN`.
  - **`cached(command:, ttl:)`** serves a command on the allow-list from the cache, or sends `CLIENT CACHING YES`,
    `MULTI`, `PTTL` for each key, the command and `EXEC` in one write.
    - An entry lives as long as the shorter of the server's TTL and `ttl`, which is required.
    - The cache is keyed by the command's bytes, with a reverse index from each Redis key.
  - **The allow-list** is generated by script from every server's COMMAND INFO: read-only, keyed, not blocking, not
    random, and not a script runner, on all eight servers. XREAD, XPENDING and SORT_RO are left out, as go-redis does.
  - **Every frame is applied in wire order.** A pending entry is made before sending, and a reply is stored only if
    its entry is still pending; an invalidation removes pending entries too.
    - Before a hit is served, every frame already buffered is applied without blocking.
    - After any other command on a caching connection, the next hit first makes a round trip (PING). That
      guarantees the invalidation of the connection's own write has arrived, since the server sends it right after
      the write's reply.
  - **Everything is flushed** on close, I/O failure, timeout, protocol error, a null invalidation, and
    `tracking-redir-broken`.
  - **Refused on a caching connection:** SELECT, AUTH, HELLO, RESET, and `CLIENT TRACKING` or `CLIENT CACHING`.
  - **Bounds:** entries and bytes, LRU, and a pending entry is never evicted.
  - **Left out:** BCAST and REDIRECT. Only rueidis offers BCAST, and it is safe only when every cached key falls under
    a prefix. Both stay refused.

### The session's steps
Each step ends green before its commit:
- `tools/test.sh`, debug and release, on CI's tag and on cstar's newest build;
- the live matrix.

0. **Done (2026-10-18).** Repros: a `Subscriber` that takes a `Connection` by value and hands it back, a `Delivery`
   enum with resource payloads, and per-method `friend` grants from `Connection`. The decisions are under "Decided,
   and why", "Phase 4". The cache's LRU and a reachable `drain` wait for 0.3.0, with the cache.
1. **Vectors** (`tools/gen-server-vectors.sh`). **Done (2026-10-18)**: 80 pub/sub cases a server, 56 on 6.2, which has
   no sharded pub/sub. Two runs give the same file, and the existing cases' bytes did not move. Found on the way: a
   redirected flush is `>2 invalidate $-1` under RESP3 (not `_`), and RESP2's redirected invalidation is a `message`
   with an array payload ("Decided, and why", "Phase 4").
   - Captures read by count, and second-connection setups (PUBLISH, SET, FLUSHALL), for every probe above under both
     protocols.
   - An unsubscribe-all's confirmations are recorded sorted. Their order follows the server's hash seed, which is
     random per process, so a recorded order would differ on the next run. The unit test plays every permutation.
   - A two-node cluster for MOVED, CROSSSLOT and the server's own `sunsubscribe` (bytes only; routing is phase 6).
     `redis-cli --cluster create` needs three primaries, so the two nodes are joined by hand (ADDSLOTSRANGE, CLUSTER
     MEET), on 7.0 and later only.
   - (0.3.0) Each server's COMMAND INFO flags, for the allow-list: captured in step 5, which uses them.
2. **A connection's pushes:** `takePushes`, the bound, `droppedPushes`, and `CLIENT TRACKING`/`CACHING` refused.
3. **`Subscriber`, under RESP2 and RESP3.**
   - Unit: every captured confirmation order; messages queued during a subscribe; a timeout that keeps the
     connection; a hangup; the RESP2 refusals; ping's two shapes; `release`.
   - Live: a publisher from a second connection, patterns, a message matched twice, and `release` back to `call`.
4. **Sharded pub/sub, and the server's own `sunsubscribe`.** Unit tests from the cluster captures; live on a
   standalone server; refused on 6.2.
5. **(0.3.0) Client-side caching.** Not in this phase's run for 0.1.0. `CacheConfig`, `enableCache`, `cached`, the
   generated allow-list, the race (pending entries, through the scripted server), and every flush rule. Live: another
   connection's write, FLUSHALL, a key's TTL, reading one's own write, and the bounds. Step 1's COMMAND INFO capture
   serves it then.
6. **Close phase 4:** ROADMAP, AGENTS.redis.md, README (programs checked by `tools/check-readme.sh`), CHANGELOG, the
   module header.

**For 0.1.0:** steps 0–4 and 6. If the session runs long, do 0–3, then 4.

## Phase 5: an outline (draw up its session plan from primary sources at its start, as phases 3 and 4 were)

- **What is known.**
  - `@kama/tls` 0.1.2 gives a client `TlsConfig`: `Verify::Full` (chain and name) by default, trust from the system,
    a file or PEM, a client identity (`identityFiles`/`identityPem`), revocation, ALPN and version bounds.
  - `TlsStream::<S>.client(inner:, config:, serverName:)` sends SNI and checks the name. A stepwise `handshake()`
    fits a deadline. `TlsError::Certificate` names each check that failed.
  - The model is @kama/postgres's `src/secure/`. Its `transport.kama` makes any `Transport` a `ReliableStream`, so
    TLS runs over TCP, a caller's tunnel and the scripted server alike, non-blocking end to end. `setup.kama` builds
    a configuration per attempt.
  - Redis starts TLS at once, with no in-protocol request, so postgres's `negotiate.kama` has no counterpart.
  - The test servers listen on TLS (base + 100, `tls-auth-clients optional`), with the PKI from
    `tools/gen-test-certs.sh`.
  - `rediss://` and `valkeys://` are parsed today and refused in `Config` (`tlsRefused`).
- **To research at its start:**
  - redis-cli 8.10's and valkey-cli 9.1's TLS flags (`--tls`, `--cacert`, `--cacertdir`, `--cert`, `--key`, `--sni`,
    `--insecure`, `--tls-ciphers`);
  - the peers' URL options and defaults (redis-py's `ssl_*`, go-redis's `rediss` with `ServerName`, redis-rs's
    `rediss` and `#insecure`, Lettuce's `verifyPeer`);
  - which option names to honour and which to refuse;
  - whether `insecure` (no verification) exists at all, or only `Verify` modes named for what they check.
- **Tests:**
  - unit: a TLS session over the scripted server;
  - live, on every server's TLS port: the chain and the name verified, a wrong CA, a wrong name, a client
    certificate required and offered, SNI, and a handshake past `connect_timeout`.

## Phase 7a: an outline (likewise, drawn up at its start)

- **Reconnection.**
  - Research the peers first:
    - go-redis redials through its pool;
    - redis-py retries on the next command;
    - redis-rs's `ConnectionManager` reconnects and resubscribes;
    - Lettuce reconnects on its own and replays.
  - Decide what is retried. Nothing is resent silently: a command that may have run is the caller's to retry.
  - A `Subscriber` resubscribes from its kept sets.
- **Examples:** an `examples/` program per area, built and run against a live server by a script, as
  `tools/check-readme.sh` does the README's.
- **Hardening:** a server restart in the middle of a call, a pipeline and a subscription; `CLIENT KILL`; memory
  bounded under a flood of pushes and replies.
- **Docs and the release:** the README, the CHANGELOG as `[0.1.0]`, and the checklist in "The release plan".



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
**Done 2026-10-13**, on v0.9.573 (KAMA_GAPS.md has each verification).

### The session's steps

Each step ends green before its commit:
- `tools/test.sh`, debug and release, on `v0.9.542` (CI's) and on cstar's newest build;
- the live tests on the matrix.

Every step below is done (2026-10-09), each in its own commit ("Phase 3, step N").

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
- ~~once a tag has KPG-38's and KRD-7's fixes: the `DynamicArray<uint8>`, `DynamicArray<T>` and `Uuid` adapters, and
  lifting the one-conversion-file rule~~ (done 2026-10-13, v0.9.573).

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
  - A blocking command's own timeout is added to `command_timeout` (phase 3, "Blocking commands").
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
    | float32, float64 | shortest round-trip (a float32's own, "0.1"), `inf`/`-inf`; NaN refused (the server rejects it too) |
    | string | its bytes |
    | `DynamicArray<uint8>` | exactly one binary argument, even when empty |
    | `DynamicArray<T: RedisArg>` | one argument per element, so an empty list is none |
    | Uuid | its text |

    Step 3 found, live: every float in the table comes back from ZADD and ZSCORE as the same value under both
    protocols, except the sign of zero. `-0` is sent as `-0`; Redis 6.2 keeps its sign, and 7.0 and later answer `0`
    for it (ZSCORE, ZRANGE, INCRBYFLOAT), so the sign of a zero is the server's.

    The last three waited for KRD-7's fix, and came with v0.9.573 (2026-10-13). Until then a caller writes them through `Command`:
    `argBytes`, a loop of `add`, `arg(text: "${id}")`.

  - **No adapter, so each is a compile-time refusal:**
    - bool and char: redis-py refuses bool; redis-rs and go-redis send 1/0;
    - Optional: redis-rs drops a None; go-redis sends "";
    - uint8, Timestamp, Date and Duration: no single meaning (EXPIREAT wants seconds, PEXPIREAT milliseconds).
  - **Coherence:** `<DynamicArray<uint8>>` beside `<DynamicArray> when [T: RedisArg]` is coherent only because uint8
    has no adapter, since the compiler checks `when` per instance (SPEC, "Adapters"). Confirmed on v0.9.573: both
    build, and the unit tests read each as designed.
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
- **Typed replies:** `reply::<T>`, `replyOpt::<T>`, `replyOpts::<T>` (MGET; `Optional<T>` is not
  `Deserializable` on its own), `replyRecord::<T>` and `replyRecordOpt::<T>` (a top-level array read by position:
  EXEC's, and BLPOP's or its null), each consuming a `Result<Value, RedisError>`. So `reply::<T>(result:
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
  - **What building it settled (step 4):**
    - An integer read from text follows the server's own grammar (string2ll): no `+`, no leading zero, no `-0`.
      std's `parse` accepts `+`, so the reader checks the bytes itself.
    - A double reads as an integer only when it is whole and in range, checked before the cast: kama has no
      `try cast` from a float, because an out-of-range float cast traps.
    - A float32 is parsed from text as a float32, so it is rounded once.
    - A string that is read as a list is read as its bytes, so `DynamicArray<uint8>` reads any string reply.
    - After a type reads itself without error, a reply it did not read to its end is `Value`.
    - Every typed pair reads the same from all eight servers' RESP2 and RESP3 bytes, and the reader has been run
      over every resp vector as eight types without a panic.
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
  - **What building it settled (step 5):**
    - A command is checked as it is added, as `call` checks one. The first refusal refuses the whole pipeline before
      anything is written, naming the command ("command 2: …"), as `Usage` or `Value`.
    - An empty pipeline writes nothing and has no replies.
    - A reply taken twice is `Usage`. An index past the end panics, as a collection's does (RedisError's rule for a
      contract violation).
    - `call` and `run` share one read loop (`nextReply`), which sets push messages aside.
    - A `Value::Error`'s `ServerError` comes from the internal `redis::wire`, so it is not public API.
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
  - **What building it settled (step 6):**
    - A timeout in seconds of less than a millisecond is for ever. Some servers read it as 0, which blocks without
      end, and a deadline must never cut a wait short.
    - A timeout the server refuses at once (not a number, NaN, negative, out of range, or an unknown XREAD option
      or no STREAMS) adds nothing. So does a hexadecimal float, which the server's `strtold` accepts and std's
      `parse` does not; that one gap is known.
    - A timeout past 10¹² ms (31 years) is for ever, which keeps every sum far from overflowing a `Duration`.
    - A pipeline adds its blocking commands' timeouts, since they wait in turn.
    - The unit test builds, from each server's COMMAND DOCS, a command whose timeout is 1.5 s at the documented
      place, and the scripted server's `Patient` step answers it only if the connection waited that long. All 85
      rows pass, and every name in every server's `ACL CAT blocking` is documented by one of them.
    - Live: "a call that outlasts `command_timeout`" is a SET held by `CLIENT PAUSE … WRITE` from another
      connection, since a blocking command now has its own deadline.
- **Transactions:** `transact(pipeline:)` writes MULTI, the commands and EXEC in one write. It reads every reply before
  it decides, so the connection stays in step with the server.
  - Its outcome is `TxOutcome { Committed(Replies), WatchConflict }`. EXEC's null is `WatchConflict`, an outcome
    rather than an error (go-redis `TxFailedErr`, redis-py `WatchError`, redis-rs `None`).
  - EXECABORT is `Server`, carrying the first queue-time error.
  - The deadline is `command_timeout` alone, since nothing blocks inside MULTI.
  - `watched(watch:, body: TxBody, attempts:)` retries a bounded number of times, which the caller states. Peers retry
    without bound (redis-rs, redis-py) or leave it to the caller (go-redis).
  - **What building it settled (step 7):**
    - `watched` takes the WATCH command itself (`cmd"WATCH ${a} ${b}"`), not `keys: RedisArg`. A list of keys needs
      the `DynamicArray` adapter, which KRD-7 blocked then, and a command carries binary keys as they are. A list hole
      works there now too: `cmd"WATCH ${keys}"`.
    - A body is a `TxBody`, as postgres's `TransactionBody` is (no closures): `build(ref Connection conn, ref
      Pipeline tx)` reads over the connection while the keys are watched, and fills the pipeline. A body that fails
      gets UNWATCH, and its error is returned.
    - WATCH or UNWATCH inside the pipeline is `Usage` before anything is written, as the server refuses them inside
      MULTI. MULTI, EXEC and DISCARD joined the refused commands in this step, so a connection is never left inside
      a transaction.
    - A reply other than `+OK` to MULTI or `+QUEUED` to a command is `Unexpected`, and closes the connection.
    - An error to MULTI itself (a user who may not run it) is `Server`, with that error. The server then ran each
      command on its own, as MULTI was not in force; every client shares this, and the ACL is the fix.
- **Scripts:** `Script` computes its SHA-1 client-side (`std::digest::sha1`), and `ScriptCall` carries the call.
  - `eval` sends EVALSHA, and on NOSCRIPT, EVAL (go-redis's way; redis-py and redis-rs SCRIPT LOAD first). That is
    safe, because NOSCRIPT means the script never ran.
  - A read-only script uses the `_RO` forms (7.0+).
  - Inside pipelines and transactions, EVAL (redis.io: NOSCRIPT cannot be handled there).
  - FCALL needs nothing special.
  - **What building it settled (step 8):**
    - A script's keys and arguments are added as `addKey`/`addArg` (a `RedisArg`) and `addKeyBytes`/`addArgBytes`,
      each a whole argument. One refused while it is added (a NaN) refuses the call before anything is written.
    - Only NOSCRIPT is answered with EVAL; any other answer to EVALSHA, an error included, is EVALSHA's.
    - A read-only script is never sent as plain EVAL: on a server before 7.0 the `_RO` form is refused, which
      honours what the caller asked for. Valkey 7.2 has the `_RO` forms, as Redis 7.2 does.
    - The SHA-1 equals SCRIPT LOAD's on all eight servers (captured), and live under both protocols.
- **SCAN** is a page API, not an Iterator: an iterator cannot borrow a Connection, has no error channel, and would need
  a hand-back.
  - `Scan.next(conn:)` returns every page, empty ones included, so no call makes an unbounded number of round trips.
  - The cursor is opaque bytes (Valkey 9.1's CLUSTERSCAN has string cursors, and Lettuce keeps a String).
  - Repeats are documented.
  - **What building it settled (step 9):**
    - The shape is `Scan.keys()`, `setMembers(key:)`, `hashFields(key:)` and `sortedSetMembers(key:)`, with the
      options `matching(pattern:)`, `countHint(count:)`, `ofType(typeName:)` and `noValues()`. `next(conn:)`
      returns the page's items as a reply, so they read with `reply::<T>` as any reply does.
    - Keys and patterns are `RedisArg`s, so a key as bytes is a `DynamicArray<uint8>`.
    - An option a scan does not have (TYPE on a key's members, NOVALUES off HSCAN, COUNT below 1) is `Usage`,
      before anything is written. A reply that is not a cursor and a page is `Value`, and the connection goes on.
      `next` after the last page is `Usage`.
    - NOVALUES is answered by Redis 7.4 and later and Valkey 8.1 and later in the matrix; the others refuse it.
    - Live, under both protocols: 1000 keys over many pages with MATCH and COUNT, TYPE, 1000 set members, 500 hash
      fields and 300 sorted-set members all come back whole.

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


### Phase 4

Drawn up 2026-10-13 (see "Phase 4: where to start" for the sources and the proposals, which hold unless this section
says otherwise). Step 0's repros, run 2026-10-18 on v0.9.667 and cstar's 0.9.668, debug and release, confirmed the kama
facts underneath; they are listed at the end.

- **A `Subscriber` holds its `Connection` in a `DynamicArray` of zero or one,** as `Opener` holds its dialer. A
  field cannot be given out, so `release()` pops it. A second `release()` is `Usage`, and every later call is
  `Closed`. A subscriber dropped while it holds a connection closes it, through the connection's destructor.
- **Channel and pattern names are bytes, as payloads are.** `Message` has `channel()`, `pattern()` and `payload()` as
  bytes, and `channelText()`, `patternText()` and `text()`, which refuse bytes that are not UTF-8 (`Value`).
  Subscribing takes a `RedisArg`, a `DynamicArray<uint8>` included, so a channel can be any bytes, and a reply must
  give them back whole.
  - redis-py gives bytes (unless `decode_responses`), and go-redis's Go strings hold any bytes.
  - redis-rs 1.7.1's `get_channel_name()` turns a name that is not UTF-8 into `"?"` (connection.rs:2302). That
    silent replacement is what this decision avoids.
- **`release()` drops what was not read.** It unsubscribes from everything, reads until every count is 0, and hands
  the connection back. Messages queued or arriving meanwhile are dropped. The caller chose to stop listening, and a
  caller who wants everything reads `next` until it gives None first. go-redis's `Close` and redis-py's `close`
  drop them too.
- **`next` with nothing subscribed and nothing queued is `Usage`,** never a wait with no end. A server's own
  `sunsubscribe` of the last shard channel would otherwise leave `next(timeout: None)` waiting for ever. The
  `Unsubscribed` delivery comes first, so the caller learns why.
- **Two kinds of waiting, two outcomes.**
  - `next`'s time passing is an answer: None. The connection stays open, and a message half-read stays in the
    reader for the next call (postgres's `waitForNotification`).
  - A (un)subscribe's confirmations, or a PING's answer, that do not come by `command_timeout` close the
    subscriber, as `call` closes on a timeout: the server's state is no longer known.
  - `next(timeout: Some(zero))` polls: it reads what has arrived, and waits for nothing more.
- **An error reply in place of confirmations is `Server`, and the subscriber goes on.** The server refused the whole
  command (NOPERM, CROSSSLOT, MOVED, `unknown command` for SSUBSCRIBE on 6.2), so no confirmation will come, and the
  kept sets are unchanged.
- **A RESP3 push that is not pub/sub** goes to the connection's set-aside pushes (bounded), and comes back with it
  from `release()`. On a subscriber that can be a module's push, or an `invalidate` that another connection's
  `CLIENT TRACKING … REDIRECT` sends here.
- **Invalidations are never deliveries, under either protocol.** Under RESP2, a redirected invalidation is a
  `message` on `__redis__:invalidate` whose payload is an array of keys, or a null for a flush (captured on all
  eight servers: `tracking-redirect/2`, `tracking-flush/2`). It is the only message whose payload is not a string,
  and it is RESP2's form of RESP3's `invalidate` push. So it is set aside on the connection as that push is, and a
  `Message`'s payload is always bytes. go-redis gives such a payload a field of its own (`PayloadSlice`), and redis-rs
  keeps every payload as a `Value`. Here, client-side caching is 0.3.0's, and until then an invalidation has no
  reader of its own.

- **What step 0's repros showed** (in the session's scratchpad; each on v0.9.667 and 0.9.668, debug and release):
  - A resource taken by value into a `DynamicArray` of one, used in place through `held[0]`, and handed back by
    `pop()`; a second pop is None.
  - A `friend` grant from one type to another type's private and public methods, across files, reaches private
    fields and methods (`friend r0::Holder::exchange[secret, shut, setAside];`).
  - A `Delivery` enum with a resource payload and a bytes payload, matched with `give`, and handed out of a queue
    with `remove(index: 0)`.
  - `next(timeout: Optional<Duration>)` returning `Result<Optional<Delivery>, E>`.
  - A ctor returning `Result<Holder, E>` that refuses a value it was given hands it to a local first.
  - A type cannot be named `Err` (a language name).
