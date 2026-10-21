# Roadmap

Where this is, 2026-10-21: phases 0 to 6 and 7a are done, on kama v0.9.707 (the floor, CI's pin and the newest tag;
cstar's newest build is `0.9.713+g03d52a6b`). **0.1.0, a complete client for one server, is published** (2026-10-19,
from `146a4d8`). **0.2.0, Cluster and Sentinel, is published** (2026-10-21, from `f9b7d38`). **Phase 7b, for 0.3.0, is
under way:** "Phase 7b: where to start", just below, is its session plan (drawn up 2026-10-21, the maintainer's
decisions in it), and "Parity with the peers" (surveyed 2026-10-21) is why the releases after it hold what they
hold. "Phase 6: where to start" has what each step of 0.2.0 did.
- The floor moved from v0.9.667 to v0.9.690 on 2026-10-20 (the maintainer's word), which closed KRD-11: from 0.9.684
  kama requires `fn uint8 main()` and every earlier tag refuses it. The ten `main`s, the README's programs and the live
  program's channel `send` (0.9.680) took the new forms.
- It moved again, to v0.9.707, on 2026-10-21, when that tag came out: it closed KRD-9 (`View.copyWithin`, so the
  reader slides its unread bytes in one call) and KRD-12 (an arm may end in `panic`, so the test programs' `stop` went).
  0.2.0 carries no workaround for kama, and a consumer moves the floor once, not twice. Since 0.9.706 `string.find`
  has another type, which nothing here calls. `@kama/tls` 0.1.6 (2026-10-20) builds there, and the package needs
  `^0.1.6`; its own tests are green on the tag.
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
- Pub/sub is in (phase 4): `Subscriber` under RESP2 and RESP3, sharded pub/sub with the server's own `sunsubscribe`,
  and a connection's bounded set-aside pushes (`takePushes`, `droppedPushes`); `CLIENT TRACKING` and `CACHING` are
  refused until 0.3.0. The unit suite replays each server's pub/sub captures under both protocols (two cluster nodes
  included), every order of an unsubscribe-all among them; the live suite runs on all eight servers.
- TLS is in (phase 5): `rediss://` and `valkeys://`, verified by default (the chain and the name, against the system's
  roots), `tls_verify` `full`, `chain` or `none`, a CA, a client certificate, `tls_server_name`, over any transport,
  from `@kama/tls` 0.1.3. The unit suite runs Mbed TLS as the scripted server; the live suite checks each server's
  TLS ports, SNI on the wire, a silent handshake and both wrong ports.
- Reconnection is in (phase 7a): a lost connection is made again by its next call and nothing is sent twice; a call
  finds a close that came while idle before it writes; a redial waits out a restart (`reconnect_timeout`); session
  state is refused or recorded (`select`, `authenticate`); a lost WATCH holds the transaction back; a subscriber
  subscribes again and says `Reconnected`. Live, a restart (`SHUTDOWN NOSAVE`, the server back half a second later),
  kills and a pub/sub flood, on all eight servers; eight examples run on every one; every step proven by mutation
  (`tools/mutate.sh`, 79 mutations, all caught).
- Cluster and Sentinel are in (phase 6): a `Connection` and a `Subscriber` through sentinels (`redis-sentinel://`),
  as Sentinel's client specification says; `Cluster` with routing by every server's own command table and tips,
  MOVED, ASK and the waits, pipelines, transactions and `watched`, replica reads, a cluster SCAN and
  `ClusterSubscriber`. `tools/redis.sh --topology cluster|sentinel` runs both on all eight servers; the vectors come
  from `tools/gen-topology-vectors.sh` and `tools/gen-command-table.sh`; the live suite drives failovers, a sleeping
  primary, restarts, resharding and the atomic migrations.
- Gates (0.2.0): `tools/test.sh` is green, debug and release, the examples built, on kama v0.9.707 (the floor and CI's
  pin); `tools/test-integration.sh` on all eight servers, alone, under Sentinel and as a cluster;
  the README's programs and the examples live. Every step proven by mutation (`tools/mutate.sh`). Published 2026-10-21.
  - `tools/test.sh` installs the manifest's dependencies first: a fresh checkout has no `.kama/deps`, and CI's unit
    jobs failed on the phase 5 push until it did (2026-10-18).
- No gap is open here (KAMA_GAPS.md). KRD-9 (std had no in-place copy, and 0.9.675 refused the reader's copy between
  two windows of its buffer) and KRD-12 closed with v0.9.707; KRD-10 (an application named like a dependency's module
  broke that dependency's imports) is refused by name since 0.9.693; KRD-11 closed with v0.9.690. KRD-7, KRD-8
  and KPG-38 were fixed upstream and tagged in v0.9.573 (2026-10-13): the floor and CI pin moved there, `RedisArg`
  gained its bytes, list and Uuid adapters, the one-conversion-file rule is gone, and the reply reader implements
  0.9.569's `Deserializer` (`DeErrorKind`, a missing field named by its path).

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
| 4 | Server push. Pub/sub on a `Subscriber` that owns its connection, under RESP3 and RESP2 (every peer gives pub/sub its own connection). Sharded pub/sub. **0.1.0.** Client-side caching (`CLIENT TRACKING` invalidations, RESP3, a cache per connection) moves to **0.3.0**. See "Phase 4: where to start" | **done** |
| 5 | TLS through `@kama/tls`: `rediss://`, verification of the chain and the host name, client certificates, SNI. **0.1.0**. See "Phase 5: where to start" | **done** |
| 6 | Topologies. Cluster: the slot map from `CLUSTER SLOTS`, `MOVED` and `ASK`, commands that span nodes by the server's command tips, reads from replicas, sharded pub/sub that follows its slot. Sentinel: discovery and failover. A multi-node `tools/redis.sh` topology for both. **0.2.0**. See "Phase 6: where to start" | **done** |
| 7a | Reconnection (a connection's, and a subscriber's resubscribing), examples, hardening (a server restart, bounded memory under load), docs. **0.1.0**. See "Phase 7a: where to start" | **done** |
| 7b | Scale. A pool shared across isolates (`@kama/postgres`'s phase 8 S3 and S4 are the model), client-side caching (phase 4's research and decisions), a credentials provider with live re-AUTH, and hardening across a failover. **0.3.0**. See "Phase 7b: where to start" | **in progress** |
| 8 | Typed commands. A method per command, generated by script from every server's `COMMAND DOCS`, beside `cmd"…"`. The Redis 8 modules (JSON, the Query Engine's `FT.*`, TimeSeries, the probabilistic types) loaded in the matrix's servers, in the command table, and read into typed replies; Valkey's modules beside them. **0.4.0**. See "Parity with the peers" | |
| 9 | Integration, placed in releases as each is planned: a hook contract for instrumentation, so an OpenTelemetry package can plug in; Valkey's extras (replica reads in the client's availability zone, `CLIENT CAPA redirect`, `CLUSTERSCAN`); smart client handoffs and client-side Active-Active failover, for Redis Cloud and Redis Software; Windows, once `@kama/tls` has it | |
| — | Publish 0.1.0 after 4, 5 and 7a; 0.2.0 after 6; 0.3.0 after 7b; 0.4.0 after 8. Each only on the maintainer's word | 0.1.0 **published** (2026-10-19); 0.2.0 **published** (2026-10-21) |

### The release plan (decided by the maintainer, 2026-10-18; 0.3.0's credentials provider, 0.4.0 and phase 9 on 2026-10-21)

The roadmap is unchanged; its releases are phased. Each release is held to the same bar as the rest:
- every form it covers is honoured or refused;
- every failure path is tested against the scripted server;
- the whole matrix passes live, debug and release.

Anything not in a release yet is refused clearly rather than half there. Today a cluster's MOVED comes back as
`Server` with its code, and `CLIENT TRACKING` is refused (phase 4, step 2).

- **0.1.0, a complete client for one server:**
  - what phases 0–3 built;
  - pub/sub and sharded pub/sub (phase 4, without client-side caching);
  - TLS (phase 5);
  - reconnection, examples, hardening and docs (phase 7a).

  The order: phase 4 (done 2026-10-18), then 5 (done 2026-10-18), then 7a (done 2026-10-19), then the release
  (published 2026-10-19). The first publish stopped at the registry's `kama check` with cstar's 0.9.675, which
  refused the reader (KRD-9); `146a4d8` fixed it, and that is what is published. The registry checks with cstar's
  newest build, not CI's tag: gate on that build before calling a release ready.
- **0.2.0, topologies:** Cluster and Sentinel (phase 6). Published 2026-10-21, from `f9b7d38`, on kama ≥ 0.9.707.
- **0.3.0, scale:** a pool shared across isolates, and hardening across a failover (phase 7b), client-side caching
  (phase 4's research and decisions, kept below), and a credentials provider: a contract called at each connect, and
  live re-AUTH when its credentials change (moved here from "Carried" on 2026-10-21; seven of the eight peers have one).
- **0.4.0, typed commands:** phase 8. A method per command and the Redis 8 modules, typed, were the largest day-to-day
  gap the peer survey found: every peer has a typed API, and the four clients Redis maintains have every module.
- **After 0.4.0:** phase 9's items, each placed in a release when it is planned.
- **Carried, to be placed in a release:**
  - `Command.addFields(value: Serializable)` (HSET from a struct);
  - a `<Map>` adapter;
  - measuring the typed read of `DynamicArray<uint8>`, byte by byte, before asking cstar for a bulk read;
  - postgres's seeded mutations of every scripted reply (its phase 8 S2d: each must end in an error, never a panic),
    beside the resp reader's hostile vectors here.
- **The published description** (`kama.json`'s, on the registry) names cluster and sentinel, which come in 0.2.0. A
  published version cannot change; 0.2.0 makes it true.
- **Each release** (AGENTS.package.md, "Publishing"):
  - the CHANGELOG's Unreleased section becomes the version, kept in step with `kama.json` and `libraryVersion()`
    (`tools/test.sh` checks the two);
  - CI green on the pinned tag;
  - `kama publish kama.json --dry-run` lists no certificates and no agent files;
  - `./ops publish ../kama-redis/kama.json` from `../kama-registry`, only on the maintainer's word, since a version is
    permanent.
- **Neighbours, as of 2026-10-21:**
  - `@kama/tls` 0.1.6 is on the registry, the first release that builds on kama 0.9.696 and later; this package needs
    `^0.1.6`, and every lock pins it. Its library's floor is kama 0.9.523, and its tests run on v0.9.690 and are green
    on v0.9.707. Its next phases are Windows, WebAssembly, then session resumption (TLS 1.3, then 1.2), which a redial
    here could use once it ships.
  - `@kama/postgres` is in its phase 8: S3 (a pool shared by isolates) and S4 (its maintenance) are done, on kama
    0.9.690, and S5 is next. 0.3.0's pool here (phase 7b) starts from them.
  - `@kama/http` is seeded, with nothing usable yet. The UI packages (`ui`, `rmlui`, `freetype`) do not touch this one.

## Phase 7b: where to start

The session plan, drawn up on 2026-10-21 from primary sources, for 0.3.0. It replaces the outline 0.2.0's session left.
- **The maintainer chose three of its decisions** (1, 2 and 4), and left three to this plan's best production answer
  (3, 5 and 6). Decision 5 was asked as "the best and most secure approach".
- **A review of the draft against this code** (H1–H10 below) settled decision 7.

The sources:
- **The model:** @kama/postgres's pool, its phase 8 S3 and S4, at `091ee50`:
  - `src/pool/pool.kama` and `connector.kama`;
  - its ROADMAP's S3 and S4 decisions;
  - `pool_test.kama`, unit and integration;
  - `tools/mutations/s3.json` (27) and `s4.json` (44).

  Its S5 was mid-edit in another session and is not used. Postgres runs on kama 0.9.690.
- **The peers, at the survey's tags:** redis-py 8.1.0, go-redis v9.23.0, Jedis 8.0.2, node-redis redis@6.3.0, rueidis
  v1.0.79, Valkey GLIDE v2.5.3 (its pool is on unreleased main), and Lettuce 7.9.0 in part.
- **The servers:** probes P1–P5, run live on all eight in throwaway containers; phase 6's failover captures for P7.
- **kama:** step 0's repros R1–R12, on v0.9.707 and cstar's `0.9.713+g03d52a6b`, debug, release and sanitized;
  cstar's `channel.kama`, `poll.kama` and `atomic.kama`; its ROADMAP's KR-3 and KR-226.

The bar is 7a's and phase 6's:
- every form honoured or refused;
- every failure path tested against the scripted server;
- the whole matrix live, debug and release, standalone, under Sentinel and as a cluster;
- every step proven by mutation.

### What the sources showed

Short names: PY is redis-py, GR go-redis, JE Jedis, NR node-redis, RU rueidis, GL GLIDE, LE Lettuce, and PG @kama/postgres.

- **A pool, or one multiplexed connection.**
  - **Pools:**
    - PY (`ConnectionPool`, client.py:869-926);
    - GR (`internal/pool/pool.go`);
    - JE (commons-pool2, `ConnectionPool.java`).
  - **Multiplexed:**
    - NR: one pipelined socket per client, and `RedisClientPool` for exclusive use (pool.ts:112, `execute` 472-558);
    - RU: auto-pipelined wires, four to a server (rueidis.go:220-223). Blocking commands and `Dedicated` go to a pool of
      1024 (mux.go:235-265);
    - GL 2.5.3: one connection per node and no pool. WATCH is not tracked (mod.rs:833-836);
    - LE: one connection, and commons-pool2 on opt-in.
  - **GR's auto-pipelining** (9.22) and full duplex (9.23) are opt-in and experimental (redis.go:2825-2880,
    autopipeline.go:89-104). Its stateful commands go to a pooled connection (autopipeline.go:1849-1873).
  - **Here** (R10, an Apple M4), as KRD-14 says, the hop is not what stops a multiplexer. An isolate cannot wait on a
    socket and a channel at once.

    | | each |
    |---|---|
    | a channel round trip between isolates | 2.5 µs |
    | a PING, one at a time, through podman's forwarder | 220 µs |
    | the same, inside the container | 70 µs |
    | a PING pipelined 100 at a time | 2.4 µs |
- **A cluster.**
  - GR, PY and JE keep a pool per node inside the cluster client (osscluster.go:517-545, cluster.py:2499-2530,
    JedisClusterInfoCache.java:41). NR and RU keep a multiplexed client per node.
  - One pooled `Cluster` here costs about 320 KiB resident and a link to each primary it uses. R11: 64 of them on a
    three-primary cluster held 21.9 MiB and 256 sockets.
- **Sentinel and a pool.**
  - GR, JE, NR and RU subscribe to `+switch-master` and purge or replace pooled connections (sentinel.go:660-676,
    JedisSentinelPool.java:343-415, sentinel/index.ts:1700-1712, sentinel.go:479-575).
  - PY finds the master again at connect, and drops stale connections at release (sentinel.py:121-128).
  - Here, phase 6's captures (`promoted-let-go`, `demoted-let-go`) show Sentinel letting every idle client of both
    nodes go, with no bytes. So 7a's redial finds each pooled connection's loss and asks the sentinels again (phase 6,
    decision 4).
- **What a release puts back.**
  - JE's legacy pool sends DISCARD or UNWATCH on return (Jedis.java:364-383) and SELECT on borrow
    (JedisFactory.java:183-188). Its new `ConnectionPool` puts back nothing (ConnectionFactory.java:170-218).
  - NR's pool puts back nothing (pool.ts:560-579). Its Sentinel leases send RESET and the whole handshake again when the
    database, a WATCH, MONITOR or pub/sub changed (index.ts:2112-2163). It is the only peer that sends RESET.
  - PY puts back nothing, so a SELECT leaks to the next caller (core.py:1652-1657). Its pipeline's reset sends UNWATCH
    (client.py:1854-1876).
  - GR puts back nothing (pool.go:1380-1568). Its init pipeline sets every connection's state, and its sticky `Conn`
    leaks state, by its own words (redis.go:2679-2696).
  - RU's `Dedicated` sends CLIENT TRACKING OFF, the unsubscribes and DISCARD, but no UNWATCH (pipe.go:1055-1065).
  - GL main (unreleased), on a dirty release: DISCARD or UNWATCH, the unsubscribes, TRACKING OFF, SELECT and SETNAME
    back. A failure discards the connection (pool.rs:1380-1530).
  - **Here, a lease can leave only three things:** a database (`select`), a WATCH, and a re-authentication
    (`authenticate`). `call` refuses every other command that changes session state, and the table is checked against
    every server's `ACL CAT connection`.
  - **P4:** UNWATCH and SELECT 0 in one write answer `+OK` twice, on all eight, under both protocols.
- **A cache with a pool.**
  - **One per client, shared by every connection,** all with plain `CLIENT TRACKING ON`:
    - PY (connection.py:3011-3028);
    - GR (`CSCStrategySharedTracking`);
    - JE (ConnectionFactory.java:98-101);
    - NR (`BasicPooledClientSideCache`, pool.ts:323-335).
  - **When one connection drops:**
    - PY, JE and NR flush the whole cache (connection.py:1734-1737, CacheConnection.java:108-112, index.ts:2240-2246);
    - GR evicts that connection's entries (`EvictByConn`, csc_integration.go:738-812). It caches on DB 0 only, and not
      at all with a credentials provider (options.go:458-489).
  - **RU keeps one per connection,** OPTIN, 128 MiB each (pipe.go:143-147, 187-192). A key always goes to the same wire
    (mux.go:345-353).
  - **GL 2.5.3** uses BCAST or a TTL alone, with no pending marker (multiplexed_connection.rs:897-933).
  - **P5, on all eight:**
    - HELLO 3 and `CLIENT TRACKING ON OPTIN` go in one write;
    - `CLIENT CACHING YES`, MULTI, PTTL, GET and EXEC answer `*2 [:ttl, value]`: `:-1` with no TTL, `:-2 _` for a
      missing key;
    - a connection's own write gets its reply, then the push;
    - another client's write, then this client's PING, gives the push before `+PONG`;
    - FLUSHALL is `>2 invalidate _`;
    - CACHING without tracking is an error;
    - RESP2 takes TRACKING with `+OK`, and delivers nothing (phase 4).
- **Credentials.**
  - **Every peer asks its provider at each connect,** and sends HELLO AUTH: PY connection.py:1131-1176, GR
    redis.go:864-1054, JE Connection.java:690-710, NR index.ts:882-966, LE RedisHandshake.java:208-270, RU
    pipe.go:152-176.
  - **How a change reaches a live connection:**
    - PY: an idle connection at once, under the pool's lock; a busy one on release (connection.py:3431-3442);
    - GR marks it, and re-AUTHs once it is idle, without the pool's lock (pool_hook.go:99-215);
    - JE: in an eviction pass, and on return (ConnectionPool.java:71-91);
    - NR at once (index.ts:854-880);
    - LE only with `ON_NEW_CREDENTIALS`, which is off by default (ClientOptions.java:66);
    - RU on a per-connection timer from `RefreshAfter` (pipe.go:375-393);
    - GL takes its IAM token at the next reconnect (mod.rs:1041-1064).
  - **A refused re-AUTH:** RU closes the connection (pipe.go:822-848). GR keeps it unless the connection is bad
    (redis.go:832-855); PY raises and keeps it; NR and LE report it and keep it.
  - **Every peer re-authenticates with plain AUTH.**
  - **P1, on all eight:** AUTH, HELLO 3 AUTH, and AUTH as another user each keep `CLIENT TRACKING` and its
    invalidations.
  - **P2:** a refused AUTH (a wrong password, a disabled user, HELLO AUTH) leaves the connection logged in as before
    (`ACL WHOAMI`).
  - **P3:** of `ACL SETUSER … resetpass >new`, `… >new`, `… off`, `… -@all +ping` and `ACL DELUSER`, only DELUSER
    lets the user's idle client go. The rest leave it working.
- **Pool defaults, from source:**

  | | size | waiting for one | idle | lifetime | at checkout |
  |---|---|---|---|---|---|
  | GR | 10 × GOMAXPROCS | read timeout + 1 s (6 s) | 30 minutes | none | no PING (options.go:704-762, pool.go:2085-2145) |
  | PY | 100, an error when full | — | — | — | — |
  | PY blocking pool | 50 | 20 s | — | — | (connection.py:2975, 3520-3536) |
  | NR | 1 to 100 | 3 s | 3 s | — | (pool.ts:205-210) |
  | JE | commons-pool2's (8, not verified) | — | tested every 30 s | — | (ConnectionPoolConfig.java:8-14) |
  | RU | `BlockingPoolSize` 1024 | — | — | no jitter | (rueidis.go:205-235) |
  | PG | max(4, cpuCount) | 30 s | 1800 s; health 60 s, ping 5 s | 3600 s, 90 s of jitter | — |
- **This code:**
  - **H1.** `Scan` tells links apart by `Connection.generation()`, a per-connection count from 0 (scan.kama:105-111;
    connection.kama:87, 1059, 1203). Two pooled connections both read 0. So a scan continued on another lease sends its
    cursor to another link, perhaps another server, without a word. It is phase 6's decision 9 again.
  - **H2.** `authenticate` after a lost link redials with the old credentials first (connection.kama:488-492, then
    1149). A revoked password ends in a final WRONGPASS, and the new credentials never apply.
  - **H3.** A release must not redial. `settle()` ends in `lostIdle`, which answers OK whenever the connection can
    redial (connection.kama:1089-1130). The put-back checks `live` itself.
  - **H4.** A lease can leave client-side state that no write covers:
    - the command timeout (`setCommandTimeout`, 824-828);
    - `watchLost` (1071, 613): the next lease's first transaction would answer a spurious `WatchConflict`;
    - the set-aside pushes (795-821).
  - **H5.** `NodeLink.close()` closes for good (cluster.kama:118, connection.kama:766), so a cluster's put-back pops a
    lost link instead. A `TxBody` gets a node's `ref Connection` (cluster.kama:117) and may call `select` or
    `authenticate`, so a cluster's put-back looks at every link.
  - **H6.** `Cluster` refuses `reconnect=off` (cluster.kama:1300). A pool of Clusters therefore keeps redialing within
    a lease, and 7a's note that the pool would use `reconnect=off` (its decision 1) does not hold.
  - **H7.** `recourseFor` must treat a credentials failure as final. Otherwise a cluster calls its provider in a loop
    within `reconnect_timeout`.
  - **H8.** A RESP2 subscriber cannot AUTH while subscribed: RESET, QUIT, PING and the (un)subscribes only.
  - **H9.** A `Config` is `Copyable` (config.kama:207-245), so it cannot hold an `Owned<…>` as a plain field. R1 shows
    that a 0/1 `DynamicArray<Owned<Credentials>>` that forks on copy keeps it `Sendable` and `Copyable`.
  - **H10.** `tools/mutate.sh` had a fixed 900 s timeout, and a pool mutant can deadlock. Postgres's per-mutation
    `timeout` is ported, and 7b-s0 proves it: a run cut off after 1 s is judged by what it printed.
- **kama:** step 0's repros, in the session's scratchpad, on v0.9.707 and `0.9.713+g03d52a6b`, debug and release.
  - **R1, R2, R9:** a `Copyable`, `Sendable` config holds its provider as a 0/1 `DynamicArray<Owned<Credentials>>`, and
    its copy constructor forks it.
    - `copy this` works in a `const fn` (`forNode`'s shape).
    - The provider moves out into an opener with `pop()`.
    - The config crosses to another isolate.
  - **Found on the way:** KRD-13. `kama check` takes an `Optional<R>` where a resource `R` is wanted, and only clang
    refuses it.
  - **R3–R8,** all clean under AddressSanitizer and UBSan on both compilers:
    - `Slot { Idle(Held, …), Empty }` over `Held { One(Connection), Whole(Cluster) }`, on a bounded channel;
    - `Shared<Home>`:
      - two leases dropped in turn;
      - a nested acquire inside a `borrow` of a lease's connection (KR-211's shape);
      - a share joined in another isolate with a lease out;
      - the pool dropped before its lease;
      - a cluster lease;
    - a `Channel<Owned<Dialer>>`;
    - a consumer's `case _` over a new `@nonExhaustive` variant.
  - **R5:** a grant reads `friend <accessor>[<my members>]`. `Connection` grants
    `friend redis::pool::Core::release[putBack];`, a method of a type its module does not export.
  - **A lease's `conn()` cannot hand out a `ref` into an enum payload.** So a `Lease` holds a `Connection` and a
    `ClusterLease` a `Cluster`, and `Held` wraps either only while it waits in the pool.
  - **R12:** `cpuCount()` answers `int32`.

### Decisions

**1. A pool, not a multiplexed connection** (the maintainer's choice, 2026-10-21). It is postgres's S3 and S4, copied
and not depended on.
- **The mechanism:**
  - two bounded channels;
  - a lease that releases only when dropped;
  - a maintenance isolate per pool.
- **A lease gives a plain `Connection`,** so every kind of command works through it, blocking ones and WATCH included.
  Pools are what PY, GR and JE use, and every multiplexing peer still keeps a pool for those commands.
- **The maintainer wants the optimal design once kama allows it.** So KRD-14 (fibers, or a channel a `Poller` can wait
  on) and KRD-15 (`Locked<T>`) say what each would unlock, for cstar to rank them. When one lands, this package adds a
  multiplexed client or a shared cache beside the pool.

**2. On a cluster a lease holds a whole `Cluster`** (the maintainer's choice).
- Phase 6 is reused unchanged: pipelines across nodes, transactions, `watched` and SCAN.
- At most maxSize × nodes connections, the same bound as the peers' pool per node.
- The README states R11's cost.

**3. A release puts back only what changed,** at the release (postgres's rule: a failure is the releaser's). The
maintainer left this to the production answer, and this is that answer, not a stopgap. In order:
1. a zero-time settle;
2. discard the connection if its link is lost, if `authenticate` was called by hand, or if the caller closed it;
3. reset what is local:
   - the command timeout;
   - `watchLost`;
   - the set-aside pushes, dropped and counted in `droppedPushes`;
4. one write of UNWATCH (if a WATCH is in force), then SELECT (if the database changed), bounded by the command
   timeout;
5. discard the connection if a reply is not `+OK`.

There is no RESET (NR alone sends it). It logs the connection out and drops its name, protocol and tracking, and it
needs a second handshake.

**4. One cache per connection** (the maintainer's choice; rueidis's design and phase 4's decision).
- **Recorded on the configuration.** `Config.setCache(CacheConfig)` records it, so the handshake's one write carries
  `CLIENT TRACKING ON OPTIN` and every redial restores it (7a, decision 5). Phase 4's `enableCache` method goes.
- **When it is flushed:** on every rule phase 4 named, and on a re-AUTH as another user. P1 shows the server keeps
  tracking across it, so values read as one user would otherwise be served to another.
- **Each lease's first cached hit makes a round trip first** (PING). It extends phase 4's rule: P5 shows another
  client's invalidation lands before the PING's reply, and a write made through another pooled connection would
  otherwise be read stale.
- **A shared cache waits for KR-226** (KRD-15).

**5. Credentials are pulled, with a refresh time, and fail closed.** This was asked as "the best and most secure
approach". The model is rueidis's.
- **The contract:** a provider is a `Credentials` contract, set with `Config.setCredentials`. A Config's copy holds a
  fork (R1).
- **Its answer:** a `Login`, holding the user, the password and an optional `refreshAfter`.
- **When it is asked:**
  - at every connect and redial, for the data servers;
  - the sentinels keep `setSentinelAuth`, and `forSentinel` drops the provider;
  - once the refresh time passes, the next call re-authenticates first, with AUTH in its own round trip, and the pool's
    maintenance does the same for an idle connection. A token never lapses on a live connection.
- **Where it is kept:** `establish` moves the provider into the `Opener`, so the kept `Config` holds no password.
- **On failure:** a provider error or a refused AUTH closes the link, and the call returns `RedisError::Credentials`,
  meaning nothing was sent. At a redial it is `Reconnect` holding that cause, which is final.
  - P2 shows a refused AUTH leaves the old identity in force, which is what GR, PY, NR and LE then keep running.
  - P3 shows the server lets a disabled user's clients run on, so closing on the refusal is what ends them.
- **Refused:** a URL password or `setAuth` together with a provider, and `authenticate` on a provider's connection.
- **It fixes H2.**
- **A subscriber:** a RESP2 subscriber redials at its refresh time and delivers `Reconnected` (H8). A RESP3 one
  re-AUTHs in place.

**6. A lease redials within the lease** (left to this plan), as a lone `Connection` does, and a `Cluster` requires it
(H6).
- The pool never redials on its own time: a connection lost at release is closed, and its place freed.
- 7a's decision 1 is revised here.

**7. What the review settled.**
- **The Scan fix (H1):** each link draws a random identity, and a scan carried to another link ends with an error. The
  CHANGELOG lists it under Fixed.
- **A cluster's put-back (H5):**
  - a lost node link is popped, not closed;
  - SELECT goes back per node;
  - a hand `authenticate` through a `TxBody` discards the `Cluster`.
- **`recourseFor` takes `Credentials` as final** (H7).
- **No PING at acquire** (GR): acquire makes a zero-time check of an idle connection, and the maintenance PINGs idle
  ones.
- **A new contract, `PoolDialers { another(); fork(); }`,** for a caller's dialers. `Dialers` does not change, since a
  new member breaks every implementer.
- **CLIENT TRACKING and CACHING stay refused in `call`,** with words naming `Config.setCache`.
- **No URL keys:** the pool, the cache and the provider are set in code (PG).

**8. Defaults.**

| | default | basis |
|---|---|---|
| maxSize | max(4, cpuCount) | PG |
| lifetime | none | GR, RU |
| lifetimeJitter | 90 s | applied only when a lifetime is set |
| acquireTimeout | 6 s | GR's derivation, the command timeout + 1 s |
| minIdle | 0 | |
| idleTimeout | 30 minutes | GR, PG |
| healthCheck | 60 s | |
| pingTimeout | 5 s | |
| a cache | 10 000 entries and 16 MiB per connection | the peers' 10 000; RU's 128 MiB × maxSize is too much |

**9. The shape.**
- **In `redis`:**
  - `Credentials` (a contract: `login(server:)` → `Result<Login, RedisError>`, and `fork()`), and `Login`;
  - `CacheConfig` and `CacheStats`;
  - `Config.setCredentials`, `hasCredentials`, `setCache` and `cache`;
  - `RedisError::PoolTimeout` and `RedisError::Credentials` (`@nonExhaustive`, so neither breaks a caller);
  - `Connection.cached(command:, ttl:)` and `cacheStats()`, and `Cluster.cached`;
  - the `PoolDialers` contract.
- **In a new public module, `redis::pool`:**
  - `Pool` (`make`, `makeWith`, `join`, `share`, `acquire`), `Lease` (`conn()`) and `PoolShare`;
  - `ClusterPool`, `ClusterLease` (`cluster()`) and `ClusterPoolShare`;
  - `PoolOptions`.

  The core is file-private, as PG's is. It reaches `putBack`, `settleIdle`, `probeIdle` and `relogin` on `Connection`
  and `Cluster` through grants.

**10. The changes, for the CHANGELOG** (0.x allows breaks):
- the two new `RedisError` variants;
- a scan carried to another link ends with an error;
- `authenticate` after a lost link uses the new credentials;
- CLIENT TRACKING's refusal names `Config.setCache`;
- `setAuth` is refused once a provider is set;
- the README's `reconnect=off` text.

### The session's steps

Each step ends green before its commit:
- `tools/test.sh`, debug and release, on v0.9.707 and on cstar's newest build;
- `tools/test-integration.sh` on all eight servers, alone, under Sentinel and as a cluster;
- the step's mutations (`tools/mutations/7b-sN.json`), every one CAUGHT, with the live ones run after the matrix;
- this file, AGENTS.redis.md and the CHANGELOG's Unreleased section.

0. **Done (2026-10-21).** This plan; repros R1–R12 and probes P1–P5; KRD-13 (found), KRD-14 and KRD-15 filed;
   `tools/mutate.sh`'s per-mutation `timeout` (`7b-s0.json`). The unit gate was green at the start on both compilers.
1. **Done (2026-10-21).** **Vectors, by script.** Two runs of each generator give the same files; no earlier capture
   moved.
   - `tools/gen-server-vectors.sh`: 27 cases a server, under both protocols where both apply.
     - Tracking OPTIN, CACHING YES, and CACHING refused without tracking.
     - A cached read's EXEC with a TTL, without one, on a missing key and on a hash. The TTL is recorded as the
       100000 ms its setup set (`pinned()`, which checks it read within a second of it).
     - A connection's own write, another client's write before this one's PING, and a FLUSHALL.
     - A re-AUTH as another user on a tracking connection, and the invalidation after it.
     - A refused AUTH (a wrong password, a disabled user) and ACL WHOAMI after it.
     - The put-back's UNWATCH and SELECT 0.
     - RESP2's tracking delivering nothing.

     The script requires each of these facts on every server, as phase 7a's are.
   - `tools/gen-topology-vectors.sh`: a tracking client at each node of the cluster's shard and of the Sentinel group.
     On all eight servers:
     - Sentinel lets both go with no bytes, as it does any client, so a cache is flushed with its link.
     - A manual cluster failover sends neither anything and keeps both open. The new primary's write still
       invalidates the key at both, the demoted node through replication.

     So a cluster's tracking survives a planned failover. Decision 7's flush when the map moves a node's slots still
     guards an unplanned one, where the old primary may be cut off.
   - `tools/gen-command-table.sh` writes the cacheable allow-list (`src/wire/cacheable.kama`, 78 commands). The rule is
     in the script's header.
     - Read-only, never blocking, with mandatory keys, and no `nondeterministic_output` tip on any server.
     - Every key spec from 7.0 on is `RO`, a key, complete, and with a known start and end. That last rule leaves out
       SORT_RO, whose BY and GET read keys no spec names.
     - A command only 6.2 has has no specs to judge, and is left out.
     - TOUCH (its metadata is EXISTS's, but its point is to touch) and MEMORY USAGE (the server's accounting) are left
       out by name.
   - Unit (`tracking_test.kama`): every new server capture reads, three bytes at a time, as exactly the values its
     setup says. The topology captures are the cluster's and the cache's to replay (steps 5 and 6).
   - No mutations: the step adds no library code. The captures' readers come with steps 2, 3 and 6, whose mutations
     cover them.
2. **Done (2026-10-21).** **The credentials provider** (`src/credentials.kama`).
   - **What was built:**
     - `Credentials`, `Login`, `CredentialsError` and `RedisError::Credentials`;
     - `Config.setCredentials` and `hasCredentials`, with the refusals both ways;
     - the login asked at every handshake (`loginFor`), and `prepared()` (settle, ready, `refreshed`) on every call
       path;
     - the subscriber's `relogin`;
     - the `authenticate` fix.
   - **Settled on the way:**
     - `login()` takes no argument. Five of the six peers with a provider pass nothing (redis-py, go-redis, Jedis,
       node-redis, Lettuce); only rueidis passes the address. A `Config` argument would have made `Config` and
       `Credentials` refer to each other.
     - The provider moves from the `Config` into the `Opener` at `establish` and `connectOver`. So the kept `settings`
       hold neither a provider nor a password, and a `copy this.settings` forks nothing.
     - `recourseFor` already treats `Credentials` as final: it falls to `case _`, and `transient` is false for it.
       Nothing was added there.
     - A sentinel's connection is over `Opener.none()`, so `forSentinel` needs no clearing (the line was dead, and
       went).
     - A re-AUTH that loses its link redials at once, since nothing of the call was sent, and `transactAt` checks
       `watchLost` again after it.
   - **Unit** (`credentials_test.kama`, and a case each in `cluster_test` and `sentinel_test`), through the scripted
     dialer:
     - asked at the connect and at a redial; RESP2's AUTH; over `connectOver`;
     - the refresh, and not before;
     - a refused re-AUTH, and the provider failing at a refresh, at the connect and at a redial (final, one try);
     - the link lost at the re-AUTH;
     - a WATCH lost that way holding the transaction back;
     - `authenticate` refused beside a provider, and after a lost link (and refused there, the old login kept);
     - the subscriber under both protocols;
     - each cluster node with a fork of its own;
     - the sentinels keeping their own login;
     - the `Config` refusals and the `Login` checks.
   - **Live** (`credentials_test.kama`, all eight servers):
     - a `kr_rot` user, and a rotation: the refresh, then pw1 taken away and a kill, with the redial on pw2;
     - a revocation and a provider failure, each closing the connection (counted in CLIENT LIST);
     - a cluster, every node logging in;
     - the master found through sentinels.

     The rotation's second login is another user's (`kr_rot2`). The server keeps a session logged in whatever its
     passwords become, so only ACL WHOAMI naming the new user shows that the connection logged in anew. A first
     version rotated kr_rot's own password, and the live mutation that turned the refresh off survived it.
   - **Mutations** (`7b-s2.json`): 25, every one CAUGHT. 23 are unit (M1–M23) and two live (IM1–IM2, on Redis 8.10).
     - Making them caught tightened the tests. After a refusal or a provider failure, the old link's script refuses a
       login there, so a client that went on with that link fails visibly.
     - `setCredentials`'s check for a user without a password went: neither the URL (`user:@` is refused) nor
       `setAuth` can give one.
   - **Gates:** `tools/test.sh` debug and release on v0.9.707 and 0.9.713, and the integration matrix on all eight
     servers. The live credentials cases ran again on all eight once the rotation changed.
3. **Done (2026-10-21).** **The pool core** (S3; `src/pool/pool.kama`, the public module `redis::pool`).
   - **What was built:**
     - `Pool` (`make`, `makeWith`, `join`, `share`, `acquire`), `Lease`, `PoolShare` and `PoolOptions` (`maxSize`,
       `acquireTimeout`, `lifetime`, `lifetimeJitter`; the maintenance's options come with step 4);
     - the `PoolDialers` contract, and `RedisError::PoolTimeout`;
     - `Connection.putBack` (the release) and `settleIdle` (the acquire's zero-time check), granted to the core;
     - the Scan fix: each link draws a random identity (`linkId`).
   - **Settled on the way:**
     - A lease's connection is handed out as a `ref`, which a `ref` parameter cannot take: callers borrow it
       (`borrow lease.conn() as conn { … }`), as the README says.
     - The scripted server acts only when the client reads or waits, so a close after a release cannot be told from
       one before it there. The release's check is a unit case; the acquire's own check is a live case with
       `reconnect=off`, where a lost connection that was lent would answer Closed.
     - On macOS a host name's first lookup keeps two of the resolver's descriptors open for the process. So the live
       descriptor count uses an IP address, which the test certificate names.
   - **Unit** (`pool_test.kama`, through a scripted `PoolDialers`):
     - reuse;
     - the bound and `PoolTimeout`;
     - a lease given back is lent again;
     - an idle connection behind a freed place is lent first, and the place kept;
     - a waiter in another isolate woken by a release;
     - the put-back's UNWATCH and SELECT, once;
     - pushes dropped and counted;
     - each discard: a refused put-back, a hand `authenticate`, lost at the release, closed by the lease, past its
       lifetime;
     - no command timeout or lost WATCH carried over;
     - a redial inside a lease; `reconnect=off`;
     - a pool joined in another isolate, and not shared again;
     - a scan carried to another lease's connection;
     - the refusals and the defaults;
     - a provider forked for each connection.
   - **Live** (`pool_test.kama`, all eight servers):
     - four isolates × 250 INCRs through a pool of two: every one counted, never more than two connections;
     - the next lease finding database 0 and no WATCH;
     - idle connections killed, with and without `reconnect=off`;
     - `PoolTimeout`;
     - TLS;
     - no connection and no descriptor left once the pools drop.
   - **Mutations** (`7b-s3.json`): 25, every one CAUGHT. 22 are unit (P1–P22) and three live (IP1–IP3, on Redis 8.10).
     Making them caught tightened the tests:
     - a third lease (the database recorded at the release);
     - pushes dropped;
     - a freed place ahead of an idle connection;
     - a joined pool dialing through its fork;
     - a lifetime with jitter;
     - the live WATCH on database 0's key.
   - **Gates:** `tools/test.sh` debug and release on v0.9.707 and 0.9.715, and the integration matrix on all eight
     servers.
     - Valkey 8.1's release run once answered `BLPOP 1` 500 ms late, past a 1.5 s deadline; its rerun was green. The
       case now waits `BLPOP 2` under `command_timeout=1`: a 1 s margin, and still apart from command_timeout alone
       (postgres's rule: widen the margin rather than retry).
     - The pool's live cases ran again on all eight once the WATCH order changed, and Redis 8.10's full run once the
       margin did.
4. **Done (2026-10-21).** **Maintenance** (S4).
   - **What was built:**
     - `PoolOptions` gains `minIdle` (0), `idleTimeout` (30 minutes), `healthCheck` (60 s) and `pingTimeout` (5 s),
       with their checks;
     - a maintenance isolate per pool that made its channels, stopped by the pool's drop through a channel it hears:
       fill to minIdle, then a round every healthCheck (retire the expired and the pruned, probe, refill);
     - Npgsql's median pruning;
     - `Connection.probeIdle`: settle, a fresh login when due, PING within pingTimeout, never a redial;
     - the maintenance's connects bounded by acquireTimeout when connect_timeout is 0 (`boundConnects`).
   - **Unit**, through a traced scripted server (`FakeServer.traced`, `Dial::ServeTraced`: it logs "connect", each
     command and "close", and answers PING whenever it comes):
     - minIdle at the start, then leased with no new connect;
     - a lost idle connection replaced, and an idle one probed;
     - an unanswered probe closing its connection;
     - pruning by the median, and its floor at minIdle;
     - a lifetime retired by a round;
     - an idle re-AUTH;
     - the drop stopping the maintenance at once;
     - the options' checks and defaults.
   - **Live**, on all eight servers:
     - minIdle at the start;
     - pruned back to minIdle after three leases;
     - a killed idle connection replaced;
     - an idle connection logging in as the provider's next user (CLIENT LIST's `user=`);
     - the drop closing everything.
   - **Mutations** (`7b-s4.json`): 17, every one CAUGHT. 14 are unit (K1–K14) and three live (KI1–KI3, on Redis 8.10).
     Making them caught tightened the tests:
     - an unanswered probe, and a lost idle connection, refilled to minIdle in the same round (K13, K14);
     - the acquire's own check moved to the live test with `reconnect=off`, since the scripted server cannot stage a
       close between a release and the next acquire.
   - **Gates:** `tools/test.sh` debug and release on v0.9.707 and 0.9.715, and the integration matrix on all eight
     servers. The mutations ran on v0.9.707: by then cstar's tree held KR-230's `Poller` change, uncommitted, which
     its build reads from `lib/`, and nothing that uses `std::net::Ready` compiled with it.
5. **Done (2026-10-21).** **The pool under Sentinel and on a cluster.**
   - **What was built:**
     - `ClusterPool`, `ClusterLease` (`cluster()`) and `ClusterPoolShare`, over the same core: the pool holds `Held`
       (`One` connection or a `Whole` cluster), and `Pool` and `ClusterPool` share the rest through `Plant`;
     - three free functions over `Held`, each granted its members of `Connection` and of `Cluster`: `keepable`
       (release, `putBack`), `lendable` (acquire's zero-time check of a connection, `settleIdle`) and `probed` (the
       maintenance, `probeIdle`). A cluster is lent as it is: its release let every lost link go, and each call settles
       its node's link before it writes;
     - `Cluster.putBack`: each node link's own put-back (`LinkFate`): kept, let go when lost (the cluster opens it
       again when a call needs it), or the whole cluster discarded when a lease called `authenticate` on a node;
     - `NodeDialers`: a pooled cluster's nodes dial through a fork of the pool's `PoolDialers`;
     - the refusals: a Sentinel or `unix://` configuration and `reconnect=off` are `Config` for a `ClusterPool`, and a
       cluster's configuration for a `Pool` names `ClusterPool`.
   - **Unit:**
     - a lease's cluster keeps its node links across leases, and a lost one is let go and opened again;
     - a cluster a lease re-authenticated by hand is not kept;
     - the refusals;
     - through sentinels, a pooled connection Sentinel let go at a failover is replaced through the sentinels, on the
       new master.
   - **Live** (`pool_failover_test.kama`, all eight servers): four isolates INCR through a pool across a SENTINEL
     FAILOVER, and through a `ClusterPool` across a CLUSTER FAILOVER and a DEBUG SLEEP past cluster-node-timeout. No
     INCR runs twice (each count is at most those answered and those failed), and none fails once the topology has
     settled.
     - A count may end below the INCRs answered, and the message says by how many. Sentinel promotes the replica
       before it reconfigures the old master, and the old master's writes in between are discarded when it resyncs;
       step 7's first run, three failovers at about 180 INCRs a second, lost 1639 of 9163. A primary woken from DEBUG
       SLEEP answers what it ran before it slept, after its replica took over. Both servers document this ("last
       failover wins"; `min-replicas-to-write` narrows it).
     - Here the window runs from the promotion until Sentinel converts the old master and kills its clients (phase 6,
       decision 4: the kill and the redial follow a failover, with no `+switch-master` subscription), which comes on
       a later INFO poll, up to 10 s on. The peers that listen (GR, JE, NR, RU) drop their connections to the old
       master at `+switch-master`, which can come sooner; their window starts at the promotion too. Raised with the
       maintainer, since it bears on that decision.
   - **Mutations** (`7b-s5.json`): eight, every one CAUGHT, all unit (C1–C7, C9). Step 5's restructuring moved what
     seven older ones named (`7b-s3.json` P10, P11, P16, P18 and IP2; `7b-s4.json` K3, K14 and KI2): each was pointed at
     the new code and run again, every one CAUGHT. Making them caught changed the code:
     - C2 (a lost link kept at the release) and C8 (no check of a pooled cluster at acquire) each survived, because
       each check covered for the other. A `ClusterPool`'s reconnect is on and every call settles its link before it
       writes, so a check at acquire was the same work twice: it was removed (`Cluster.settleIdle`), and C2 is caught.
     - S1 (no check of a pooled connection at acquire) matters only with `reconnect=off`, which the scripted server
       cannot stage between a release and an acquire: IP2, live, is that case, and S1 was dropped.
   - **Gates:** `tools/test.sh` debug and release on v0.9.707 and on cstar's committed 0.9.716 (`d1ed4554` with its own
     `lib/` and `include/`, since its working tree held KR-230 uncommitted), and the integration matrix on all eight
     servers. After the acquire check was removed, the unit gate and the mutations ran again, and
     `pool_failover_test.kama` ran live on all eight.
6. **Done (2026-10-21).** **Client-side caching** (phase 4's step 5).
   - **What was built:**
     - `CacheConfig` (`maxEntries` 10 000, `maxBytes` 16 MiB) and `CacheStats` (src/cache.kama); `Config.setCache`
       and `cache()`, kept by a copy and a cluster node's `Config`, dropped by a sentinel's;
     - the cache (src/wire/cache.kama): a slab of entries with a generation each, an index by the command's bytes and
       one by key, an LRU through the stored entries, and `Ticket`s that hold a pending read's place;
     - tracking in the handshake (`CLIENT TRACKING ON OPTIN`, in the HELLO write, on every link made); a server that
       refuses it fails the connect, and `protocol=2` with a cache is `Config`;
     - `Connection.cached(command:, ttl:)`: a miss writes `CLIENT CACHING YES`, MULTI, PTTL of each key, the command
       and EXEC at once and keeps the reply until the shorter of `ttl` and the keys' TTLs; invalidations are applied
       in `setAside`, so in wire order, and one before the reply leaves nothing kept;
     - the sync rule by count: `Wire.written()` against the count after a cached read's last round trip, so a hit
       after any other write PINGs first, and `putBack` resets it, so each lease's first hit does too;
     - emptied on a lost link, a null invalidation, `select` of another database, `authenticate`, and any login as
       another user (in `loggedIn`, which a connect, a fresh login and a subscriber's re-login all pass);
     - `Cluster.cached`, routed and redirected as `call` (a try after ASK sent uncached), and `cacheStats()` summed;
       a node a change of the map takes a slot from has its cache emptied, and after any change each node link's next
       hit makes a round trip first (both found by step 7: see there);
     - `Commands.cacheable()`: the table's entries for the allow-list alone, for each cache's keys;
     - the subscriber's `Name` became the wire's `ByteKey`, one hashed bytes key for both.
   - **Revised from phase 4's decision:** `select` and `authenticate` are allowed on a caching connection and empty
     its cache, rather than refused: a pool's put-back sends SELECT, and a provider's login may change the user.
     `cached` refuses a WATCH in force instead, whose transaction its MULTI and EXEC would end.
   - **Unit** (`cache_test.kama`, with every reply from the vectors): tracking on every server's handshake, and its
     refusal; a miss and a hit for a string, a missing key and a hash; `ttl`; another client's write, the race, one's
     own write and the round trip after it, FLUSHALL; every flush and what keeps the cache; `maxEntries` by recency,
     `maxBytes`, a value too large to keep; the refusals and a command refused as it is queued; a lease's first hit;
     RESP2 behind a proxy; and on a scripted cluster, each read at its key's node.
   - **Live** (`cache_test.kama`, all eight servers): another client's write, one's own write, FLUSHALL, the server's
     TTL and the caller's, WRONGTYPE, the bounds, `protocol=2`, a pool's next lease reading another client's write,
     and a cluster's reads and its own write.
   - **Mutations** (`7b-s6.json`): 29, every one CAUGHT: 28 unit (H1–H24, H26–H29) and one live (HI1, on Redis 8.10).
     - H12 (tracking left out of the handshake) passed at first: the script's TRACKING step just went unconsumed. A
       PING after the handshake now meets that step when TRACKING was not sent.
     - H16 (no check that a pending entry still holds) is one the program dies of (`PANICKED`): a fill of an entry an
       invalidation removed reads past its command.
     - H25 (an expired entry left in place by a lookup) survived: the miss's pending entry removes it anyway, so the
       removal in `lookup` went.
     - H27–H29 came with step 7's findings: the resync after a change of the map, and a node's cache emptied when the
       map takes a slot from it.
     - HI1 (the server's TTL not bounding an entry) survived on a standalone server, which expires the key within about
       100 ms and invalidates it. It is now a cluster case, with active expiry off on the key's primary (`DEBUG
       SET-ACTIVE-EXPIRE 0`; the standalone servers refuse DEBUG).
     - Two live mutations went (HI2, no resync at a lease's release; HI3, no round trip after a write): live, the
       invalidation is on the socket before the next read, so only the scripted server stages the race, where H4 and
       H5 are CAUGHT.
   - **Gates:** `tools/test.sh` debug and release on v0.9.707 and on cstar's committed 0.9.716, and the integration
     matrix on all eight servers, with step 7's hardening; the live cache and hardening tests ran again on all eight
     after their last changes.
7. **Live hardening across failovers** (`pool_hardening_test.kama`).
   - Repeated SENTINEL and CLUSTER FAILOVERs, each waited out, with four isolates on one pool, the cache and a provider
     on.
   - A restart, and maxclients.
   - What it checks: the INCR invariants, `/dev/fd` back to its count, and the cache's bytes and the pushes within
     their bounds.
8. **Docs, examples and 0.3.0.**
   - `examples/pool`, `examples/cache`, and a README program with a provider.
   - The README's error table gains `PoolTimeout` and `Credentials`.
   - The CHANGELOG, `kama.json` and `libraryVersion()`; "Decided, and why", "Phase 7b".
   - The gates from a clean clone; `kama publish --dry-run`.
   - Pushed and published on the maintainer's word.

## Parity with the peers (surveyed 2026-10-21)

The maintainer asked what remains for this package to be on par with other Redis bindings. The answer below placed
phases 8 and 9 in the release plan and moved the credentials provider into 0.3.0 (the maintainer, 2026-10-21: "Sounds
good").

**Sources.** Each client was read at its latest release tag (shallow clones; release dates from the GitHub releases
API, PyPI, npm and crates.io), and checked against redis.io's pages on smart client handoffs, failover and
client-side caching:
- redis-py 8.1.0 (2026-07-30), go-redis v9.23.0 (2026-10-05), Jedis 8.0.2 (2026-10-07; 8.1.0-beta1 on 2026-09-01),
  node-redis redis@6.3.0 (2026-09-30; 6.4.0-beta.0 on 2026-10-12);
- Lettuce 7.9.0 (2026-10-14), redis-rs 1.7.1 (2026-09-25), rueidis v1.0.79 (2026-10-15), Valkey GLIDE v2.5.3
  (2026-09-25).

A version after a claim is the release that added it. Paths are relative to the repository at its tag.

**Where this package matches or leads:**
- **Tested on Redis and Valkey both.** It runs live on Redis 6.2 to 8.10 and Valkey 7.2 to 9.1. None of the four
  clients Redis maintains (redis-py, go-redis, Jedis, node-redis) mentions Valkey; redis-rs, rueidis and GLIDE do.
- **Commands that span nodes are split by the servers' own command tips.**
  - node-redis 6.2+ splits MGET, MSET and DEL, and redis-rs and Lettuce split.
  - redis-py splits a few (DEL and the like) and refuses the rest.
  - go-redis splits only when the tips are turned on, and rueidis refuses ("Phase 6: where to start", the peers'
    table).
- **A shard channel whose slot moves is followed and reported.**
  - redis-py 8.0 and node-redis follow (`cluster-slots.ts`), and GLIDE resubscribes.
  - go-redis and rueidis only partly: no handling of the server's `sunsubscribe` was found in go-redis, and in
    rueidis the caller subscribes again.
  - Jedis does not, and Lettuce's issue #3213 is open.
- **Atomic slot migrations** (Redis 8.4+, Valkey 9) are followed, live. rueidis is the only peer that claims it
  (1.0.69).
- **Sentinel's answer is checked with ROLE.** Only redis-rs and rueidis do the same.
- **Nothing is ever sent twice** (phase 7a). Most peers resend after an I/O failure:
  - redis-py by default 10 times, with backoff from 10 ms to 1 s, writes included (`redis/_defaults.py`);
  - go-redis 3 times (`error.go:84`);
  - Lettuce replays its queue (at-least-once).

  rueidis resends read-only commands only, and GLIDE does not resend. That is a stance here, not a gap.
- **Present here, as at the peers:** RESP2 and RESP3, TLS, Unix sockets, comma-listed hosts and the sentinel URL
  forms, EVALSHA falling back to EVAL, SCAN iterators (on a cluster too), every hostile input bounded, and the
  database honoured on Valkey 9's cluster (GLIDE 2.1 and redis-rs 1.3 do this too).

**The gaps, and where each is placed:**

| Gap | The peers | Here | Placed |
|---|---|---|---|
| A client shared by concurrent callers | All 8: a pool (redis-py, go-redis, Jedis) or one multiplexed connection (Lettuce, redis-rs, node-redis, rueidis, GLIDE) | One `Connection` per isolate | 0.3.0 |
| A credentials provider with live re-AUTH | 7 of 8; GLIDE has `updateConnectionPassword` and AWS IAM | `authenticate()`, called by hand | 0.3.0 |
| Client-side caching | All 8, opt-in in every one | Refused (`CLIENT TRACKING`) | 0.3.0 |
| A typed method per command | All 8: Jedis about 1093 (`CommandObjects.java`), redis-py about 665, go-redis about 617, rueidis 576 (generated from 13 JSON specs, `hack/cmds/`), node-redis about 570, GLIDE about 396, redis-rs about 289, and Lettuce one interface per command group | `cmd"…"` and `reply::<T>` | 0.4.0 |
| The Redis 8 modules: JSON, `FT.*`, TimeSeries, the probabilistic types | All four Redis clients and rueidis, typed. Lettuce has all but TimeSeries; redis-rs has JSON and Bloom, and `FT.CREATE` only; GLIDE types JSON and `FT.*` | Through `cmd` on one server, untyped; refused by name on a cluster (below) | 0.4.0 |
| Hooks and OpenTelemetry | go-redis, rueidis, GLIDE, Lettuce (Micrometer), redis-py and node-redis (metrics); none in Jedis or redis-rs | None | phase 9 |
| Valkey's extras | AZ-affinity reads (GLIDE 1.2, rueidis 1.0.54); `CLIENT CAPA redirect` (rueidis 1.0.67); `CLUSTERSCAN` (rueidis 1.0.78–79) | Primary or replica reads; CAPA refused; CLUSTERSCAN deferred in phase 6 | phase 9 |
| Smart client handoffs | On by default under RESP3: redis-py 7.0, go-redis 9.16, node-redis 5.9 (all October 2025; cluster forms in 2026). Also Lettuce 7.0, and Jedis 8.1.0-beta1 | None | phase 9 |
| Client-side Active-Active failover | redis-py 7.0, Jedis 7.0 (`MultiDbClient`) and Lettuce 7.4 (GA 7.8), all experimental; node-redis 6.4.0-beta.0 | None | phase 9 |
| Windows | All 8 | Linux and macOS | phase 9, after `@kama/tls` |

**What the survey found here:**
- **The Redis 8 images ship four modules that the matrix does not load.** The `redis:8.x` images carry `rejson.so`,
  `redisearch.so`, `redistimeseries.so` and `redisbloom.so` in `/usr/local/lib/redis/modules`. The matrix's servers
  start from `tests/integration/server`'s own config, so none is loaded: `MODULE LIST` on 8.10 shows `vectorset`
  alone.
  - So the generated command table (466 commands) has no `FT.*`, `JSON.*`, `TS.*` or `BF.*` command. A `Cluster`
    refuses each by name and points to `callFor(key:)`, which honours the rule that anything missing is refused, never
    half there.
  - Phase 8 starts by loading them on Redis 8. For Valkey, the bundle image (valkey-json, valkey-bloom, valkey-search)
    is to be checked. Then the table is generated again.
- **No open-source server takes `CLIENT MAINT_NOTIFICATIONS`.** Redis 8.10 and Valkey 9.1 both answer "unknown
  subcommand", checked 2026-10-21. Smart client handoffs come from Redis Cloud and Redis Software alone, so the
  matrix cannot capture them. Their vectors would come from the specification, or from a recording against one of
  those services.

**The peers' defaults, for the designs to come:**
- **Pools:**
  - redis-py: at most 100 connections since 8.0.0, and a full pool is an error; its blocking pool is 50 connections
    with a 20 s wait (`redis/connection.py:2970`).
  - go-redis: 10 × GOMAXPROCS, 30 minutes' idle time, and an acquire bounded by the read timeout plus 1 s
    (`options.go:595,704-768`).
  - Jedis: commons-pool2's sizes (its FAQ says 8; not checked in source), testing idle connections every 30 s.
  - node-redis: 1 to 100 connections, 3 s to acquire, 3 s idle (`docs/pool.md`). It serves blocking commands and
    WATCH only.
  - Lettuce: commons-pool2, opt-in, at most 8. redis-rs: r2d2 or bb8, opt-in. GLIDE: no pool.
- **Multiplexing:**
  - node-redis writes the commands of one tick as one batch, by default.
  - rueidis auto-pipelines by default (`PipelineMultiplex`: 1 to 4 connections to one server, 1 per cluster node).
  - GLIDE allows 1000 commands in flight.
  - go-redis batches up to 200 commands or 128 KiB (9.22, experimental).
- **Client-side caching:**
  - Opt-in everywhere. Default tracking, never BCAST, in the four clients Redis maintains and in redis-rs. BCAST is an
    option in rueidis, in GLIDE (2.5) and in Lettuce, which deprecated its cache in 7.8.
  - rueidis turns on `CLIENT TRACKING ON OPTIN` for every RESP3 connection, gives each connection 128 MiB, and caches
    per call with a TTL (`DoCache`).
  - About 10 000 entries, LRU, in redis-py, go-redis, Jedis and redis-rs; node-redis has no size limit.
  - What can be cached:
    - an allow-list of 68 to 90 read commands in most;
    - node-redis reads it from the server's COMMAND metadata;
    - GLIDE caches only GET, HGETALL and SMEMBERS.
  - go-redis caches on a standalone client only, and not at all once a credentials provider is set.
- **Credentials:**
  - redis-py (5.3.0): an idle connection re-AUTHs at once, a busy one when it is released.
  - go-redis (9.10): a connection marked for re-AUTH is not leased; it re-AUTHs once idle.
  - Jedis (5.3.0): on the return to the pool, or in an eviction pass.
  - node-redis: at once, on the live connection.
  - Lettuce (6.6): only with `ON_NEW_CREDENTIALS`, which is off by default.
  - redis-rs (1.0.4): each connection follows the provider's stream.
  - rueidis: `RefreshAfter` (1.0.77).
  - GLIDE: AWS IAM (2.2), whose token is refreshed every 300 s and used at the next reconnect.
  - Entra ID is a separate package at every peer that has it.
- **Health:**
  - rueidis pings idle connections every second, and GLIDE checks every 3 s.
  - redis-py's `health_check_interval` and node-redis's `pingInterval` are off by default.
  - go-redis checks a connection's age and idle time at checkout and peeks at its socket.
  - TCP keepalive is on in most.
- **Timeouts:**
  - 5 s in redis-py 8.0, go-redis 9.22 and node-redis 6.0.
  - 2 s in Jedis.
  - 60 s per command in Lettuce.
  - GLIDE's requests: 250 ms.

**Outside a core client at every peer:** locks (redis-py's single-instance `Lock`, rueidislock, bsm/redislock), rate
limiters (go-redis/redis_rate, rueidislimiter) and object mapping (redis-om-*). They belong in packages of their own,
not here.

**Not verified:**
- Jedis's commons-pool2 sizes.
- When go-redis and Jedis added HEXPIRE.
- Whether go-redis handles a server's `sunsubscribe` after a slot move.
- node-redis's public push event.
- Jedis 8.1's handoff settings.
- redis-rs's keepalive default.
- GLIDE's C# and PHP clients.

## Phase 6: where to start

The session plan, drawn up on 2026-10-19 from primary sources, for 0.2.0.
- **The maintainer chose four of its decisions:**
  - commands that span nodes follow the server's own command tips;
  - several hosts are written with commas;
  - a shard channel whose slot moves is followed;
  - a Sentinel failover is followed on the next connect.

  The rest are this plan's recommendation.
- **A review of the draft against this code** (cited H1–H22 below) changed several of them.

The sources:
- **The servers,** at the matrix's tags:
  - Redis 8.10.2, with 7.2.16, 7.0.0 and 6.2.24 where they differ, and Valkey 9.1.2;
  - the files: `cluster.c`, `cluster_legacy.c`, `server.c`, `sentinel.c`, `replication.c`, `blocked.c`,
    `networking.c`, `pubsub.c`, `commands.def` and `src/commands/*.json`.
- **The documentation:** the cluster specification, the Sentinel documentation and its client specification
  (`sentinel-clients.md`), and `command-tips.md` and `key-specs.md`.
- **The peers, at their current tags:**
  - go-redis v9.23.0: `osscluster.go`, `osscluster_router.go`, `sentinel.go`;
  - redis-py 8.1.0: `cluster.py`, `sentinel.py`, `_parsers/commands.py`;
  - redis-rs 1.7.1: `cluster_handling/` and `sentinel.rs` (the cluster files the outline named are gone);
  - Lettuce 7.9.0: `RedisClusterClient`, `ClusterTopologyRefreshOptions`, `ClusterDistributionChannelWriter`,
    `SentinelConnector`, `SentinelTopologyRefresh`;
  - rueidis v1.0.79: `cluster.go`, `sentinel.go`;
  - hiredis v1.5.0 and redis-cli 8.10.2.
- **The model:** @kama/postgres's hosts list (libpq's comma-separated URL), and this package's 7a.

The bar is phase 3's and 7a's:
- every form honoured or refused;
- every failure path tested against the scripted server;
- the whole matrix live, debug and release;
- every step proven by mutation.

### What the sources showed

Short names: R8 is Redis 8.10.2, V9 Valkey 9.1.2, R62 Redis 6.2.24, and SPEC the cluster specification.

- **How a node answers a key it does not serve** (`getNodeByQuery`, R8 cluster.c:1236-1489, V9 1048-1312). The words
  come from `clusterRedirectClient` (R8 1498-1527, V9 1321-1345).
  - **The error lines:**
    - `-MOVED <slot> <endpoint>:<port>` and `-ASK …`, formatted `"-%s %d %s:%d"`;
    - `-TRYAGAIN Multiple keys request during rehashing of slot`, and Redis 8's `-TRYAGAIN Slot is being trimmed`;
    - `-CLUSTERDOWN The cluster is down`, `… and only accepts read commands`, and `-CLUSTERDOWN Hash slot not served`;
    - `-CROSSSLOT Keys in request don't hash to the same slot`.
  - **A slot another node owns:** MOVED.
  - **A slot being migrated, on the source:**
    - every key present: served;
    - every key missing: ASK;
    - some of each: TRYAGAIN.
  - **On the target:**
    - with ASKING: served, unless a multi-key command has a key missing, which is TRYAGAIN;
    - without ASKING: MOVED to the source.

    ASKING lasts one command, except inside MULTI (R8 networking.c:3050).
  - **A replica:**
    - without READONLY: MOVED to its primary;
    - with READONLY: reads served, writes MOVED;
    - sharded pub/sub is served on a replica even without READONLY.
  - **A command with no keys** is never redirected and never CLUSTERDOWN (R8 server.c:4602-4606).
  - **Inside MULTI** each queued command is checked. A redirection there makes EXEC answer EXECABORT. At EXEC every
    queued key must be in one slot (R8 cluster.c:1263).
  - **EVAL** with keys in two slots is CROSSSLOT. With `numkeys 0` it runs where it lands.
  - **PUBLISH** is broadcast across the cluster. SPUBLISH and SSUBSCRIBE are routed by their channel. A node that
    loses a slot pushes `sunsubscribe` itself (R8 pubsub.c:321-351, from `clusterDelSlot` and `clusterSetMaster`).
- **Where a redirection points.**
  - **The endpoint** (`clusterNodePreferredEndpoint`, R8 cluster_legacy.c:6653) is one of:
    - an IP;
    - a hostname, or `"?"` when none is set;
    - `""` for `unknown-endpoint`: `-MOVED 3999 :6380` means "the host you asked, this port" (SPEC:389).

    IPv6 comes without brackets, so a client splits at the last colon. 6.2 always sends the IP.
  - **The port:**
    - on 7.2 and later it follows the asking connection: TLS clients get `tls-port` (`clusterNodeClientPort(n,
      shouldReturnTlsInfo())`, R8 cluster.c:889-895);
    - on 6.2 and 7.0, under `tls-cluster yes`, a node announces its TLS port and its plaintext one beside it (`pport`,
      `deriveAnnouncedPorts`, R62 cluster.c:444-458). MOVED and SLOTS give a plaintext client the plaintext port (R62
      4370-4373, 5960-5963), so one cluster serves both kinds of client. Under `tls-cluster no` every client gets the
      plaintext port (the review's H12 said otherwise, from the 7.0 source alone; step 1 read 6.2's);
    - Valkey 9 adds `cluster-announce-client-(tls-)port`.
- **The slot map.**
  - **`CLUSTER SLOTS`:**
    - 6.2: `[start, end, [ip, port, id]…]`;
    - 7.0 and later: `[endpoint, port, id, {ip|hostname}]`, the endpoint NULL for unknown-endpoint;
    - failed replicas, and replicas at offset 0, are left out (R8 cluster.c:1607-1669);
    - deprecated in Redis since 7.0, un-deprecated in Valkey 8.0;
    - Valkey 9.1 adds `availability-zone`.
  - **`CLUSTER SHARDS`** (7.0 and later):
    - each node: `id`, `port`, `tls-port`, `ip`, `endpoint`, `hostname`, `role`, `replication-offset` and `health`
      (`online`, `fail` or `loading`);
    - slot numbers were bulk strings in 7.0.0–7.2.1;
    - the docs say `failed` where the code sends `fail`, and NULL where it sends `""`;
    - rueidis documents it as wrong on Redis 7.x after a failover.
  - **The spec tells a client** (SPEC:401-411, 548-561, 575-585, 624-650):
    - refresh the whole map on MOVED;
    - ASK is one command, ASKING first, with no change to the map;
    - read the map again before calling a slot unassigned;
    - wait on TRYAGAIN, then retry.
- **Commands, as the servers describe them.**
  - **7.0 and later's COMMAND INFO** has ten elements, the tips and the key specs among them.
    - A key spec is a `begin_search` (`index`, `keyword` or `unknown`), a `find_keys` (`range`, `keynum` or
      `unknown`) and flags (`RO`, `RW`, `OW`, `RM`, `access`, `update`, `insert`, `delete`, `not_key`, `incomplete`,
      …).
    - 6.2 has seven elements and a `movablekeys` flag. Its specs are the legacy first/last/step.
  - **`incomplete`:** only MIGRATE on Redis 8.0–8.8.0 and on Valkey 9.1. Redis 7.2.16, and 8.8.3 and later, mark
    GEORADIUS(BYMEMBER) and XREAD(GROUP) too.
  - **`command-tips.md` tells a cluster client what to do** with each command:
    - `multi_shard` (DEL, UNLINK, EXISTS, TOUCH, MGET, MSET, MSETEX): split the keys by slot ("the command must be
      split even if all the slots are managed by the same shard");
    - `all_shards` (PING, KEYS, DBSIZE, FLUSHALL, FUNCTION LOAD, SCRIPT EXISTS, WAIT, INFO, RANDOMKEY, …): every
      primary;
    - `all_nodes` (SCRIPT LOAD and FLUSH, CONFIG SET, ACL SETUSER, …): every node;
    - `special` (SCAN): its own procedure.
  - **The doc also says how to combine the replies:**
    - `agg_sum` (DEL, DBSIZE), `agg_min` (WAIT), `agg_logical_and` (SCRIPT EXISTS);
    - `all_succeeded` (MSET, FLUSHALL, CONFIG SET), `one_succeeded` (SCRIPT KILL);
    - otherwise the default: key order for a keyed command (MGET), concatenation for a keyless one (KEYS).

    It says each command is "atomic per shard".
- **Valkey's and Redis 8's cluster additions.**
  - **Valkey 9.0:**
    - `cluster-databases`, so SELECT works in cluster mode. Redis answers "SELECT is not allowed in cluster mode"
      (db.c:1577);
    - `CLUSTER MIGRATESLOTS`, an atomic migration: no ASK, writes paused, then MOVED.
  - **Valkey 9.1:** CLUSTERSCAN, a string cursor routed as a key.
  - **Redis 8.4:** `CLUSTER MIGRATION`, atomic too, with writes paused for at most 10 s.
  - **Valkey's `CLIENT CAPA redirect`** applies to a standalone replica only: `-REDIRECT host:port`.
- **Sentinel.**
  - **The client specification** (sentinel-clients.md:49-154):
    1. the sentinels in turn, with a short timeout each;
    2. `SENTINEL GET-MASTER-ADDR-BY-NAME`, where a null means the next sentinel;
    3. `ROLE`, which must say master; otherwise wait a little and start again;
    4. every reconnect starts at step 1;
    5. the sentinel that answered moves to the front;
    6. optionally, `SENTINEL SENTINELS` appended to the end of the list;
    7. "Sentinel unreachable" is reported apart from "unknown master";
    8. pub/sub may speed things up, but "should not substitute" this.
  - **The replies:**
    - GET-MASTER-ADDR-BY-NAME: `[ip, port]`, the port a bulk string, or a null array (sentinel.c:4021-4034);
    - SENTINELS and REPLICAS: an array of maps under RESP3, of flat arrays under RESP2 (3818-3833);
    - ROLE: `["master", offset, [[ip, port, ack]]]`, `["slave", host, port, state, offset]` or `["sentinel",
      [names]]`;
    - `+switch-master`: `<name> <oldip> <oldport> <newip> <newport>`.
  - **What a sentinel accepts:** HELLO 3 (`mode: "sentinel"`), RESP3 SUBSCRIBE mixed with commands, AUTH, CLIENT
    SETNAME and SETINFO, PING and ROLE. SELECT, ECHO, RESET, QUIT and SSUBSCRIBE are unknown commands there.
  - **What a failover does to clients:**
    - every reconfiguration's MULTI sends `CLIENT KILL TYPE normal` and `TYPE pubsub` to the node, "to trigger the
      ask-master-on-reconnection protocol" (sentinel.c:4923-4991);
    - a demoted master answers writes `-READONLY You can't write against a read only replica.`;
    - its blocked clients get `-UNBLOCKED …` and are closed;
    - a master cut off from the sentinels keeps its clients. `min-replicas-to-write` is the server's own guard.
  - **Valkey 9:**
    - a coordinated failover (`SENTINEL FAILOVER … COORDINATED`), which kills clients on both nodes;
    - GET-PRIMARY-ADDR-BY-NAME, as an alias.
- **The peers (cluster):**

  | | go-redis | redis-py | redis-rs | Lettuce | rueidis |
  |---|---|---|---|---|---|
  | the slot map | SLOTS | SLOTS | SLOTS | NODES, majority vote | SHARDS (8+) or SLOTS |
  | on MOVED | whole map, 200 ms cooldown | that slot, the whole map every 5th | whole map | whole map, at most every 5 s | that slot, then a lazy whole map |
  | redirections | 3 | 16 | 16 | 5 | unlimited |
  | ASK | in one write | its own round trip | its own round trip | in one write | in one write |
  | a write sent again after an I/O failure | yes | yes | yes | yes (at least once) | no: read-only commands only |
  | keys | first-key rule and COMMAND | COMMAND, and GETKEYS | a static table | the command builder | generated |
  | multi-key commands | to the server (the tips on opt-in) | refused, or split (DEL…) | split | split | panics, or helpers |
  | transactions | one slot | one slot | one slot (async) | none | one slot |
  | replica reads | ReadOnly, ByLatency, Randomly | `load_balancing_strategy` | `read_routing_strategy` | `ReadFrom` | `SendToReplicas` |
  | sharded pub/sub, when a slot moves | passed on | moved, silently | not handled | passed on | dropped |
  | SELECT | none | refused | `database_id` | none | sent |

  Only redis-py's docs mention that a replica read may be stale. Each peer's URL with several hosts differs:
  - Lettuce: commas;
  - go-redis and rueidis: repeated `addr=`;
  - redis-py and redis-rs: no such URL.
- **The peers (Sentinel):**
  - **Finding the master:**
    - GET-MASTER-ADDR-BY-NAME: go-redis (all sentinels at once), plain Lettuce and rueidis;
    - SENTINEL MASTERS and its flags: redis-py and redis-rs.
  - **ROLE is checked** only by redis-rs and rueidis.
  - **Following a failover by subscription:** go-redis, rueidis and Lettuce's MasterReplica. Two of those are buggy:
    - go-redis listens for `+replica-reconf-done`, which no server sends;
    - Lettuce names three events without their `+`, so they never fire.

    The others reconnect.
  - **The sentinels' TLS** is shared with the data servers in go-redis and Lettuce, and separate in redis-rs and
    rueidis.
  - **The URL's user and password** mean the sentinels' in go-redis, and the data servers' in Lettuce and rueidis.
  - **Default timeouts:** 5 s (go-redis, redis-py, rueidis), 60 s (Lettuce), 1 s / 500 ms (redis-rs).

### Decisions

**1. Commands that span nodes follow the server's command tips** (the maintainer's choice, 2026-10-19).
- **The routing table is generated by script from every server's COMMAND INFO** (`src/cluster/commands.kama`). Each
  entry has:
  - the keys rule;
  - `readonly`;
  - the request and response policies;
  - which server it came from (the newest server's entry wins; 6.2 has no tips).
- **What each policy does:**
  - `multi_shard` commands are split by slot;
  - `all_shards` commands go to every primary, and `all_nodes` commands to every node;
  - the replies are combined by the response policy, as the doc says;
  - a `special` command (INFO, RANDOMKEY, MEMORY STATS, LATENCY, SCAN) is refused in `call`, and goes through
    `callEach(command:, on:)` (each node's reply, unmerged) or `Scan`.
- **The table is checked against the servers themselves,** not against the captures it came from (H8). Each command
  gets a sample invocation built from COMMAND DOCS, and each server's `COMMAND GETKEYS` answer to it is captured;
  `route()` must find the same keys.
- **An unknown command** is `Usage`, naming `callFor(key:, command:)` and `callEach`. There is no COMMAND INFO at run
  time (H7): it would need a node, it could fail, and it could not route inside a pipeline.
- **Inside a pipeline or a transaction** a command stays on one slot.
- **The README says:**
  - a split MSET is atomic per shard, not across the cluster;
  - a failure on one shard means part of the call may have run;
  - a hash tag keeps it one atomic command.
- **Peers:** redis-rs and Lettuce do this by default, go-redis on opt-in, redis-py in part, and rueidis refuses.

**2. Several hosts are written with commas** (the maintainer's choice). This is Lettuce's form, and libpq's, which
@kama/postgres reads.
- **A cluster's seeds:** `redis://u:p@h1:7000,h2:7001/0?read_from=replica`.
- **The sentinels:** `redis-sentinel://u:p@s1:26379,s2,s3/0?master_name=mymaster[&role=replica]`, and
  `rediss-sentinel://` for TLS to the sentinels and the data servers both.
  - A sentinel's port defaults to 26379.
  - `master_name` is go-redis's key.
- **The user and password are the data servers'** (Lettuce, rueidis). The sentinels' own credentials are set in code
  only.
- **There is one `Config`.** It reads several hosts, the sentinel schemes, `master_name`, `role`, `read_from` and
  `max_redirects` (H18). Each entry point refuses what is not its own when it connects, naming the right one:
  - `Connection.connect` refuses several hosts on a non-sentinel URL, and the cluster's options;
  - `Cluster.connect` refuses a sentinel Config and `reconnect=off` (H3);
  - `connectOver` refuses a sentinel Config.
- **`redis://a,b`, today the host `"a,b"`,** becomes two hosts. The URL generator's misread rules gain the comma
  forms.

**3. A shard channel whose slot moves is followed, and the gap reported** (the maintainer's choice).
- **What happens:** the node's own `sunsubscribe` of a channel still wanted leads to:
  1. the map read again;
  2. SSUBSCRIBE at the new owner;
  3. `Delivery::Moved(name, to)`, queued first, saying that messages published in between may be lost.

  A refusal there (NOPERM) stays `Unsubscribed`.
- **Peers:** only redis-py moves a subscription, and silently. The others pass the unsubscribe on, or drop the
  channel.
- **`ClusterSubscriber`** runs a plain `Subscriber` per node, each keeping 7a's resubscribe: channels and patterns on
  one primary, shard channels on each owning primary.
- **How its `next` waits:**
  1. it sweeps every node without waiting: frames the reader holds, and TLS plaintext already buffered;
  2. then it waits on every node's socket at once with `std::net::Poller`. The raw handle is recorded when this
     client opens a socket, so the `Transport` contract does not change (a contract has no default methods, and a new
     member breaks every implementer);
  3. links over a caller's dialer have no handle, so they are waited on in turn, a short slice each. The README says
     what that costs.

**4. A Sentinel failover is followed on the next connect, with no +switch-master subscription** (the maintainer's
choice).
- **The kill and redial are the mechanism:** Sentinel kills every client of a node it reconfigures, so 7a's redial
  asks the sentinels again and ROLE confirms the answer.
- **The client spec** says pub/sub should not substitute for this. redis-py, redis-rs and plain Lettuce do the same.
- **A synchronous client has no thread to listen with** (H19).

**5. The slot map comes from CLUSTER SLOTS on every server.** The outline proposed SHARDS. The reasons:
- SLOTS has one shape on all eight servers, and 6.2 has no SHARDS;
- on 7.2 and later its port is the asking connection's;
- the server leaves out failed and loading replicas itself;
- SHARDS's slot numbers changed type within 7.x, and rueidis documents it as wrong after a failover there;
- Valkey un-deprecated SLOTS, and go-redis, redis-py and redis-rs read it.

**Reading the map:**
- **Endpoints:**
  - `""` or NULL is the asking node's host;
  - `"?"` is skipped;
  - IPv6 splits at the last colon;
  - every count and port is bounded.
- **Where it is read:** from the seeds first, then on a refresh from the live nodes, with the seeds last (H10). The
  first complete answer is taken.
- **What it may hold:** partial coverage is accepted, and an unowned slot goes to any primary, whose answer stands.
  Nodes no longer announced are closed.
- **When it is read again:**
  - on MOVED: the slot is patched at once, so the call follows it, and the whole map is read at most once a second;
  - when a node cannot be reached again;
  - on CLUSTERDOWN.

  There is no timer, and `refreshTopology()` is public.

**6. Redirections, and 7a's rule.**
- **MOVED and ASK** are followed at once, up to `max_redirects` (default 5, Lettuce's). ASK is ASKING and the
  command in one write. When the budget runs out, the call returns the last `Server` error.
- **TRYAGAIN, CLUSTERDOWN, LOADING and MASTERDOWN** are each refused before anything runs. They are waited out with
  7a's backoff, within `reconnect_timeout`.
- **7a's rule holds:** anything that may have run is never sent again.
- **The cluster drives each node's redial** (H2), one paced try (`readyOnce`) at a time:
  1. a transient failure reads the map again;
  2. the call goes where the map now says, since nothing was sent;
  3. the backoff paces the next try.

  So a failover never costs a whole `reconnect_timeout` before the map is read.
- **WATCH and UNWATCH** are refused in the cluster's `call` and `run`; only `watched` sends them, so a WATCH can never
  sit on one node while its EXEC goes to another (H4). ASKING, READONLY and READWRITE are refused too.

**7. The shape.**
- **`redis::Cluster`** owns a 7a `Connection` per node. A node's opens lazily; the seed's opens at connect.
  - It is owned by one isolate, and `Sendable`.
  - The database is honoured, as SELECT on each node.
- **A caller's dialer** comes through a new contract, `Dialers { fn Owned<Dialer> another(); }`, taken by
  `Cluster.connectWith`. One `Owned<Dialer>` cannot serve several links, and a `Shared` is not `Sendable` (H1). It
  gets each node's target, so it can remap an announced address, as redis-py's `address_remap` does.
- **The TLS name checked** is the node's announced endpoint: an IP against IP SANs, a hostname against DNS names.
  `tls_server_name`, when set, applies to every data node.
- **Pipelines:**
  - split by node;
  - every node's batch written before any is read;
  - the replies back in the caller's order;
  - a command redirected or refused before it ran (MOVED, ASK, TRYAGAIN, CLUSTERDOWN, LOADING) sent again, in the
    original relative order;
  - a node lost mid-batch makes its own commands' replies `Io`. `Replies` holds an error per command.
- **Transactions:**
  - every keyed command in one slot, sent to that slot's primary;
  - a redirection while queueing or at EXEC means nothing ran, so the whole transaction is sent again at the owner,
    with ASKING before MULTI for ASK (H6).
- **`watched`:**
  - its keys share one slot;
  - its `TxBody` gets the watching node's `Connection`, unchanged;
  - ASK backs off (H5);
  - a slot that moved between WATCH and EXEC is `WatchConflict`, so the transaction runs again from fresh reads.
- **Scripts:** `eval` routes by the script's keys. NOSCRIPT falls back to EVAL on each node, as today.
- **Replica reads** are opt-in, as at every peer. `read_from=replica` sends a command flagged `readonly` to a random
  online replica of its slot's shard, or to the primary when there is none (Lettuce's REPLICA_PREFERRED).
  - The replica's link sends READONLY in its handshake's one write, so a redial restores it. READONLY stays refused
    in `call`.
  - The README says the read may be stale.
- **SCAN on a cluster** (`Scan.nextIn(cluster:)`) walks each primary in turn. A primary lost mid-scan ends the scan
  with an error. CLUSTERSCAN waits: it would be a second path, tested on one server (H14).

**8. Sentinel is a way of finding the server.** A `Connection` and a `Subscriber` work over it unchanged.
- **Finding the master,** as the client specification says:
  1. the sentinels are asked in order, `connect_timeout` each;
  2. `GET-MASTER-ADDR-BY-NAME`;
  3. the data server's handshake carries ROLE in its one write, and ROLE must say `master` (`slave` for
     `role=replica`). Otherwise the client pauses with 7a's backoff and asks again, within the window;
  4. the sentinel that answered moves to the front;
  5. `SENTINEL SENTINELS` adds sentinels not yet known, a bounded list kept across redials.
- **The errors:**
  - no sentinel reached is `Connect`, with an attempt per sentinel;
  - no sentinel knowing the name, and a master that ROLE never confirms, are the one new variant,
    `RedisError::Sentinel(SentinelError)`.
- **`role=replica`** reads `SENTINEL REPLICAS`, skips those `s_down`, `o_down` or `disconnected`, and picks one at
  random.
- **A `-READONLY` from a sentinel-found master in `call`** loses the link. The call asks the sentinels again and
  sends once more, since its command never ran. In `run` and `transact` the replies stand, and the next call asks
  again.
- **A sentinel connection** never sends SELECT. `tls_server_name` applies to the data servers, and the sentinels are
  checked against their URL hosts.

**9. A 0.1.0 bug the review found** (H13). `Scan.next` sends a cursor from the old server process to a new one after a
redial, so keys are skipped without a word.
- A `generation` count on `Connection` makes such a scan end with an error.
- The CHANGELOG lists it under Fixed.

**10. The breaks, for the CHANGELOG** (0.x allows them):
- the new `RedisError` variant;
- `redis://a,b` read as two hosts;
- a scan across a redial ending with an error;
- READONLY's refusal message.

`TxBody`, `Transport`, `Dialer` and `DialTarget` do not change.

### The session's steps

Each step ends green before its commit:
- `tools/test.sh`, debug and release, on v0.9.667 and on cstar's newest build;
- the live matrix, once it exists;
- the step's mutations (`tools/mutations/6-sN.json`), every one CAUGHT, with live mutations run after the matrix.

0. **Done (2026-10-20).** This plan, and the repros ("Decided, and why", "Phase 6"). KRD-11 filed: cstar's 0.9.684
   refuses `fn int32 main()`, which every tag requires.
1. **Done (2026-10-20).** **Topologies:** `tools/redis.sh up|down|env|cli|logs|smoke --topology cluster|sentinel
   [--server S]`, in containers of their own.
   - **The cluster** (`tests/integration/server/cluster.sh`):
     - three primaries with a replica each, every node in plaintext and over TLS;
     - ports published 1:1 and `cluster-announce-ip 127.0.0.1`;
     - `cluster-node-timeout 2000`, DEBUG enabled where a server has the setting (7.0 and later), and each node in a
       restart loop.

     It is created once, by the image's `redis-cli --cluster create` over the TLS ports, since a CLUSTER MEET's bus
     port is the given port's. Its smoke has 13 checks:
     - the state;
     - CLUSTER SLOTS naming plaintext ports to a plaintext client and TLS ports to a TLS one;
     - MOVED by the asking connection's kind;
     - a replica's WAIT and its read after READONLY;
     - `redis-cli -c` in both kinds;
     - the read-only user;
     - DEBUG.
   - **Sentinel** (`tests/integration/server/sentinel.sh`) is two groups, each a master, two replicas and three
     sentinels monitoring `kr`. A sentinel names the port it monitors, so one group is plaintext and the other TLS
     only, and the TLS group's sentinels want `kr_sentinel`'s password. Its smoke has 14 checks:
     - in each group: one master named by all three sentinels, ROLE on each server, and each sentinel knowing the
       others;
     - ROLE and HELLO 3 on a sentinel;
     - SELECT unknown there;
     - an unknown name a null;
     - the TLS group's NOAUTH, WRONGPASS and refused plaintext;
     - the data servers' own user on the TLS master.
   - **CI** starts both topologies beside each server and runs their smoke. Both pass on all eight servers.
   - **What building it settled:**
     - **6.2 serves both kinds of client.** Under `tls-cluster yes` a node announces its plaintext port beside its
       TLS one (`pport`), and MOVED and SLOTS give a plaintext client that one (R62 cluster.c:444-458, 4370-4373,
       5960-5963). So every server's cluster is TLS on the bus. The review's H12 was wrong.
     - **A node's own links present the test client certificate** (`tls-client-cert-file`). The server's certificate
       is for serverAuth only, and a cluster bus link that presented it stayed in `handshake` for good.
     - **After SENTINEL FAILOVER the old master turns replica only on a later INFO poll,** up to 10 s on. A check in
       between sees two masters. A SENTINEL FAILOVER moved the plain group's master in 2 s, and a CLUSTER FAILOVER
       moved a shard's at once; smoke passed again after each.
     - **The generator cannot capture a reply over TLS:** it runs in `--network none` containers whose Perl has no
       TLS. A reply over TLS has the same shape as one in plaintext, and the port it names is checked live (smoke,
       then the integration suite).
     - **COMMAND INFO, DOCS and GETKEYS move to step 7,** where the table they check is generated.
2. **Done (2026-10-20).** **Vectors** (`tools/gen-topology-vectors.sh` → `tests/unit/src/topology_vectors.kama`): 984
   replies, under both protocols, from throwaway `--network none` containers of all eight images. Two full runs
   give the same file.
   - **The cluster** is six nodes built by hand (`ADDSLOTS` in thirds, `MEET`, `REPLICATE`), so it comes out the
     same every run. What was captured:
     - CLUSTER SLOTS, at a primary and at a replica;
     - MOVED from a primary and from a replica, and CROSSSLOT across shards and within one;
     - MULTI meeting MOVED, then EXECABORT, and EXEC's own CROSSSLOT;
     - a migration: ASK, served, TRYAGAIN, MOVED back without ASKING, ASKING for one command, ASKING then a
       transaction;
     - READONLY and READWRITE, and a keyless write's READONLY;
     - a slot not served, and the map with its gap;
     - the map and MOVED after a CLUSTER FAILOVER;
     - hostnames and an unknown endpoint (7.0 and later);
     - Valkey's zones;
     - MASTERDOWN;
     - the cluster down, in both of its words.
   - **Sentinel** is a group of a master, two replicas and four sentinels, one wanting a password. What was captured:
     - HELLO 3, GET-MASTER-ADDR-BY-NAME known and unknown, and Valkey's GET-PRIMARY-ADDR-BY-NAME;
     - SENTINELS and REPLICAS, and REPLICAS with one down;
     - ROLE three ways;
     - SELECT, CLIENT SETINFO and SETNAME on a sentinel;
     - the password refused;
     - a SENTINEL FAILOVER: `+switch-master` under both protocols, the promoted replica's and the old master's
       clients let go, a BLPOP cut off, the new address, and the old master's READONLY and ROLE.
   - **What moves from run to run is made canonical:**
     - node ids become their ports;
     - Sentinel's times, offsets and run ids become 0 or the port, its lists are sorted by address, and HELLO's client
       id is 0;
     - ROLE's offsets become 0.

     The file's re-encoding keeps each value's RESP form, and a unit test (`topology_test.kama`) reads every reply
     as one whole value, each error a named code.
   - **What the servers showed:**
     - **6.2's source answers a half-migrated MGET with ASK,** where 7.0 and later answer TRYAGAIN. The target's
       TRYAGAIN after ASKING is every server's. So a client must follow an ASK even for a command whose keys are
       partly on the source, and may then meet TRYAGAIN.
     - **A 6.2 replica whose link is down answers a READONLY read with MOVED to its dead primary.** The others answer
       MASTERDOWN (`replica-serve-stale-data no`).
     - **Sentinel's kill lands before the unblock.** The old master's BLPOP client gets no bytes and a close on all
       eight servers, not `-UNBLOCKED`. So do the idle clients of the old master and of the promoted replica.
     - **A sentinel accepts CLIENT SETINFO on 7.2 and later.** 6.2 refuses it, as the handshake already allows.
       SELECT is an unknown command there, in 6.2's backquoted words too.
     - **`CLUSTER SETSLOT … NODE` naming another node leaves the importing node importing.** `STABLE` clears both
       sides.
     - **Valkey 8.1 keeps zones out of CLUSTER SLOTS, and 9.1 puts them in.** Zones travel by gossip, so the script
       waits for all six or none, and for them to go again.
3. **Folded into the steps that use each piece (2026-10-20).** Each piece lands beside its first caller, so its tests
   exercise it through the public API rather than leaving unused code:
   - `generation`, with the Scan fix (step 5);
   - ROLE in the handshake, with Sentinel (step 5);
   - READONLY in the handshake, with replica reads (step 10);
   - `readyOnce` and the grants, with the cluster's core (step 8);
   - `Replies` holding results and `Pipeline`'s offsets, with the cluster's pipelines (step 9);
   - the scripted server's dialer keyed by address, with the first test that dials two places (step 5).
4. **Done (2026-10-20).** **URLs and Config.**
   - **`RedisUrl`:**
     - several hosts, comma-separated, each with its own port (`hostCount`, `hostAt`, `portAt`; `host()` and
       `port()` are the first);
     - `redis-sentinel://` and `rediss-sentinel://` (`isSentinel()`);
     - an empty host in the list refused, as is a list whose first host names no port on redis://, rediss://,
       valkey:// and valkeys://. redis-cli, asked, reads `redis://127.0.0.1,127.0.0.1:7101` as the one host
       "127.0.0.1,127.0.0.1", and `redis://127.0.0.1:7100,127.0.0.1:7101` as its first host, since `atoi` stops at
       the comma.
     The URL vectors gained nine comma forms. The CLI's reading of each is the expectation, or the refusal's
     reason.
   - **`Config`:**
     - the hosts, with 26379 for a sentinel that names no port, and `addHost`;
     - Sentinel: the schemes and `Config.sentinel(masterName:, host:, port:, tls:)`, `master_name` (needed), `role`
       (`SentinelRole::Master|Replica`), and `setSentinelAuth`. Each is refused off a Sentinel configuration;
     - a cluster's `read_from` (`ReadFrom::Primary|Replica`) and `max_redirects` (0 to 100, default 5);
     - the copy constructor copying every new field.
   - **A `Connection` refuses what is not its own,** before it dials: several hosts, and a cluster's options. A
     Sentinel configuration over `connectOver` is refused too. `Connection.connect` refuses a Sentinel configuration
     until step 5 builds it.
   - 30 mutations, all caught.
5. **Done (2026-10-20).** **Sentinel discovery** (unit), in `Connection`, so a `Subscriber` works through sentinels
   too.
   - **`reach` asks the sentinels first** (`askSentinels`), each with `connect_timeout`, its own credentials and no
     database:
     - GET-MASTER-ADDR-BY-NAME, or for `role=replica` SENTINEL REPLICAS (those up, at random; the master when none is
       up);
     - the sentinel that answered moves to the front of a list kept in the `Opener` across redials;
     - SENTINEL SENTINELS adds the sentinels it knows (at most 16);
     - the answer is a configuration for the server named (`Config.forNode`, `forSentinel`).
   - **The role is confirmed** from HELLO's `role` field under RESP3: no extra round trip, and HELLO is every user's,
     where ROLE is `@dangerous`. Only the RESP2 path sends ROLE.
     - A server that says otherwise is asked for again, with a redial's backoff, within `reconnect_timeout`, on a
       first connect and a redial alike.
     - Past that window it is `RedisError::Sentinel`, unconfirmed: "the sentinels named 127.0.0.1:7200 for master kr,
       and its role is replica".
   - **The errors:**
     - no sentinel reached is `Connect`, with an attempt for each;
     - sentinels that answered without an address (none knew the name, a NOAUTH, a reply that is not an address) are
       `Sentinel`, with each one's answer.
   - **`RedisError` and `ServerCode` are now `@nonExhaustive`** (checked across packages: a consumer's `match` needs
     `case _:`). So 0.2.0's new variant is the last one to break a caller.
   - **READONLY from a sentinel-found master:**
     - in `call`, the link goes and the command is sent once more, since it never ran;
     - in `run` and `transact` (while queueing or at EXEC), the replies or the error stand, and the link goes, so the
       next call asks again.
   - **The 0.1.0 Scan bug is fixed:** a scan whose connection was made again (`Connection.generation`) ends with
     `Usage`, sends nothing more, and stays ended.
   - **The vectors gained:**
     - HELLO on a master, a replica and the demoted master;
     - REPLICAS with every replica down;
     - two waits, so that Sentinel's record of a replica is settled before the capture.
   - **The scripted server's dialer can be keyed by address** (`ScriptDialer.byPlace`). A connection that dials
     somewhere it should not then finds a closed port.
   - **Unit tests:**
     - each finding path;
     - the list's order, and a learned sentinel;
     - a replica named, first connect and redial;
     - past the window;
     - `role=replica`, and with none up;
     - RESP2's ROLE;
     - the two sets of credentials, and no SELECT to a sentinel;
     - READONLY in a call, a pipeline and a transaction (both ways);
     - the scan.

     A failed connect in a test is a named failure, not a panic, so that a mutation shows which case caught it.
   - 24 mutations, all caught. The guard against a port that is not a number is proven by its words: removing it
     traps at the port's cast, a crash rather than a named failure.
6. **Done (2026-10-20).** **Sentinel live,** with `examples/sentinel`, on all eight servers, debug and release
   (`tests/integration/src/sentinel_test.kama`, after the TLS tests and before the restarts). Each test waits for its
   group to settle (one master named by all three sentinels, ROLE right on each server, replicas linked), since the
   next test and the release run use the same group.
   - **Found:**
     - the master;
     - `role=replica` reaching a replica, whose READONLY is the call's error;
     - the TLS group, through sentinels that want `kr_sentinel` and refuse a connection without it.
   - **DEBUG SLEEP 9 on the master:** the sentinels fail it over, the connection's calls fail meanwhile (about twenty
     on redis-8.10), and then reach the new master.
   - **SENTINEL FAILOVER under INCRs every 50 ms:** each answered INCR is one more than the last, or two after a call
     that failed. So nothing ran twice, and ten calls in a row then succeed on the new master.
   - **A subscriber across a failover:** Sentinel's kill of pub/sub clients comes back as `Reconnected`, and a message
     published after it is received.
   - **The topology's `failover-timeout` is 3 s now.** A sentinel starts no failover of its own within twice that of
     the last one, and the release run's DEBUG SLEEP comes seconds after the debug run's SENTINEL FAILOVER. The
     containers were made again.
   - **The tools:** `tools/test-integration.sh` starts the sentinel topology and reads its settings, as do
     `tools/check-examples.sh` (`REDIS_SENTINEL_URL`) and `tools/mutate.sh` (each topology's env file, when it is up).
   - 4 live mutations, all caught:
     - not asking the sentinels;
     - `role=replica` not looking for a replica;
     - the sentinels given the server's credentials;
     - a redial that does not ask again.
7. **Done (2026-10-20).** **`redis::cluster`'s pure layers** (unit).
   - **The table of commands** (`tools/gen-command-table.sh` → `src/wire/commands.kama`, internal): 466 commands and
     subcommands from all eight servers' COMMAND output. Each entry has:
     - its key specs (or the legacy first/last/step);
     - `readonly`;
     - its request and response policies.

     The newest server's entry wins. Where servers differ, they differ only in flags (`incomplete`,
     `variable_flags`, `insert`/`update`) and in tips that are not policies. Where a key is found, they all agree.
     The official images load none of Redis 8's modules, so no module command is in it: such a command is refused,
     naming `callFor`.
   - **The check is not circular.** One or two invocations of each command are built from the newest servers' COMMAND
     DOCS, a `numkeys` argument counting the keys after it. Each server's COMMAND GETKEYS of each is captured: 3825
     cases, 2162 with keys and 1663 refused (1567 of those "no key arguments") (`tests/unit/src/command_vectors.kama`).
   - **`keysOf` (src/wire/route.kama) ports the server's own walk** (`getKeysUsingKeySpecs`, R8 db.c:3227-3330):
     - index and keyword begin;
     - range (a limit included) and keynum find;
     - a keyword in any case, never the last argument going forward;
     - numkeys 0 has no keys;
     - a spec that is unknown, incomplete or does not fit makes the reading partial;
     - `not_key` specs (shard channels) count only for routing.
   - **Every case agrees** with its server, as a set: 6.2's own procedures give ZUNIONSTORE's destination last. A
     partial reading must be a subset of the server's keys. One invocation is not compared: on 6.2, a MIGRATE naming a
     key and KEYS together, which no server runs.
   - **Public, in `redis::cluster`** (useful beside a cluster for grouping keys by slot, as go-redis's `MasterForKey`
     and Lettuce's `SlotHash` are):
     - `CommandTable.load()`, with `keysOf(command:)` (what GETKEYS finds) and `slotOf(command:)` (what a cluster
       routes by: shard channels count, keys in two slots are `Usage` naming a hash tag, an unknown command is `Usage`
       naming `callFor`);
     - `SlotMap.fromSlots(reply:, asked:)`, `ClusterNode`, `Redirect.of(error:, asked:)`, `RedirectKind`.
   - **`SlotMap`** reads every server's CLUSTER SLOTS under both protocols:
     - the plain map;
     - the map at a replica, the gap, and after a failover;
     - hostnames;
     - an unknown endpoint, as the node asked;
     - Valkey's zones.

     It refuses:
     - a reply that is not an array;
     - a range out of 0–16383, or ending before it starts;
     - overlapping ranges;
     - more than 1000 nodes.

     A primary that cannot be reached (port 0, or `?` with no ip) serves nothing, and `?` with an ip is that ip.
   - **`Redirect`** reads every server's MOVED and ASK:
     - an empty host is the node asked;
     - a hostname is kept;
     - IPv6 splits at the last colon;
     - a slot or port out of range is refused.
   - **The response-policy aggregates move to step 8,** beside the fan-out that uses them.
   - 21 mutations, all caught. Two had no observable effect and were dropped, each with its reason in this entry:
     - the backward keyword search's bounds: its one user, MIGRATE's KEYS, is an incomplete spec, whose missing keys
       the server's own code finds;
     - the `incomplete` mark: on every captured invocation the keyword search finds what the server's procedure does.
8. **Done (2026-10-20).** **The cluster's core:** `redis::Cluster` (src/cluster.kama).
   - **Connecting:** the seeds in turn, CLUSTER SLOTS from the first that answers (`Cluster.connect`, and
     `connectWith(dialers:)` through the new `Dialers` contract, a dialer for each connection the cluster opens).
     Refused, each in words:
     - a Sentinel configuration, unix:// and reconnect=off (`Config`);
     - a server not in cluster mode, whose CLUSTER SLOTS says "cluster support disabled" on all eight servers
       (`Config`, naming `Connection.connect`);
     - a cluster whose slots are not assigned, whose map is empty (`Unexpected`).
   - **A connection per node,** 7a's `Connection`, opened when a call first goes there. `Config.forNode` gives each
     the cluster's settings without the cluster's own options, and one try per redial. Every node speaks the protocol
     the first settled on, so replies have one shape.
   - **Routing by the table:**
     - a command with keys goes to its slot's primary, and one without to a primary (the first whose link is up);
     - `multi_shard` commands are split by slot, a piece per slot in the order of each slot's first key. MSETEX's
       count is rewritten for each piece, and what follows the keys goes with every piece;
     - `all_shards` commands go to every primary, `all_nodes` ones to every node;
     - the replies are made one by the response policy: key order, a sum, the least, the most, and/or, all or one
       succeeded, or gathered (arrays one after another).
   - **Refused before anything is written:**
     - a `special` command (INFO, RANDOMKEY, LATENCY, SCAN), naming `callEach`;
     - a command the table does not know, naming `callFor` and `callEach`;
     - WATCH and UNWATCH, naming `watched` (step 9), and ASKING.
   - **What the cluster answers:**
     - MOVED is followed, and the map takes it at once (`SlotMap`'s private `moved`). The whole map is read again
       before the next call, but not within a second of the last reading;
     - ASK is ASKING and the command in one write, a pipeline of two. The map is unchanged;
     - TRYAGAIN is waited out, and CLUSTERDOWN, LOADING and MASTERDOWN after reading the map, within
       `reconnect_timeout`. At most `max_redirects` redirections;
     - a node that cannot be opened, or whose one redial fails for a reason that passes (nothing was sent), takes the
       same path. The map is read again (the live links, then the map's nodes, then the seeds), and after a pause the
       call goes where it says. The pause is 7a's backoff, kept across calls; `backoffAfter` and `transient` moved to
       `redis::wire` (src/wire/retry.kama) for both;
     - what may have run is the call's, and is never sent again.
   - **The rest of the API:** `callEach(command:, on: Primaries|AllNodes)` gives `NodeReply`s, each taken once;
     `callFor(key:, command:)`; `eval` at the keys' node, then EVAL there on NOSCRIPT; `refreshTopology()`,
     `topology()`, `close()`.
   - **The vectors gained** (tools/gen-topology-vectors.sh, two runs the same):
     - a node's HELLO;
     - CLUSTER SLOTS before the slots are assigned, and on a standalone server;
     - the pieces of split and fanned-out commands, each at its own node: MGET (one key, and two of one slot), EXISTS,
       MSET, DBSIZE, KEYS, PING and SCRIPT EXISTS.
     One run died without a word on valkey-9.1. Three runs of valkey-9.1 alone passed, and with every topology up
     beside @kama/postgres's ten containers the podman machine is short of memory. A failed container now reports
     its exit status and how far it got.
   - **Unit tests** over scripted nodes, each connection taking the next scripted dialer in the order the cluster opens
     them (`ScriptDialers`), each keyed by its place:
     - routing, an unknown endpoint;
     - MOVED, the map patched, then read again a second on;
     - ASK twice, with the map unchanged; the redirection budget at 1 and at 0;
     - TRYAGAIN, CLUSTERDOWN, LOADING, and a cluster that stays down;
     - a node that will not open; a failover found through an idle link's refused redial;
     - an I/O loss, not resent, then a redial;
     - every split and policy above, and a piece refused as the call's error;
     - each refusal; `callFor`, `eval`, `callEach` on both targets;
     - the seeds in turn, none reached, the protocol pinned, and the empty map.
   - **Live** (tests/integration/src/cluster_test.kama), on all eight clusters, debug and release:
     - a key per shard, every split and fan-out, `eval`, `callFor`, and `callEach`'s six INFOs;
     - a slot moved by hand mid-test. A new key's SET and GET go by ASK while the slot is half moved, MOVED follows
       once it has moved, and it moves back. The keys are MIGRATEd over the cluster's TLS ports, since MIGRATE
       uses TLS under `tls-cluster yes`;
     - TLS at the nodes' TLS ports, and a standalone server refused.

     `tools/test-integration.sh` starts the cluster topology and reads its settings.
   - **38 mutations (36 unit, 2 live), all caught.** Not mutated, each for its reason:
     - a split's one-slot shortcut, since its one piece is the command;
     - closing the links a new map lacks, which no call observes;
     - a node's one-try redial, which changes how long a call takes, not what it returns;
     - `agg_logical_or`, which no command in the table has.
   - **Found:** KRD-11 has a second change with no overlap: a channel's `send` (0.9.680). The live program's socket
     relay uses one.
9. **Done (2026-10-20).** **Pipelines, transactions and `watched` on a cluster.**
   - **The shapes underneath:**
     - a `Pipeline` records where each command's bytes begin, and the cluster reads each back (`Command.decoded`) to
       route it;
     - `Replies` holds a result per command. On a connection that is the server's error reply, as before; on a cluster
       it can also be the failure of a node's link. `take` is unchanged;
     - `Connection.run` is `begin` (settle, ready, one write) and `finish` (the replies), so a cluster writes every
       node's batch before it reads any;
     - `Connection.transact` is `transactAt`, which can send ASKING before MULTI in the same write and reports which
       commands' queueing was answered ASK.
   - **`Cluster.run(pipeline:)`:**
     - a command must stay on one slot: one for every node, one the table does not know, and keys in two slots are
       refused, naming the command, before anything is written;
     - each node's commands go in one batch, every batch is written before any is read, and the replies come back in
       the pipeline's order;
     - a command answered MOVED or ASK goes again where it says (ASKING first, for ASK) in the next round's batch, up
       to `max_redirects` each; TRYAGAIN, CLUSTERDOWN and LOADING are waited out, as is a node that will not open;
     - a node's link lost on the way makes that failure the reply of each command it had, since they may have run;
       the other nodes' replies stand.
   - **`Cluster.transact(pipeline:)`** runs at the node of its keys' slot, which they must share. A redirection while
     queueing means nothing ran, and the whole transaction goes again: MOVED at the new owner; ASK at the importing
     node with ASKING before MULTI, but only when every command with keys was answered ASK. Otherwise the slot is
     waited out until it has moved (see "Decided, and why").
   - **Found live, on valkey-9.1 alone:** in a slot being migrated, Valkey 9.1 queues a transaction's commands and
     answers at EXEC for all of them: ASK when every key is on the importing node, TRYAGAIN when some are still on the
     source. Every other server answers ASK as each command queues, then EXECABORT. An ASK from EXEC now counts every
     command as asked, and TRYAGAIN was already waited out. The generator captures both answers on all eight servers
     (`multi-ask`, `exec-after-ask`, `exec-after-mixed`), and the unit tests replay valkey-9.1's.
   - **`Cluster.watched(watch:, body:, attempts:)`:**
     - WATCH, the body and the transaction run on the watched keys' node, over its one connection, and the
       transaction must stay on their slot;
     - MOVED at WATCH is followed; ASK, and a refusal that ran nothing, are waited out;
     - a slot that moved between WATCH and EXEC runs it all again, from fresh reads;
     - a body that fails, or a transaction off the slot, ends it after UNWATCH.
   - **Unit tests** over scripted nodes:
     - pipelines: four commands over three nodes; MOVED, ASK (the map unchanged), TRYAGAIN; a node lost mid-batch; a
       node that will not open; the budget at 0, and at 1 with two nodes that point at each other (a command's
       redirections count across rounds); every refusal, and the empty pipeline;
     - transactions: one slot; ASK on every key; a slot half moved under the keys, waited out; MOVED while queueing;
       the refusals;
     - `watched`: a conflict then a commit, MOVED at WATCH, a slot moved between WATCH and EXEC, the refusals with
       their UNWATCH.
   - **Live**, in the hand-made reshard, on all eight clusters:
     - while the slot is half moved: a pipeline meets ASK for a new key, a transaction of new keys runs by ASKING at
       the importing node, and `watched` runs at the source on a key still there;
     - once it has moved, a pipeline, a transaction and `watched` from clusters whose maps are stale each meet MOVED;
     - each counter ends at its count, so nothing ran twice.
   - **22 mutations (20 unit, 2 live), all caught.**
10. **Done (2026-10-20).** **Replica reads and the cluster's SCAN.**
    - **`read_from=replica`:**
      - every node's link sends READONLY in its handshake's one write, under both protocols, and again on every link
        made again, through a flag on the node's `Config` that only the cluster sets. It goes to a primary too, where it
        changes nothing, so a node the map later names a replica serves reads at once;
      - a command the servers flag `readonly` goes first to a replica of its slot, at random, and anything that sends it
        again (MASTERDOWN, the link lost) goes to the primary. A write, a command without keys, and a shard with no
        replica go to the primary. In a pipeline, each command is chosen alone;
      - READONLY's refusal on a connection now names `read_from=replica`.
    - **`Scan.nextIn(cluster:)`:**
      - SCAN walks every primary the map named when the scan began, in turn, each from cursor 0 to its 0;
      - SSCAN, HSCAN and ZSCAN go to the primary of their key's slot;
      - a node whose link is made again mid-scan ends it with `Usage`, as `next` does, and so does a key's slot that
        moves to another node. Valkey 9.1's CLUSTERSCAN stays deferred, as planned;
      - `next` and `nextIn` share how a page is read.
    - **Unit tests:**
      - a read at the replica and a write at the primary, alone and in a pipeline;
      - MASTERDOWN sending the read to the primary;
      - RESP2's READONLY, and READONLY again on a replica's link made again;
      - SCAN over three primaries (two pages at the first), SSCAN, a link made again mid-scan, and a key's slot that
        moves mid-scan.
    - **Live**, on all eight clusters:
      - a read after WAIT is served by a replica, by the replicas' own `INFO commandstats`;
      - a SCAN finds all 60 keys across the three primaries;
      - CLIENT KILL on the scan's first primary, mid-scan, ends it.
    - **17 mutations (15 unit, 2 live), all caught.**
11. **Done (2026-10-20).** **`ClusterSubscriber`** (src/cluster_subscriber.kama): a `Subscriber` per node it needs,
    each on a connection of its own, and a `Cluster` of its own for the map.
    - **Where names go:** channels and patterns to one primary (a PUBLISH reaches every node); shard channels to the
      primary of each one's slot, a command per slot. A MOVED to an SSUBSCRIBE reads the map again and sends once more.
    - **`next`:**
      - first what has already arrived on any node (a zero wait each), in turn from the node after the last that gave
        something;
      - then a wait on every node's socket at once with `std::net::Poller`, when this client opened them all. The
        `Opener` records each socket's handle as it opens it (`TcpTransport`'s, granted), so the `Transport` contract is
        unchanged; a TLS link's buffered plaintext is found by the sweep, as R10 showed;
      - over a caller's dialers, which give no socket, a wait on each node in turn, 10 ms at a time (`SLICE_MS`).
    - **What moves under it:**
      - a node's link lost is made again by its next wait (one try, as a cluster's nodes are), and its `Reconnected`
        passes through;
      - a node that cannot be reached again is let go: the map is read again, its names go where it now says, and
        `Reconnected` comes. Names no node takes yet wait for the next call;
      - a shard channel whose slot moved (the old owner's own sunsubscribe) is followed: the map read again until it
        names another owner, within `reconnect_timeout`, SSUBSCRIBE there, and **`Delivery::Moved(channel, to)`**.
        One the new owner refuses, or no new owner, is `Unsubscribed`.
    - **`Delivery` is `@nonExhaustive`**, as `RedisError` is: `Moved` is the last variant to break a consumer's `match`.
    - **The vectors gained** (two runs the same, 1410 replies): a shard channel of shard 1 subscribed at 7001, what
      that connection gets when 7004 takes the shard over (the server's own sunsubscribe, required), and the same
      SSUBSCRIBE at 7004, on every server from 7.0.
    - **Unit tests** (through the in-turn wait: scripted nodes have no socket): a channel and a shard channel delivering
      from two nodes; a shard channel followed across the failover, `Moved` first; the channels' node lost for good,
      placed at another primary after one that would not open; nothing subscribed.
    - **Live** (through the `Poller`), on all eight clusters: a channel, a pattern and shard channels on two shards,
      every message received; a shard channel's slot moved by hand and back, each followed with `Moved` and a message
      from the new owner; CLIENT KILL TYPE pubsub on the channels' node, then `Reconnected` and messages again. Redis
      6.2, which has no sharded pub/sub, runs the rest.
    - **9 mutations (8 unit, 1 live), all caught.** Not mutated: the sweep's turn (it shares the nodes' order fairly;
      no test sees an order), and the `Poller` against the in-turn wait (each delivers the same; only how soon differs).
12. **Done (2026-10-20).** **The cluster live, hardened,** with `examples/cluster`
    (tests/integration/src/cluster_hardening_test.kama, after the cluster's other tests). Each event runs while INCRs go
    on, and each answered INCR must be one more than the last, or two right after a call that failed:
    - **CLUSTER FAILOVER** at the slot's replica: the calls end at it, ten in a row;
    - **DEBUG SLEEP 12** on the slot's primary, past `cluster-node-timeout`: its replica takes over, and the calls
      settle there before the sleeper wakes, so they found it by reading the map, not by its MOVED once awake;
    - **SHUTDOWN NOSAVE** on a primary: its loop brings it back, empty, before the cluster would fail it over, and the
      calls are answered again;
    - **the atomic migrations**, Redis 8.4's `CLUSTER MIGRATION IMPORT` at the target and Valkey 9.0's
      `CLUSTER MIGRATESLOTS` at the source (probed first on redis-8.10 and valkey-9.1: both finish in milliseconds,
      `state completed` and `state success`): the slot moves whole, the calls follow MOVED, and the key holds the last
      INCR's answer. Then it moves back;
    - **the descriptors** the process holds are what they were once the cluster is closed.
    - **`examples/cluster`:** the map, a split MSET and MGET, a transaction under one hash tag, a pipeline over the
      nodes, and a summed DEL. `tools/check-examples.sh` starts the cluster topology and sets `REDIS_CLUSTER_URL`.
    - **2 live mutations, both caught:** MOVED not followed (the failover's calls never reach the new primary), and a
      failed redial not reading the map (the sleep's calls wait for the sleeper's MOVED).
13. **Done (2026-10-20), but for the publish.** **Docs and 0.2.0.**
    - **The README:** the status; Sentinel and Cluster sections, each with a complete program that
      `tools/check-readme.sh` runs against the topologies (it now starts them and puts their URLs in); per-shard
      atomicity said plainly; the URL forms and options; three rows in "could it have run" (`Sentinel`, a redirection
      past `max_redirects`, a split command's failure); the examples; the tests' topologies and generators.
    - **The CHANGELOG's 0.2.0**, with what a caller of 0.1.0 may need to change in one list.
    - **The version** is 0.2.0 in `kama.json` and `libraryVersion()`.
    - **`@kama/tls` ^0.1.6** (released 2026-10-20 for cstar's newest build): the range moved from ^0.1.3, every lock
      pins 0.1.6, and its own floor is still kama 0.9.523.
    - **The gates**, from a clean clone after the dependency moved: `tools/test.sh` on v0.9.667, debug and release,
      every example built; the same on the v0.9.690 tag and on cstar's newest build (0.9.707), through KRD-11's copy;
      `kama check` and `kama build` of the package on 0.9.707, which is the registry's check; the live matrix on all
      eight servers, debug and release, and the examples and the README's programs on all eight.
    - **Found on the way:** on redis-8.2's release run, the CLIENT KILL in the cluster SCAN's test landed between a
      page's idle check and its write, so that page failed on I/O instead of ending the scan. The test now takes either
      outcome, as every CLIENT KILL test here does: after an I/O failure, the next page makes the link again and ends
      the scan. And on redis-7.4 a slot was served by no node: the subscriber's test moved slot 8970 back to its
      primary, and the hardening test's CLUSTER FAILOVER promoted that primary's replica before gossip had told it,
      so the new primary lacked the slot while every other node named it the owner. The client was right (CLUSTERDOWN
      Hash slot not served, waited out, then reported). The tests now wait, after every slot move and failover and
      before the cluster tests start, until all six nodes say `cluster_state:ok` and name the same primary for every
      slot (`settled` in tests/integration/src/cluster_test.kama).
    - **`kama publish --dry-run`** lists no certificate and no agent file.
    - **The floor moved to v0.9.690** (the maintainer's word, 2026-10-20), and CI's pin with it: the ten `main`s and
      the README's programs say `fn uint8 main()`, and the live program's relays take a channel `send`'s `Result`.
      KRD-11 is closed. The gates ran again from a clean clone, on v0.9.690 and on 0.9.707 with no scratch copy, and
      live on the tag.
    - **The floor moved again, to v0.9.707** (2026-10-21, the day it was tagged): `Reader.spare` slides with one
      `copyWithin` (KRD-9, `tools/mutations/krd9-slide.json` aimed at the call), and the 39 test arms that stop end in
      `panic` (KRD-12). The gates ran again from a clean clone on the tag, and live; `@kama/tls` 0.1.6's own tests are
      green on it, so nothing changes there.
    - **Published** 2026-10-21 by the maintainer, from `f9b7d38` (the CHANGELOG's date on `a9df208`, whose CI was
      green).

**If the session runs long:** steps 0–6 (Sentinel complete), then 7–10, then 11–13.

## Phase 4: where to start

The session plan, drawn up on 2026-10-13 from primary sources. It was carried out on 2026-10-18: every step but 5
(client-side caching, 0.3.0's) is done, each noting what it found, and the decisions are under "Decided, and why",
"Phase 4". The sources:
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
    silently. Built (step 2) with a second bound, in bytes: a push can be as large as `maxReplyBytes` on its own,
    so the set-aside pushes hold at most that much too, in a `Deque`, so dropping the oldest costs nothing.
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
2. **Done (2026-10-18).** **A connection's pushes:** `takePushes`, the bound, `droppedPushes`, and `CLIENT TRACKING`/`CACHING` refused.
3. **Done (2026-10-18).** **`Subscriber`, under RESP2 and RESP3.**
   - Unit: every captured confirmation order; messages queued during a subscribe; a timeout that keeps the
     connection; a hangup; the RESP2 refusals; ping's two shapes; `release`.
   - Live: a publisher from a second connection, patterns, a message matched twice, and `release` back to `call`.
4. **Done (2026-10-18).** **Sharded pub/sub, and the server's own `sunsubscribe`.** Unit tests from the cluster captures; live on a
   standalone server; refused on 6.2.
5. **(0.3.0) Client-side caching.** Not in this phase's run for 0.1.0. `CacheConfig`, `enableCache`, `cached`, the
   generated allow-list, the race (pending entries, through the scripted server), and every flush rule. Live: another
   connection's write, FLUSHALL, a key's TTL, reading one's own write, and the bounds. Step 1's COMMAND INFO capture
   serves it then.
6. **Done (2026-10-18).** **Close phase 4:** ROADMAP, AGENTS.redis.md, README (programs checked by `tools/check-readme.sh`), CHANGELOG, the
   module header.

**For 0.1.0:** steps 0–4 and 6. If the session runs long, do 0–3, then 4.

## Phase 5: where to start

The session plan, drawn up on 2026-10-18 from primary sources. The sources:
- **The reference:** redis-cli 8.10.2's and valkey-cli 9.1.2's `cli_common.c` and `redis-cli.c`/`valkey-cli.c`, and
  the hiredis 1.2.0 that Redis 8.10 bundles (`deps/hiredis/ssl.c`).
- **The peers:** go-redis v9.23.0 (`options.go`, `osscluster.go`), redis-py 8.1.0 (`connection.py`), redis-rs 1.7.1
  (`connection.rs`, `tls.rs`), Lettuce 7.9.0 (`RedisURI`, `SslVerifyMode`, `SslConnectionBuilder`), and beside them
  GLIDE v2.5.3 and ioredis v6.0.0. Go 1.25's `crypto/tls`, CPython 3.13's `ssl` and Node 22's `tls` were read where
  a peer leaves the behaviour to them.
- **The servers:** Redis 8.10.2's and Valkey 9.1.2's `config.c` and `tls.c`; the redis.io and valkey.io TLS pages;
  IANA's provisional `redis` and `rediss` schemes.
- **The library:** `@kama/tls` 0.1.2 (`src/`, `csrc/ktls.c`, the vendored Mbed TLS 4.1.1).
- **The model:** @kama/postgres's `src/secure/` and its unit and live TLS tests.

The bar is phase 3's: every form honoured or refused, every failure path against the scripted server, the whole matrix
live, debug and release.

### What the sources showed

- **redis-cli and valkey-cli.**
  - `rediss://` (and `valkeys://` for valkey-cli) turns TLS on. Neither CLI reads a URL's query.
  - Their flags are `--tls`, `--cacert`, `--cacertdir`, `--cert`, `--key`, `--sni`, `--insecure`, `--tls-ciphers` and
    `--tls-ciphersuites`.
  - With no CA given, they trust the system's (`SSL_CTX_set_default_verify_paths`).
  - They verify the chain and **never the host name**: nothing calls `SSL_set1_host`. hiredis gained an opt-in
    `verify_name` only in v1.5.0 (2026-10-15), and redis-cli builds its own `SSL_CTX` in any case.
  - They send **no SNI** unless given `--sni`.
  - They set no minimum version beyond refusing SSLv2 and SSLv3, and do not check that `--cert` comes with `--key`.
  - A setup failure prints `Could not negotiate a TLS connection: <why>` (`Invalid CA Certificate File/Directory`,
    `Invalid client certificate`, `Invalid private key`). A failed handshake prints `Could not connect to Redis at
    <host>:<port>: SSL_connect failed: <OpenSSL's reason>`.
- **The peers agree with one another, and not with the CLIs.**
  - All six verify the chain and the name by default, against the system's trust. A name is matched against DNS
    SANs, and an IP literal against IP SANs.
  - Go, CPython, rustls and Node never send an IP literal as SNI (RFC 6066, section 3). They send the host name
    otherwise, except ioredis, which sends none unless told.
  - Each has a way to verify nothing: go-redis `skip_verify`, redis-py `ssl_cert_reqs=none`, redis-rs `#insecure`,
    Lettuce `verifyPeer=NONE`, GLIDE `InsecureTls`. Lettuce (`CA`), redis-rs (`danger_accept_invalid_hostnames`) and
    redis-py (`ssl_check_hostname=False`) can also verify the chain alone.
  - The footguns: redis-py's `ssl_cert_reqs=none` silently turns its host-name check off too, and its `ssl_ca_certs`
    adds to the system's trust rather than replacing it. redis-rs documents `#insecure` as turning off the host-name
    check, and it turns off every check and SNI. Lettuce's `setVerifyPeer(false)` means NONE, not CA. go-redis's
    cluster URL sends the seed's name to every node.
  - URL options: go-redis reads `skip_verify` and refuses it on `redis://`; redis-py passes every `ssl_*` key through
    as a string; redis-rs reads only the `#insecure` fragment; Lettuce reads `verifyPeer` and ignores unknown keys.
    A CA, a client certificate or a key is set in code everywhere but redis-py.
  - TLS 1.2 is the floor in Go, CPython and go-redis. No peer offers a CA directory but redis-py (`ssl_ca_path`).
- **The servers.**
  - `tls-auth-clients` is `yes` by default: a stock server requires a client certificate. `optional` takes one and
    checks it when it comes.
  - `tls-protocols` is TLSv1.2 and TLSv1.3 by default.
  - Redis 8.10 and Valkey 9.1 can log a client in as the ACL user its certificate's CN names
    (`tls-auth-clients-user CN`; Valkey also reads a URI SAN). Redis 8.2 and Valkey 8.1 cannot.
  - Under TLS 1.3 a server that refuses a client's certificate does so after the handshake has finished on the
    client's side, as an alert at its first read (`tools/redis.sh smoke` already notes it).
- **`@kama/tls` 0.1.2** has what a client needs: `Verify::None`, `Chain` and `Full` (the client's default); trust from
  a file, PEM or the system's bundle (`SSL_CERT_FILE`, then the known bundle paths); a client identity from files or
  PEM, with an encrypted key's password; version bounds (TLS 1.2 and 1.3); a stepwise `handshake()`; and
  `TlsError::Certificate`, which names each check that failed. It lacks two things this package needs:
  - **`TlsError` is not `Sendable`,** and `RedisError` is.
  - **It sends an IP literal as SNI** (Mbed TLS's `ssl_write_hostname_ext` writes whatever name it holds). Its
    ROADMAP records this as a known difference.

  It has no CA directory, no cipher setting and no session resumption.
- **The model.** Postgres's `TransportStream` makes any `Transport` a `ReliableStream`, and `TlsTransport` makes the
  session a `Transport` again, non-blocking end to end. A `TlsConfig` is built for each attempt. Its unit tests run a
  real @kama/tls server inside the scripted server, which checks the SNI it receives. Redis starts TLS at once, with
  no in-protocol request, so postgres's `negotiate.kama` has no counterpart.
- **What here must change with it.** `Connection.targetsOf` and `Opener.open` dial everything that is not `unix://`
  as plain TCP. So no TLS configuration may reach them until all three entry points (`connect`, `connectWith`,
  `connectOver`) secure the link. The scripted server reads what it receives as RESP, so it needs a TLS front.

### Proposed decisions (step 0 confirmed the kama facts by repro; "Decided, and why", "Phase 5", holds them as decided)

The maintainer decided two things on 2026-10-18: the changes `@kama/tls` needs ship as its 0.1.3, and verification has
three modes, each named for what it checks, as the peers' three states are.
- **Verification.** `full`, the default, verifies the chain and the name: a DNS SAN, or an IP SAN for an IP literal.
  `chain` verifies the chain alone (Lettuce's `CA`, and the CLIs' own behaviour). `none` verifies nothing, and only
  `tls_verify=none` or `setTlsVerify` turns it on: no other setting implies it. A CA with `none` is refused, since it
  would never be used.
  - The CLIs' chain-only default is not followed: on this the reference is the outlier, and every peer verifies the
    name.
- **Trust.** The system's bundle by default (`trustSystem`), as the CLIs, Go, CPython and rustls-native-certs do; with
  none found, the connect fails, naming `SSL_CERT_FILE`. A CA given replaces the system's trust, as Go's `RootCAs`,
  redis-rs and GLIDE do (redis-py adds to it). There is no CA directory: `@kama/tls` has none, and neither have Go,
  redis-rs, Lettuce or GLIDE.
- **A client certificate,** with its key: both or neither. A key's password is a setting, never a URL option.
- **The name.** The name verified and sent as SNI is the host, or `tls_server_name` (go-redis's `ServerName`). An IP
  literal is verified against IP SANs and never sent as SNI (`@kama/tls` 0.1.3). TLS over `unix://` is refused.
- **Versions:** TLS 1.2 and 1.3, the servers' default, with `setTlsVersions(min:, max:)`.
- **Left out of 0.1.0:** ciphers (`@kama/tls` has no setting; Mbed TLS's defaults), CRLs and the key log (`@kama/tls`
  has them, and no Redis peer offers them in a URL), and session resumption. Each can come later without changing
  what an accepted setting means.
- **URL options,** refused when unknown as today, and refused on `redis://` and `unix://`, as go-redis refuses
  `skip_verify` there:

  | option | value | default |
  |---|---|---|
  | `tls_verify` | `full`, `chain` or `none` | `full` |
  | `tls_ca` | a PEM file | the system's bundle |
  | `tls_cert`, `tls_key` | PEM files, both or neither | none |
  | `tls_server_name` | a host name or an IP address | the URL's host |
- **Settings:** `Config.tls(host:, port:)` and setters (`setTlsVerify`, `setTlsTrustFile`, `setTlsTrustPem`,
  `setTlsIdentityFiles`, `setTlsIdentityPem`, `setTlsServerName`, `setTlsVersions`), each refused on a configuration
  that is not TLS. Their enums are this package's own (`TlsVerify`, `TlsVersion`): a consumer cannot name a
  `tls::` type without declaring `@kama/tls` itself (step 0).
- **Files are read at each connect,** never by `Config.parse`, as postgres and libpq read them for each attempt. A
  renewed certificate is read by the next connection, which reconnection (phase 7a) will rely on.
- **Errors.** `RedisError::Tls(detail, cause)`, carrying the `TlsError`. A setup failure is worded in redis-cli's
  frame, `Could not negotiate a TLS connection: …`, and a failed handshake in `Connect`'s, `Could not connect to
  <place>: …`, each with `@kama/tls`'s reason. A TLS failure after the TCP connect is final, as `HELLO`'s outcome is,
  so the next address is not tried. The handshake shares the address's `connect_timeout` with the connect and the
  handshake that follows it. An alert after the handshake (a client certificate refused under TLS 1.3) is `Tls` too.
- **The wrong port** is told from the bytes, captured from the servers: `rediss://` at a plaintext port (the server
  answers the ClientHello in RESP), and `redis://` at a TLS port.
- **`Connection.tlsSession()`** gives the version, the cipher suite and the server's certificate.
- **Code.** An internal `redis::secure` module (`transport.kama`, `setup.kama`), from postgres's.

### The session's steps

Each step ends green before its commit:
- `tools/test.sh`, debug and release, on CI's tag and on cstar's newest build;
- from step 2 on, the live matrix.

0. **Done (2026-10-18).** The sources above, the decisions, and the repros ("Decided, and why", "Phase 5").
1. **Done (2026-10-18), published by the maintainer.** **`@kama/tls` 0.1.3,** in `../kama-tls` with its own tests and gate: `TlsError` is `Sendable`; an IP literal is
   never sent as SNI, and `Full` verifies it against the certificate's IP SANs. Published on the maintainer's word.
2. **Done (2026-10-18).** **The PKI, the servers and vectors.**
   - `tools/gen-test-certs.sh` (generation 2) adds a server certificate for another name and an encrypted client key.
   - The locked server gains a TLS port that requires a client certificate (base + 300), and logs one in by its CN
     where the server can. `smoke` checks it.
   - `tools/gen-server-vectors.sh` captures, on all eight servers, the plaintext port's answer to a TLS ClientHello
     and the TLS port's answer to a plaintext `HELLO`.
3. **Done (2026-10-18).** **`Config`:** the settings, the URL options and the refusals. The refusal of a TLS configuration moves from parse
   to connect, in the same words, so nothing dials it.
4. **Done (2026-10-18).** **The TLS layer:** `redis::secure`, `RedisError::Tls`, `tlsSession()`, wired into all three entry points in the
   commit that lifts the refusal. The scripted server gains a TLS front. Unit tests, one byte at a time:
   - verification by name, by IP and by `tls_server_name`, TLS 1.2 and 1.3, another name, another CA, each mode;
   - a client certificate asked for and given, required and missing, an encrypted key and a wrong password, a
     missing file;
   - HELLO, a pipeline through the jammed server, a transaction and a subscriber over TLS, a record split across a
     subscriber's timeout;
   - silence, a hangup at each step, garbage, the servers' plaintext answer, close_notify and a truncated record;
   - no plaintext byte through any entry point.
5. **Done (2026-10-18).** **Live,** on all eight servers, debug and release: both names, both protocols, the system's trust refusing the
   test CA, another CA, another name under each mode, client certificates required and optional, SNI on the wire (read
   by a relay from the ClientHello), a handshake past `connect_timeout`, both wrong ports, a pipeline, a large value, a
   transaction and a subscriber over TLS. A README program over TLS.
6. **Done (2026-10-18).** **Close phase 5:** ROADMAP, AGENTS.redis.md, README, CHANGELOG, the module header.

**If the session runs long:** steps 0–4, then 5, then 6.

## Phase 7a: where to start

The session plan, drawn up on 2026-10-19 from primary sources. The maintainer chose two of its decisions (a subscriber
resubscribes and reports the gap; a redial waits out a restart) and left the rest to this plan's recommendation. The
sources:
- **The peers, at their current tags:**
  - go-redis v9.23.0: `redis.go`, `error.go`, `internal/pool/`, `pubsub.go`;
  - redis-py 8.1.0: `client.py`, `connection.py`, `retry.py`, `backoff.py`;
  - redis-rs 1.7.1: `aio/connection_manager.rs`, `aio/multiplexed_connection.rs`, `errors/`;
  - Lettuce 7.9.0: `ConnectionWatchdog`, `DefaultEndpoint`, `CommandHandler`, `RedisHandshake`, `PubSubEndpoint`;
  - hiredis v1.5.0 (`redisReconnect`) and redis-cli 8.10.2 (`cliConnect`, `issueCommandRepeat`).
- **The servers:** Redis 8.10.2's and Valkey 9.1.2's `networking.c` and `server.c`, and the command flags in
  `src/commands/*.json`.
- **The model:** @kama/postgres's phase 8: S1's `ping()` and `resetSession()`, its pool plan, and `tools/mutate.sh`.
- **`@kama/tls`:** session resumption is its phases 9 and 10, after Windows and WebAssembly. It has not shipped, so a
  reconnect makes a full handshake in 0.1.0. Resumption can come later without changing what any setting means.

The bar is phase 3's: every form honoured or refused, every failure path against the scripted server, the whole
matrix live, debug and release. From this phase on, a test is good only once a mutation of the code it covers makes
it fail (`tools/mutate.sh`, postgres's rule).

### What the sources showed

- **Resending.**
  - **Most peers resend by default, and can run a write twice:**
    - go-redis retries a command three times after an EOF, a reset or a read timeout (`shouldRetry`), and resends a
      plain pipeline whole. There is no per-command opt-out, only `MaxRetries: -1`.
    - redis-py's `Redis(host=…)` retries ten times on any `ConnectionError` or `TimeoutError`, pipelines and unwatched
      MULTI/EXEC included. `Redis.from_url()` retries none: the same application behaves differently by how it was
      built.
    - Lettuce re-queues the commands it sent but has no answer for, and replays them on reconnect
      (`notifyDrainQueuedCommands`). Its `replayFilter` never sees those.
  - **Three never resend:** redis-rs's `ConnectionManager` returns the error and reconnects in the background;
    hiredis's `redisReconnect` drops what was queued; redis-cli prints the error, and the next typed command reconnects.
- **What a reconnect restores.** Each peer restores what its configuration holds: AUTH or HELLO, SELECT, the name and
  CLIENT SETINFO. A user's own SETNAME or AUTH is lost by all of them. Lettuce (`preProcessCommand`) and redis-cli
  (`input_dbnum`) remember a user's SELECT, and the others revert it silently. Lettuce lets a user's AUTH replace its
  credentials provider.
- **Pub/sub.**
  - go-redis, redis-py and Lettuce resubscribe silently. Messages published during the outage vanish, and nothing
    says so.
  - redis-rs resubscribes only when asked (`set_automatic_resubscription`), and forwards a `Disconnection` push.
  - The order is channels, then patterns or shard channels.
  - redis-py undoes an unsubscribe that was in flight when the link dropped.
  - Health checks: go-redis writes a PING every 3 s and never checks the answer. redis-py's is off by default.
    redis-rs and Lettuce have none, and lean on TCP keepalive.
- **A dead idle connection.** go-redis peeks every pooled connection before use (`MSG_PEEK|MSG_DONTWAIT`, not on
  TLS). redis-py reads without blocking on checkout. Neither can close the window between the check and the write.
- **Backoff.**
  - go-redis: 10 ms to 1 s, three retries.
  - redis-py: full jitter, 10 ms to 1 s, ten retries (about 5 s).
  - redis-rs: 100 ms × 2ⁿ, six retries, jittered (about 6–12 s).
  - Lettuce: 1 ms doubling to 30 s, forever, no jitter.
- **Files and credentials at a reconnect.** redis-py and Lettuce read the TLS files again at each connect; go-redis and
  redis-rs do not. Every peer but hiredis calls its credentials provider at each connect. This package already reads
  its TLS files at each attempt (phase 5).
- **The servers.**
  - A server sends nothing when it drops a client: `CLIENT KILL`, the idle `timeout`, a full output buffer and
    SHUTDOWN all close without a byte.
  - At accept, `maxclients` reached writes `-ERR max number of clients reached` and closes. Today the handshake takes
    that ERR for "HELLO unsupported", takes the RESP2 path, and reports the close that follows. That is misleading.
  - During a reload after a restart, HELLO, AUTH, SELECT and CLIENT SETINFO/SETNAME are allowed (they carry the
    `LOADING` flag), but PING and ordinary commands answer `-LOADING`. So a reconnect succeeds while the server still
    loads, and only the first command is refused.
- **The model.** @kama/postgres has no reconnect on a single connection; its pool (phase 8, S3) will replace a broken
  one. Its S2 adds `tools/pg.sh restart`, restart tests and bounds. S6 adds `examples/<name>/`, each its own
  executable project as in @kama/sodium.

### Decisions

**1. A `Connection` redials lazily, on its next call, and never resends.**
- The call that saw a failure returns it, because its command may have run.
- The next call redials, using a copy of the `Config` and the opener (or the caller's `Dialer`), both kept on the
  connection:
  - every address is tried, with `connect_timeout` each;
  - the TLS files are read again;
  - the handshake runs;
  - then the call's command is sent, once.
- A redial asks for the protocol the connection already speaks. It is written into the kept `Config`, so an ERR to
  HELLO cannot quietly move a RESP3 connection to RESP2.
- These stay `Closed`, as today: a connection the caller closed, a `connectOver` connection (it has no dialer), and
  one with `reconnect=off`. `isClosed()` means "every call answers `Closed`".
- The 0.3.0 pool will use `reconnect=off`, and replace a connection itself. (Revised by phase 7b's decision 6: a
  `Cluster` refuses `reconnect=off`, so a lease redials within the lease, and the pool replaces only what is lost when
  it is released.)

**2. A redial waits out a restart.**
- **What is retried within `reconnect_timeout`:** a failed dial, and two failures that only a redial treats as
  transient:
  - the link closing or resetting before the server's first byte, which is what docker-proxy, gvproxy, a Kubernetes
    service or HAProxy do while the server behind them is down;
  - a HELLO refused and then closed, which is how maxclients answers.
- **What stays final:** WRONGPASS, NOPERM, a certificate failure, and a refusal of the pinned protocol.
- **The backoff:** 100 ms doubling to a 1 s cap, jittered. `reconnect_timeout` defaults to 5 s, and `0` is no limit,
  as for the other timeouts.
- **A redial ends with a PING.** `-LOADING` backs off within the window. Any other answer, an error included, means
  the server is serving.
- **The backoff state lives on the connection across calls,** so a caller's tight loop cannot storm a server that is
  down. A failed redial keeps its last round of attempts, with a count of the rounds, so it stays bounded with no
  limit set.
- **New URL options:** `reconnect` (`on` or `off`, default `on`) and `reconnect_timeout`, with setters.

**3. A failed redial is `RedisError::Reconnect`, holding the redial's own error.**
- It says nothing of the call was sent. It is how a caller tells WRONGPASS at a redial from a `Server` error to its
  own command.
- The README gets a table of each error and whether the command could have run.

**4. A zero-time check before a call writes.** It finds a link the server closed while the connection sat idle.
- **How:** `wait(Readable, 0)`, then read until WouldBlock, with a cap. WouldBlock counts as quiet: a TLS 1.3 session
  ticket makes the socket readable and then reads as nothing.
- **What it finds:**
  - **the end of the stream:** the connection is lost before anything was written, so the call redials and sends;
  - **a RESP3 push:** set aside, as today. A partial push stays in the reader (`Reader.pendingKind()`);
  - **anything else:** lose the connection, redial, send.
- **Where it runs:** before the call's deadline starts, and not in a subscriber's `transmit`. On `connectOver` the
  end of the stream it finds is `Io(UnexpectedEof)`, as today.
- **What the docs promise:** "usually invisible". A close can still land between the check and the write.

**5. Session state is refused or recorded, never silently lost.**
- **Refused in `call`, `run` and `transact`, with `Usage` naming the way:** SELECT, AUTH, CLIENT SETNAME, CLIENT
  SETINFO, CLIENT NO-EVICT, CLIENT NO-TOUCH, READONLY, READWRITE, and Valkey's CLIENT CAPA and CLIENT
  IMPORT-SOURCE.
- **Recorded, and restored by every redial:** `Connection.select(db:)` and `Connection.authenticate(user:, password:)`.
  The second answers token rotation (ElastiCache IAM, Entra ID). A credentials provider, a contract called at each
  connect, is carried.
- **Kept complete:** the table is checked against every server's `ACL CAT connection`, as the blocking table is
  against `ACL CAT blocking`.

**6. A WATCH lost with its connection.**
- The connection records that a WATCH is in force. A WATCH answered OK sets it; UNWATCH, `transact` and the last of
  a pipeline's WATCH or UNWATCH update it.
- A loss while it is in force makes the next `transact` answer `WatchConflict` and send nothing, so `watched` tries
  again. MULTI/EXEC never runs on a fresh link without its WATCH; redis-py raises WatchError there.

**7. A `Subscriber` resubscribes and reports the gap.**
- **When it redials:** inside `next`, `ping` and the subscribe calls (nothing was sent, so it is safe). The redial has
  its own budget, so `next(timeout: zero)` can still make one.
- **What it sends:** SUBSCRIBE, then PSUBSCRIBE, then SSUBSCRIBE (one per slot, since a cluster answers CROSSSLOT
  otherwise), from the kept sets. The sets are taken out first, and the confirmations put back what the server
  restored.
- **What the caller sees:** `Delivery::Reconnected(cause)` comes first. It follows what was already queued and comes
  before any message of the new link. Then comes an `Unsubscribed` delivery for each name the server refused (NOPERM,
  MOVED). Nothing is silent.
- **A failed unsubscribe is never undone** (redis-py's bug): its names are left out of what is resubscribed.
- **Which failures redial:** queue overflow, Protocol and Unexpected redial too, and report the gap. `close()` closes
  for good. `release()` on a lost subscriber hands back the connection, which can still redial.
- **No automatic PING health check in 0.1.0.** TCP keepalive (on, 15 s) finds a dead peer; the docs say it does not
  cover a caller's own dialer or `keepalive=0`, and `Subscriber.ping()` is there.

**8. Hardening.**
- **Vectors** for each way a server drops a client.
- **maxclients** is reported as the server's refusal, told by the close that follows the refused HELLO, never by its
  words.
- **Restarts:** `start.sh` keeps the main server in a restart loop, so a live test can `SHUTDOWN NOSAVE` it from
  another connection and watch the client ride the restart.
- **Floods:** a subscriber flooded past the server's pub/sub output-buffer limit comes back `Reconnected`, its memory
  bounded.

**9. Examples, mutations and the docs.**
- **Examples:** `examples/<name>/` executables, published with the package as @kama/sodium's are.
- **Mutations:** a mutations file per step (`tools/mutations/7a-sN.json`).
- **The README:** its links become absolute, because the registry renders a relative link as plain text
  (postgres's S7).

### The session's steps

Each step ends green before its commit:
- `tools/test.sh`, debug and release, on CI's tag and on cstar's newest build;
- from step 1 on, the live matrix;
- from step 2 on, the step's mutations, every one CAUGHT.

While KRD-9 was refusing the reader, the newest tag (`v0.9.673`) stood in for cstar's newest build; since the
reader moves its bytes one at a time, cstar's 0.9.675 builds and passes it too.

0. **Done (2026-10-19).**
   - This plan, from the sources above.
   - The repros ("Decided, and why", "Phase 7a"), on v0.9.667 and cstar's 0.9.675, debug and release.
   - KRD-9, filed when 0.9.675 refused the reader's slide.
   - `tools/mutate.sh`, ported from postgres. Its baseline mutation, `nextReply` no longer losing the connection, is
     CAUGHT by "call: a hangup mid-reply".
1. **Done (2026-10-19).** **Vectors** (`tools/gen-server-vectors.sh`), on all eight servers, captured with `drain`.
   Two runs give the same file (1900 replies), and the existing cases' bytes did not move. What they showed:
   - **Nothing is sent, and the connection closes, on all eight:** CLIENT KILL of an idle client (both protocols) and
     of one in a BLPOP, SHUTDOWN NOSAVE for its caller and for an idle client, and the idle timeout. The script
     requires it, so a server that starts saying goodbye fails the script, not the client.
   - **A restart:** the port refuses while the server is down, and the new server's HELLO is an ordinary one.
   - **A flooded subscriber** gets whole messages, then the end of the stream. What came before the end depends on
     the sockets' buffers, so only the first message is kept.
   - **maxclients** is `-ERR max number of clients reached`, then a close, word for word on all eight.
   - **LOADING:** HELLO, SELECT and CLIENT SETINFO are answered; PING and GET are `-LOADING`. Redis says "Redis is
     loading…" and Valkey "Valkey is loading…", the code the same. 6.2 refuses CLIENT SETINFO there as it always does.
   - **`ACL CAT connection`:** 6.2 lists commands (`auth client command echo hello ping reset …`), and 7.0 and later
     list subcommands too (`client|setname`, `client|no-evict`, Valkey's `client|capa` and `client|import-source`).
   - **Found on the way:** 6.2 refuses `--client-output-buffer-limit "pubsub 64kb 0 0"` as one word, so it is
     given as four. Valkey prints a warning before it daemonizes, so a server the script starts again is silenced,
     and gen.pl now refuses any line that is not a case.
   - `CLIENT KILL`.
   - `SHUTDOWN NOSAVE`, both for an idle client and for the client that sends it.
   - A restart: a refused connect, then a fresh HELLO.
   - `timeout 1`, drained past 2 s.
   - A full output buffer, recorded as its shape.
   - `maxclients 1`.
   - LOADING: `DEBUG POPULATE` and `SAVE`, then a restart under `key-load-delay`, with the debug command enabled by
     product.
   - `ACL CAT connection`.
2. **Done (2026-10-19).** **The handshake.** maxclients is reported as the server's refusal. A handshake during
   LOADING succeeds, and the scripted server proves it. What building it settled:
   - **A refused HELLO followed by a close is the refusal.** The close may come while the write's other replies are
     drained, or in the RESP2 path. It may be an end of stream, or, on a socket the client wrote into after the
     server closed it, a reset (`ConnectionReset`, `BrokenPipe`). The words are never read.
   - **The RESP2 path sends PING when it has nothing else to send** (no AUTH, name or database), with `protocol=2` too.
     Without it, a server that refused the connection could pass for one. Lettuce does the same
     (`pingBeforeActivateConnection`); twemproxy and Envoy answer PING themselves, and the generator reads Envoy's
     `+PONG` from its pinned source.
   - **The scripted server gained `Step::Reset`:** the client's next write into the closed connection draws a reset,
     as on a socket. Through podman's port forwarder, a live connect to a full server sees an end of stream, so the
     reset branches are proven by the scripted server alone.
   - **Live:** `CONFIG SET maxclients 1`, then connects under each protocol, with a password, a database and a name,
     are each the refusal; the limit is put back.
3. **Done (2026-10-19).** **The refactor, with no change in behaviour.**
   - The connection keeps a copy of its `Config` (`settings`) and its opener (`dialing`); `connectOver`'s opener is
     `Opener.none()`, which cannot dial.
   - `establish` takes its opener whole and keeps it. `reach` (static) returns the first address's link, secured,
     with the deadline its handshake has left; `secure` (static) is the TLS step. A redial will call both.
   - `close()` records `shut`, so lost is told from closed.
   - Every test passed unchanged. Two were strengthened so that a mutation of the moved code fails them: a dialer's
     link gets the handshake's deadline (`Patient`), and a dialer's TLS session reaches the connection.
4. **Done (2026-10-19).** **Session state.**
   - The refusals, in `src/wire/known.kama`, and so through `Pipeline.add` and `transact`, each naming its way.
   - `select(db:)` and `authenticate(user:, password:)` send past the table (`exchange`, which `call` shares), check
     their argument with the `Config`'s own setter first, and record what they set in the kept `Config` once the
     server answers OK. That a redial keeps it is step 5's to prove, with the WATCH record, which only a redial makes
     observable.
   - Unit: each refusal names its way and writes nothing, in a call, a pipeline and a transaction. Every entry of every
     server's `ACL CAT connection` is placed: refused, or let through on purpose (ASKING, the reporting CLIENT
     subcommands, COMMAND, ECHO, PING, and WAIT and WAITAOF, which Valkey 8.1+ files there). A new entry fails the
     test until it is placed.
   - Live: `select(db: 3)` writes where a `/3` connection reads; `authenticate` under each protocol, wrong then
     right; SELECT and AUTH themselves refused.
5. **Done (2026-10-19).** **The lazy redial.** `ready()` stands before every call (`exchange`, `run`, `transact`):
   the link as it is, made again once lost, or `Closed`. What building it settled:
   - **A try** is `reach` and `secure` (step 3), the handshake on the new link, then a PING; LOADING to that PING, a
     link closed or reset before the handshake ended (a TLS handshake's `Closed` included), a timeout, no address
     opening and a refusal with the generic `ERR` are retried, anything else is final. A redial's handshake reports a
     close in answer to HELLO as the close it is: the twemproxy hint is for a first connect only.
   - **The protocol is pinned** after the first handshake, in the kept `Config`, so RESP2 (a proxy) stays RESP2, and a
     redial whose HELLO is refused never takes the RESP2 path.
   - **The backoff** (100 ms doubling to 1 s, half of it drawn at random) and the count of failed tries live on the
     connection; each call waits for the backoff, within its own `reconnect_timeout`, and makes at least one try.
   - **`Reconnect`** holds the last try's error and how many tries the call made, in words: "the connection was lost,
     and reconnecting failed (2 tries): …".
   - **WATCH** is recorded from replies answered OK (a call's, or the last WATCH or UNWATCH of a pipeline). A
     transaction clears it before it is sent, since EXEC ends every WATCH. A loss while it is in force makes the next
     transaction `WatchConflict`, unsent.
   - Unit, through `ScriptDialer`, whose scripts are everything a new link must carry, so a resent command meets an
     Expect it does not match:
     - lost mid-call, then the next call alone;
     - refused three times, then up;
     - a link closed and one reset, then up;
     - LOADING waited out;
     - maxclients tried again;
     - WRONGPASS final after one try;
     - down past `reconnect_timeout`;
     - `reconnect=off`, `close()`;
     - RESP2 and RESP3 kept;
     - `select` and `authenticate` restored;
     - four WATCH cases;
     - the backoff across calls;
     - over TLS: a handshake closed, then a TLS 1.2 link, and the CA file replaced on disk refusing the next redial.
   - Live: CLIENT KILL, then a PONG with a new client id; `select(db: 5)` and `authenticate(kr_acl)` outlive a kill
     (`CLIENT INFO`); a timeout, then a redial; `setCommandTimeout` outlives one.
   - 23 mutations, all caught.
6. **Done (2026-10-19).** **The check before a write** (`settle`, `Wire.catchUp`, `Reader.pendingKind`).
   - Before each call writes (`exchange`, `run`, `transact`), the wire reads whatever has arrived, never waiting, at
     most 64 reads. No `wait` is needed: a non-blocking read that answers WouldBlock is quiet. That holds over TLS
     too, where a session ticket reads as nothing, and a read touches none of the scripted server's timing steps.
   - **What it finds** is sorted before an end is acted on, so a push that came whole before a close is kept:
     - pushes are set aside;
     - a push half come stays in the reader;
     - anything else is lost with the link: a reply no call asked for, part of one (an array, a string), or bytes that
       are not RESP.
   - **A lost link** makes the call redial and send; over `connectOver` the call fails with what was found
     (`Io(UnexpectedEof)`, as it did once it wrote). A WATCH lost there holds the next transaction back.
   - **Live:** right after a CLIENT KILL, a call may now be answered rather than fail (the close came first). The
     step 5 checks take either outcome, and require a new client either way. An idle connection killed, then a call
     300 ms later, and the server's `timeout 1` with a 2.5 s wait: each next call is answered, unaware.
   - Unit:
     - a hangup while idle;
     - a push then a close;
     - a stray reply;
     - part of a string reply, and part of an array;
     - a push half come;
     - a WATCH lost while idle;
     - a pipeline;
     - `connectOver`'s `Io`;
     - a close_notify over TLS.
   - 13 mutations, all caught.
7. **Done (2026-10-19).** **The subscriber.** `linked()` stands before `next`, `ping` and each (un)subscribe. It
   makes a lost link again (through two more grants from `Connection`, `ready` and `lost`), queues
   `Delivery::Reconnected(cause)` after what was already queued, and subscribes again from the kept sets. What
   building it settled:
   - **`RedisError` copies:** `ServerError`, `ConnectAttempt`, `ConnectError` and `ReconnectError` gained copy
     constructors, so a subscriber keeps a copy of what ended its link for the `Reconnected` its redial queues, while
     the call that met the loss returns the error itself.
   - **The order:** channels, then patterns, then shard channels, each command's names sorted by their bytes, and
     shard channels one SSUBSCRIBE per slot, in slot order. So every run sends the same, and a cluster takes each.
   - **The kept sets** are taken out before each command and put back by the confirmations:
     - a refused command (NOPERM, MOVED) leaves its names out, each queued as `Unsubscribed`, of any kind now;
     - a link lost again keeps every name not confirmed, for the next redial.
   - **An unsubscribe that failed with the link** forgets what it named (or the whole kind, for an unsubscribe from
     all), so it is never undone. One the server refused changes nothing.
   - **`next`** meets a loss while it waits and makes the link again inside the call, since nothing of it was sent:
     its answer is `Reconnected`, even with a zero timeout. A link over the caller's transport is the call's error,
     as before.
   - **`close()`** is the connection's `close()`, for good. `release()` on a lost subscriber hands the connection back
     as it is, to be made again by its next call.
   - **Unit:**
     - the order;
     - queued before `Reconnected`;
     - NOPERM and MOVED as `Unsubscribed`;
     - two slots;
     - a failed unsubscribe, and a failed unsubscribe from all;
     - a zero timeout;
     - `release`;
     - a failed redial keeping the names;
     - lost again while subscribing again;
     - a subscribe on a lost subscriber;
     - RESP2.
   - **Live:** `CLIENT KILL TYPE pubsub`, then `Reconnected` inside `next` and a later PUBLISH received, under both
     protocols.
   - 13 mutations, all caught.
8. **Done (2026-10-19).** **Live hardening** (`tests/integration/src/restart_test.kama`, last in the program).
   - `start.sh` runs the main server in a loop: `SHUTDOWN NOSAVE` from a connection stops it, and it is back half a
     second later, empty; a TERM to the container ends the loop. The eight containers were made again, and `smoke`
     passes on each.
   - **Riding a restart:**
     - a call (an INCR runs once, on the new server);
     - a pipeline (each INCR once);
     - a BLPOP in flight, which ends with the connection and is not sent again (a value pushed after the restart
       stays in the list);
     - a subscriber (`Reconnected` inside `next`, then a message);
     - a TLS connection, over a new session.
   - **Fifty redials** after CLIENT KILL leave the open descriptors (`/dev/fd`) as they were.
   - **A subscriber flooded** past a lowered `client-output-buffer-limit pubsub` (put back after) reads what came,
     then `Reconnected`, then a later message.
   - **Found:** through podman's port forwarder a connect to a server that is down is never refused. The forwarder
     accepts, then closes. So a live redial meets the closed-before-the-handshake transient, never `Connect` (the
     unit tests prove `Connect`), and the step's live mutation targets the close.
   - 3 live mutations, all caught.
9. **Done (2026-10-19).** **Examples** (`examples/<name>/`), each its own project with a path dependency on the
   package, reading `REDIS_URL` (or `REDIS_TLS_URL`) and checking its own results:
   - the eight: `quickstart`, `typed_replies`, `transactions`, `pubsub_worker`, `job_queue` (BLMOVE into a processing
     list: how to live with a call that may have run), `tls_connection`, `scan`, `scripts`;
   - `tools/test.sh` builds them, debug and release; `tools/check-examples.sh --server S` runs them live. CI's
     integration job now runs it, and `tools/check-readme.sh`, on every server. All pass on all eight servers.
   - **Their `kama.lock`s** resolved `@kama/tls` 0.1.5 (published since), the newest the package's `^0.1.3` admits,
     as a consumer's would. The package's own locks stay on its floor, 0.1.3.
   - **Found on the way:** KRD-10. The TLS example, named `tls`, would not build: a project's name is its root module,
     and it shadowed `@kama/tls`'s for `@kama/redis`'s own imports. It is `tls_connection` now.
10. **Done (2026-10-19).** **Docs and 0.1.0.**
    - **The README:**
      - its status, as of the release;
      - "When the connection is lost", with the table of whether a failed call's command could have run;
      - the subscriber's reconnecting;
      - the examples;
      - the new options;
      - absolute links (the registry renders a relative link as plain text, and `docs/` is not shipped).
    - **The rest:** the CHANGELOG's `[0.1.0] - 2026-10-19`, AGENTS.redis.md, this file, and the module headers
      (`src/redis.kama`, connection, subscriber, config, the `Transport` contract).
    - **The checklist:**
      - `tools/test.sh` checks the version (`0.1.0` in kama.json and `libraryVersion()`);
      - `kama publish kama.json --dry-run` lists no certificate and no agent file, and ships `examples/`;
      - every gate is green.
    - **What remains is the maintainer's:** push, watch CI on the pinned tag, and publish from `../kama-registry`.

**If the session runs long:** steps 0–6, then 7, then 8–10.


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
  field cannot be given out, so `release()` pops it. After that every call, a second `release()` included, is
  `Usage`, naming the release. A subscriber dropped while it holds a connection closes it, through the connection's destructor.
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

- **What building it settled (step 3):**
  - `Subscriber` reaches its connection through five private members `Connection` grants it, method by method:
    `transmit` (write a command), `receiveFrame` (the next value, a failure handed back rather than acted on, so
    `next`'s time passing leaves the connection open), `lose`, `setAside` and `budget`. It sends no command but its
    own (un)subscribes and PING, and builds them with `Command`, whose `problem()` it reads by grant.
  - One classifier reads every frame under both protocols: a RESP3 push, or a RESP2 array told from a reply by its
    first element. It yields a confirmation, a message, RESP2's `["pong", text]`, something to set aside, an error, or
    anything else, which closes the subscriber as `Unexpected`.
  - Confirmations for names given are matched in the order given first (the server confirms them in that order),
    then by search, so a reordering costs nothing but time. An unsubscribe from all ends when its kind's kept names
    are gone.
  - The kept names are three std `Set`s over a small `Name` (bytes, FNV-1a as std hashes a string), since a
    `DynamicArray<uint8>` is `Equatable` but not `Hashable`.
  - The queue is a `Deque` of deliveries with their cost (the frame's footprint, as the reader counts it), bounded by
    `maxReplyBytes`; past it the call fails as `Unexpected` and the subscriber closes, dropping nothing silently.
  - The scripted server gained `Step::Pause`: nothing more of its own accord until the client's next wait comes back
    empty, which splits a message across a `next` timeout.
  - The generator records each scene's setup confirmations as cases too (`sub-three`, `psub-two-after-one`, …), so
    the unit tests replay each scene in the order a server sent it.
  - Live, under both protocols, on all eight servers: a second connection's messages, a pattern, a message matched
    twice, a binary channel with all 256 byte values, a 200 ms wait that ends with None, a publish from another
    isolate while `next` has no limit, NOPERM for `kr_ro`, and `release` back to `call`.
- **What building it settled (step 4):**
  - Sharded pub/sub needed no code of its own beyond step 3's: shard channels are the third kind of kept name, and
    the server's own `sunsubscribe` is the one confirmation no call may be waiting for. One for a name still kept is
    a delivery (`Unsubscribed`), during `next` or queued during a call; one for a name not kept means nothing.
  - From the cluster captures: CROSSSLOT and MOVED are `Server` and the subscriber goes on; the server's own
    sunsubscribe of the last subscription leaves RESP2's subscribed mode, after which PING reads `+PONG` and `next` is
    `Usage`.
  - Live on a standalone server: shard channels in two slots together, SPUBLISH reaching them, a plain PUBLISH not,
    and SUNSUBSCRIBE by name; Redis 6.2 answers SSUBSCRIBE with `ERR unknown command`, and the subscriber goes on.
    Routing a shard channel to the node that serves its slot is phase 6's.

- **What step 0's repros showed** (in the session's scratchpad; each on v0.9.667 and 0.9.668, debug and release):
  - A resource taken by value into a `DynamicArray` of one, used in place through `held[0]`, and handed back by
    `pop()`; a second pop is None.
  - A `friend` grant from one type to another type's private and public methods, across files, reaches private
    fields and methods (`friend r0::Holder::exchange[secret, shut, setAside];`).
  - A `Delivery` enum with a resource payload and a bytes payload, matched with `give`, and handed out of a queue
    with `remove(index: 0)`.
  - `next(timeout: Optional<Duration>)` returning `Result<Optional<Delivery>, E>`.
  - A ctor returning `Result<Holder, E>` that refuses a value it was given hands it to a local first.
  - A type cannot be named `Err`, `Ok`, `Some` or `None` (language names, in every scope).

### Phase 5

Drawn up 2026-10-18 (see "Phase 5: where to start" for the sources and the proposals, which hold unless this section
says otherwise). Step 0's repros, run 2026-10-18 on v0.9.667 and cstar's 0.9.668, confirmed the kama facts underneath.

- **What step 0's repros showed** (in the session's scratchpad, against `@kama/tls` 0.1.2 from the registry):
  - A `TlsStream` over a resource that makes a `Transport`-like contract a `ReliableStream`, inside a resource that
    implements the contract again and is `Sendable`, checks clean on both compilers: postgres's layering carries over.
  - A `Sendable` enum cannot carry a `TlsError` (`tls::TlsError does not declare implements Sendable`). `@kama/tls`
    0.1.3 declares it.
  - `tls::Verify` and `tls::TlsVersion`, enums without payloads, sit in a `Sendable`, `Copyable` resource without
    declaring either.
  - A consumer cannot import `tls::Verify` through this package: it would have to declare `@kama/tls` itself. So the
    settings take this package's own enums.
  - A consumer matches `Tls(detail:, cause:)` on an error that carries a `TlsError` without importing `tls`.
- **redis-cli's words, read at source** (8.10.2, `redis-cli.c:1732–1755`): a setup failure is `Could not negotiate a
  TLS connection: <why>`; a failed handshake leaves the context's error, printed as `Could not connect to Redis at
  <host>:<port>: SSL_connect failed: <reason>` (hiredis 1.2.0, `ssl.c:388–397`).
- **What building it settled (steps 1–6):**
  - `@kama/tls` 0.1.3 gives Mbed TLS no name for an IP literal (`mbedtls_ssl_set_hostname(NULL)`, so no SNI) and
    matches the address against the leaf's IP SANs in a per-session verify callback, under `Full`. Only an IP SAN
    names an address, as in OpenSSL's `X509_check_ip` and Go: a certificate whose CN reads `127.0.0.1` and has no
    SAN is refused for that address (Mbed TLS had compared the CN).
  - **The wrong port, captured on all eight servers:** a ClientHello at the plaintext port gets nothing back and the
    connection stays open (the inline parser's `strchr` stops at the ClientHello's first NUL), so `rediss://` there
    is a `Timeout`, whose message carries no hint. A plaintext HELLO at a TLS port is closed without a byte, so
    `redis://` there is told "A server's TLS port closes a plaintext connection: connect to one with rediss://"
    beside the twemproxy hint.
  - **Words:** a setup failure is `Could not negotiate a TLS connection: invalid CA file "<path>": <reason>` (or the
    client certificate's, naming both files); a failed handshake is `Could not connect to <place>: <reason>`, the
    transport's end being hiredis's "Server closed the connection during the TLS handshake"; a failure after the
    handshake is `the TLS session failed: <reason>`. When the server asked for a client certificate, a refusal adds
    whether none was given ("set tls_cert and tls_key") or the server did not accept the one sent (its alert names
    the certificate: 42–46, 48). Under TLS 1.3 an OpenSSL server's refusal arrives at the first read, HELLO's.
  - **The settings' enums are this package's** (`TlsVerify`, `TlsVersion`), mapped to `@kama/tls`'s in
    `redis::secure`; `RedisError::Tls` carries `@kama/tls`'s `TlsError` all the same, which a consumer matches without
    importing it.
  - **A handshake waiting to read counts only a readable transport** (postgres's loop took either side). A transport
    that is writable while the server says nothing has timed out; the scripted server, always writable, made the old
    loop spin.
  - **The test servers:** the locked server listens on TLS requiring a client certificate (base + 300), and on Redis
    8.6+ and Valkey 9.0+ logs the certificate in as `kr_cert` (`tls-auth-clients-user CN`; Valkey also reads a URI
    SAN). A connection that gives its own AUTH is that user instead.
  - **Live:** on all eight servers, debug and release, both names (`localhost` falls from `::1` to `127.0.0.1` on
    macOS), both protocols, TLS 1.2 when capped, the system's roots refusing the test CA, another CA, another name
    under each mode, client certificates (a plain key, an encrypted key, none, one the untrusted CA signed, the
    optional port checking one), the CN login or its refusal, SNI on the wire through a relay that reads the
    ClientHello, a handshake past `connect_timeout` at a listener that never accepts, both wrong ports, 1000 INCRs in
    a pipeline, a 1 MiB value and a subscriber over TLS.

### Phase 7a

Drawn up 2026-10-19 (see "Phase 7a: where to start" for the sources and the decisions, which hold unless this section
says otherwise). Step 0's repros, run 2026-10-19 on v0.9.667 and cstar's 0.9.675, debug and release, confirmed the kama
facts underneath.

- **What step 0's repros showed** (in the session's scratchpad):
  - A `Sendable` connection can keep a copy of its configuration (a `Copyable` resource) and an opener holding an
    `Owned<Dialer>`, beside its wire.
  - A method can redial in place: assigning a new wire to the field drops the old one, and its transport, at once.
    The arrays the handshake fills are cleared first.
  - A field cannot be passed as the `const ref` argument of a method that writes `this`. The compiler's own words
    are "copy it into a local first", which is what a redial does with its kept configuration (`Config c = copy
    this.settings;`).
  - A `Set` iterates its keys only when the key is `Copyable`, so `Name` gains a copy constructor before a subscriber
    can resubscribe from its sets.
  - An error enum can hold a resource that holds a 0/1 `DynamicArray` of the same enum
    (`Reconnect(ReconnectError)`), and its `message()` can call the inner one's. So can a variant holding the array
    directly. Both build, `Sendable`, in debug and release.
  - `std::time::sleep` and `std::random::Rng.fromEntropy()` are there, both `unsafe`, for the backoff and its jitter.
- **Found on the way:** KRD-9. cstar's 0.9.675 refuses `Reader.spare`'s slide of the unread bytes (two windows of one
  buffer, one written). v0.9.667 and v0.9.673 build it.
- **`tools/mutate.sh`** is postgres's, with `--server S` and this repo's `REDISTEST_*` settings. Each step from 2 on
  adds `tools/mutations/7a-sN.json`.

### Phase 6

Drawn up 2026-10-19 (see "Phase 6: where to start" for the sources and the decisions, which hold unless this section
says otherwise). Step 0's repros, run 2026-10-20 on v0.9.667 and cstar's 0.9.690, debug and release, confirmed the kama
facts underneath.

- **What step 0's repros showed** (in the session's scratchpad):
  - **R1:** a resource element of a field can be handed to a contract method by `ref` (`body.build(conn: ref
    this.nodes[i].held[0], …)`). So `watched` on a cluster gives its `TxBody` the watching node's `Connection`, and
    `TxBody` does not change.
  - **R2:** an element's method can be given another field of `this` by `ref`
    (`this.nodes[i].held[0].relink(opener: ref this.opener)`), under 0.9.675's rule on a `ref` argument that holds the
    receiver.
  - **R3:** a two-level receiver chain mutates in place (`this.nodes[i].held[0].call(…)`).
  - **R4, R5:** a 16384-entry `DynamicArray<int16>` and a `Map<string, isize>` sit in a `Sendable` resource; a lookup
    is `contains` then `getRefMut`.
  - **R6:** a generated table of 450 commands (a resource per command, with its key specs as enums), indexed by a
    `Map` built once, builds in under 2 s, and the whole release program is 118 KB. There is no `match` on a string,
    so a lookup goes through the `Map`.
  - **R7:** a `DynamicArray<Result<…>>` gives up an element with `replace::<Result<…>>(place:, with:)`.
  - **R8:** a static function holding `ref Opener` can make and drop a short-lived connection over `Opener.none()`.
    That is the shape of a sentinel query.
  - **R9:** the root module and a child module can import each other, with a root type granting private members to a
    child's type method by method (`friend app::cl::Cluster::route[readyOnce, generation]`), and a root type taking
    the child's by `ref` (`Scan.nextIn(cluster:)`).
  - **R10:** one `std::net::Poller` watches several sockets at once. Its wait returns when any one is ready, so every
    ready node is drained before the next wait. A peer that closed reads as readable. A TLS transport answers its own
    `wait` at once when the engine holds plaintext (src/secure/transport.kama:131), so a sweep before the `Poller`
    finds that.
  - **R11, R12:** a contract that gains a member breaks every implementer ("missing method"), and an enum that gains
    a variant breaks a consumer's exhaustive `match`. So the `Transport` contract stays as it is, and
    `RedisError::Sentinel` is listed as a break.
  - **R13:** `@nonExhaustive` is accepted on a package's own enum, but a `match` within the same file still needs no
    `case _`. Whether it binds a consumer in another package is for step 5 to check, before `RedisError` takes it.
- **What building the cluster's core settled (step 8):**
  - **A command without keys goes to the first primary whose link is up,** or else the map's first. Lettuce sends
    one to its default connection and redis-py to its default node; go-redis picks at random. A fixed choice reuses
    an open connection and keeps the unit tests' scripts deterministic, and a primary takes a keyless write (EVAL with
    no keys, FUNCTION, PUBLISH) where a replica refuses it.
  - **MOVED patches the map at once, and the whole map is read before the next call,** at most once a second (the
    spec says to read it whole; go-redis waits 200 ms between readings, Lettuce 5 s). The reading is not on the call
    that met MOVED, which has its answer by then.
  - **A split command runs its pieces in turn, and every piece runs even when one fails.** Stopping at the first
    failure would leave the outcome depending on the order of the slots; the caller is told plainly that part of the
    call may have run. Writing every piece before reading any comes with the pipelines (step 9).
  - **A fan-out sends to each node once.** Its nodes are tracked by address across readings of the map, so a node
    that answered is not asked again after a failover, and FUNCTION LOAD cannot meet its own "already exists".
  - **ASK goes as a pipeline of two** (ASKING, then the command) through the node's `Connection.run`, so nothing new
    in `Connection` was needed: the reply is the second's.
  - **ASK while a transaction queues is followed only when every command with keys was answered ASK** (step 9). The
    plan sent the whole transaction to the importing node with ASKING before MULTI on any ASK. But the source answers
    ASK for a command whose key it lacks and queues one whose key it still has, and at the importing node, under
    ASKING, a key it lacks reads as missing. So a transaction over keys half moved would run there without the source's
    values. When some keys were queued, the slot is waited out, within `reconnect_timeout`, until it has moved and
    MOVED says where. A pipeline follows ASK command by command, since nothing ties its commands together.
  - **`readyOnce` was not needed.** A node's `Config` sets `reconnect_timeout` to 1 ms, so its own redial makes one
    try and returns `Reconnect`, and the cluster's loop paces the next.
- **Found on the way:** KRD-11. cstar's 0.9.684 refuses `fn int32 main()`, and every tag (v0.9.667, v0.9.675) refuses
  `fn uint8 main()`. With the ten `main`s edited in a scratch copy, `tools/test.sh` is green on 0.9.690. KRD-9 is
  still open there.
