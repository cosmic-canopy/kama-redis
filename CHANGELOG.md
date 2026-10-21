# Changelog

All notable changes to this package are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/). In 0.x, a minor bump may break.

## [Unreleased]

What a caller of 0.2.0 may need to change:
- `RedisError` gained `Credentials` and `PoolTimeout` (it is `@nonExhaustive`, so a `match` with `case _:` needs
  nothing).
- A `Scan` continued over another connection than the one it began on ends with `Usage` (its message names both
  causes now).

### Added
- A credentials provider (src/credentials.kama): `Credentials`, a contract of yours (`login()` and `fork()`), set with
  `Config.setCredentials` (`hasCredentials`). It is asked at every connect and every redial, for the server's own
  login, and again before a call once its `Login`'s `refreshAfter` has passed, when the connection logs in anew (AUTH)
  before it writes. A subscriber logs in anew where it is under RESP3, and makes its connection again under RESP2.
  It fails closed: a provider's failure, or a login the server refuses, closes the connection.
- `Login` (a user, a password and an optional `refreshAfter`), and `RedisError::Credentials(CredentialsError)`: the
  provider failed (`byServer()` false) or the server refused its login (true); nothing of the call was sent.
- A URL's password, or `setAuth`, beside a provider is refused, and so is a provider beside them; `authenticate` on a
  provider's connection is `Usage`.

- `redis::pool`: `Pool` (`make`, `makeWith` with `PoolDialers`, `join`, `share`, `acquire`), `Lease` (`conn()`, given
  back when dropped), `PoolShare` (Sendable) and `PoolOptions` (`maxSize`, `acquireTimeout`, `lifetime`,
  `lifetimeJitter`, `minIdle`, `idleTimeout`, `healthCheck`, `pingTimeout`). Two channels, no lock: a bound across
  every isolate the pool is shared with. A maintenance isolate keeps minIdle, prunes the idle connections the pool has
  not needed (Npgsql's median), closes those past their lifetime, and probes the idle ones (a fresh login when due,
  then PING within pingTimeout). A release puts back
  only what the lease changed (UNWATCH, SELECT), sent at the release; a connection lost, closed, re-authenticated by
  hand, past its lifetime or whose put-back failed is closed and its place reused. An idle connection the server let
  go is found with no round trip and not lent. `RedisError::PoolTimeout`.
- `PoolDialers`, a contract for a pool's dialers: `another()` for each connection, `fork()` for each isolate.
- `ClusterPool`, `ClusterLease` (`cluster()`) and `ClusterPoolShare`: a pool of whole `Cluster`s, at most maxSize, so
  at most maxSize connections to each node. Release puts back what the lease changed on each node's connection and lets
  a lost one go; a cluster re-authenticated by hand is closed. The maintenance probes each node's connection in turn.

### Fixed
- A `Scan` told links apart by a count of each connection's redials, which starts at 0 on every connection, so a scan
  continued over another connection (another lease's) sent its cursor to another link without a word. Each link now
  draws an identity at random.
- `authenticate` on a connection whose link was lost made it again as the old user first, so a password that had
  been revoked failed the redial for good and the new one was never sent. It now makes the link again as the new user.

## [0.2.0] - 2026-10-21

Cluster and Sentinel (docs/ROADMAP.md, "Phase 6"). Tested live on Redis 6.2–8.10 and Valkey 7.2–9.1, alone, under
Sentinel and as a cluster, debug and release.

What a caller of 0.1.0 may need to change:
- kama ≥ 0.9.707 (was 0.9.667), whose `main` is `fn uint8 main()`: every tag before v0.9.690 requires `fn int32 main()`;
- a `match` on `RedisError`, `ServerCode` or `Delivery` needs `case _:`: each is `@nonExhaustive` now, and
  `RedisError` gained `Sentinel`, `Delivery` gained `Moved`;
- `redis://a,b` is a list of hosts now, which a `Connection` refuses: before, it was the one host `a,b`;
- a `Scan` whose connection was made again ends with `Usage` instead of skipping keys;
- the refusal of READONLY and READWRITE on a connection says something else (`read_from=replica`).

### Added
- Several hosts in a URL, comma-separated (Lettuce's form, and libpq's): `redis://h1:7000,h2:7001`, a cluster's
  seeds. On redis://, rediss://, valkey:// and valkeys:// the first host names its port, as redis-cli reads only it.
  `RedisUrl.hostCount`, `hostAt` and `portAt`; `Config.hostCount`, `hostAt`, `portAt` and `addHost`.
- `redis-sentinel://` and `rediss-sentinel://`, with `master_name` and `role`, and `Config.sentinel`,
  `setSentinelRole` and `setSentinelAuth` (the sentinels' own credentials, set in code only); `SentinelRole`.
- A cluster's options, `read_from` (`ReadFrom`) and `max_redirects`, with `Config.setReadFrom` and `setMaxRedirects`.
- Sentinel: a `Connection` (and a `Subscriber`) through sentinels, as Sentinel's client specification says. The
  sentinels are asked in turn for the master, or a replica that is up for `role=replica`. The one that answered is
  asked first from then on, and the sentinels it knows join the list. The server named must confirm its role (HELLO's
  `role`, or ROLE under RESP2), and one that does not is asked for again within `reconnect_timeout`. Every reconnect
  asks again. A write a demoted master refuses as READONLY is sent once more, since it never ran.
- `RedisError::Sentinel(SentinelError)`: the sentinels were reached and none gave an address, or the server they named
  never confirmed its role. When none could be reached, the error is `Connect`, an attempt per sentinel.
- `examples/sentinel`: the master found through sentinels, and what a failover does to a call.
- `examples/cluster`: a cluster from its seeds, a split MSET and MGET, a transaction under one hash tag, a pipeline.
- `Cluster`: a Redis or Valkey cluster, from its seeds (`Cluster.connect`, `connectWith` with `Dialers`, a dialer for
  each connection it opens). A connection per node, each opened when a call first goes there; the map from CLUSTER
  SLOTS. `call` sends a command where its keys' slot is, and spreads one as the servers' command tips say: MGET, MSET,
  DEL, EXISTS, … split by slot; DBSIZE, KEYS, FLUSHALL, … to every primary; SCRIPT LOAD, CONFIG SET, … to every node;
  the replies made one by the tips' response policy. MOVED is followed and taken into the map, which is read again a
  second later; ASK is ASKING and the command in one write; TRYAGAIN, CLUSTERDOWN and LOADING are waited out within
  `reconnect_timeout`, as is a node that cannot be reached, by reading the map again. At most `max_redirects`
  redirections a call. A command whose reply is each node's own (INFO, SCAN, …) goes through `callEach(command:,
  on:)` (`ClusterTarget`, `NodeReply`); one the table does not know, through `callFor(key:, command:)`. `eval` runs a
  script at its keys' node. `refreshTopology`, `topology`.
- `Cluster.run`: a pipeline whose commands each stay on one slot, a batch per node, every batch written before any is
  read, the replies in the pipeline's order. MOVED and ASK are followed command by command; a node lost mid-batch fails
  only its own commands. `Cluster.transact` and `Cluster.watched`: at the node of the keys' slot, which they must
  share; a redirection while queueing sends the whole transaction again, and a slot half moved under its keys is waited
  out.
- Reads from a cluster's replicas, with `read_from=replica`: a command the servers flag readonly goes to a replica of
  its slot, at random, READONLY sent on every node's link as it is made; one the replica will not serve goes to the
  primary.
- `Scan.nextIn(cluster:)`: SCAN across every primary in turn, and SSCAN, HSCAN and ZSCAN at their key's node.
- `ClusterSubscriber`: pub/sub on a cluster, a `Subscriber` per node. Channels and patterns at one primary, shard
  channels at their slots' primaries; `next` waits on every node at once. A node that cannot be reached again is let
  go and its names placed where the map says (`Reconnected`); a shard channel whose slot moves is followed
  (`Delivery::Moved`).
- `redis::cluster`:
  - `CommandTable`: a command's keys (`keysOf`, as COMMAND GETKEYS finds them) and its slot (`slotOf`), from every
    server's key specifications, checked against every server's GETKEYS;
  - `SlotMap` and `ClusterNode`, a cluster's map from CLUSTER SLOTS;
  - `Redirect` and `RedirectKind`, what a MOVED or ASK says.

### Changed
- Needs kama ≥ 0.9.707 (was 0.9.667), and CI pins v0.9.707. From 0.9.684 kama requires `fn uint8 main()` and refuses
  `fn int32 main()`, which every earlier tag requires, so no program builds on both; the examples, the test programs
  and the README's programs say `fn uint8 main()` now, and a program of yours that uses this package needs the same
  change. 0.9.707 also gives `View.copyWithin`, so the reader moves the unread part of a line to the front of its
  buffer in one copy again, where 0.1.0 moved it a byte at a time (KRD-9).
- Needs `@kama/tls` ^0.1.6 (was ^0.1.3): 0.1.6 builds on kama 0.9.696 and later, where the earlier releases do not.
- `Replies` holds a result per command: on a cluster a reply can be the failure of a node's link as well as the server's
  error reply. `take` is unchanged.
- A `Connection` (and a `Subscriber`) refuses a configuration with several hosts or a cluster's options, before it
  dials. Before, `redis://a,b` was the one host `a,b`.
- `RedisError` and `ServerCode` are `@nonExhaustive`: a `match` on either outside this package needs a `case _:`. This
  release adds a variant (`Sentinel`), and none will break a caller after it.
- `Delivery` is `@nonExhaustive` too, and gains `Moved(channel, to)`, a cluster's shard channel followed to a new node.

### Fixed
- A `Scan` across a reconnect sent its cursor to the new server process, which reads it as another place in its
  table and skips keys without a word. It now ends with `Usage` ("start a new Scan").

## [0.1.0] - 2026-10-19

The first release: a complete client for one server. Needs **kama ≥ 0.9.667**: the first tagged release with the
fixes this package relies on (KAMA_GAPS.md) and with the `Deserializer` the reply reader implements (`peekKind`,
`readNumberText`, `unknownField`, `atKeyedMap`).

### Added
- Reconnection (phase 7a). Nothing is ever sent twice: the call that meets a lost connection fails with what
  happened, since its command may have run.
  - The next call makes the connection again: every address of its configuration, the TLS files read again, the
    handshake in the protocol it spoke, then a `PING`. While the server is down, restarting, full or loading, it keeps
    trying, with a jittered backoff kept on the connection across calls, for up to `reconnect_timeout`. A wrong
    password, a refused certificate or bytes that are not RESP end it at once.
  - `RedisError::Reconnect(ReconnectError)`: the connection was lost earlier and could not be made again, so nothing
    of the call was sent; it carries the last try's error and how many tries the call made.
  - The URL options `reconnect` (`on` or `off`) and `reconnect_timeout` (seconds, 5 by default, 0 for no limit), and
    `Config.setReconnect` and `setReconnectTimeout`. A `connectOver` connection, and one closed with `close()`, stay
    closed.
  - Before each call writes, what came while the connection sat idle is read: a close found there (a kill, the
    server's idle timeout) is made good before anything is sent, and the call never sees it. Pushes are set aside; a
    reply no call asked for loses the connection rather than becoming the next call's.
  - A transaction whose `WATCH` was lost with the connection answers `WatchConflict` without being sent, so
    `watched` runs its body again.
  - `Connection.select(db:)` and `authenticate(user:, password:)`, which every reconnect keeps. `SELECT`, `AUTH`,
    `CLIENT SETNAME`, `CLIENT SETINFO`, `CLIENT NO-EVICT`, `NO-TOUCH`, `CAPA` and `IMPORT-SOURCE`, `READONLY` and
    `READWRITE` are refused by `call`, `run` and `transact`, each naming its way, since a reconnect would quietly
    undo them; the table is checked against every server's `ACL CAT connection`.
  - A server with no room left (`maxclients`) refuses the connection as it accepts it, and the connect fails with
    that refusal, in the server's words. The RESP2 path sends `PING` when it has nothing else to send, so a connect
    always knows its link is open.
  - `RedisError` copies (its payloads gained copy constructors).
  - A `Subscriber` makes its connection again too, by `next` (inside the call) or its next subscribe, unsubscribe or
    ping, and subscribes again to every kept name: channels, patterns, then shard channels a slot at a time.
    `Delivery::Reconnected(cause)` comes first, after what was already queued, so a caller knows messages were missed;
    a name the server refuses then comes as `Unsubscribed`; an unsubscribe that failed with the connection is never
    undone.
- `examples/`: eight programs (quickstart, typed replies, transactions, a pub/sub worker, a reliable job queue, TLS,
  SCAN, scripts), each its own project, built by `tools/test.sh` and run against every server by
  `tools/check-examples.sh`.
- `tools/mutate.sh` (from `@kama/postgres`): each mutation of the source must make the case it targets fail; every
  step of phase 7a has a mutations file, and every mutation is caught.
- `tools/gen-server-vectors.sh` captures how each server lets a client go: `CLIENT KILL`, `SHUTDOWN NOSAVE`, a
  restart, the idle timeout, a full pub/sub buffer, `maxclients`, a server still loading its data, and
  `ACL CAT connection`. The scripted server gained `Step::Reset`, and the live suite stops and restarts the server
  (`tests/integration/server/start.sh` runs it in a loop).
- TLS (phase 5), from `@kama/tls` ^0.1.3, which vendors Mbed TLS:
  - `rediss://` and `valkeys://` connect over TLS, verified by default: the certificate must chain to a trusted root
    (the system's bundle) and name the server, its host name among the DNS names or its IP address among the IP
    addresses. The host name is sent as SNI; an IP address is not (RFC 6066).
  - The URL options `tls_verify` (`full`, `chain`, `none`), `tls_ca`, `tls_cert` and `tls_key` (both or neither) and
    `tls_server_name`, each refused on `redis://` and `unix://`; a CA with `tls_verify=none` is refused.
  - `Config.tls`, and setters for the same, for roots and an identity as PEM bytes, an encrypted key's password, and
    the TLS versions (1.2 and 1.3 by default).
  - `RedisError::Tls(detail, cause)`, in redis-cli's words, carrying `@kama/tls`'s `TlsError`. A TLS failure while
    connecting is final; `connect_timeout` bounds the handshake. A refused client certificate says whether one was
    given.
  - `Connection.tlsSession()`: the version, the cipher suite and the server's certificate, and whether a client
    certificate was asked for and sent.
  - TLS runs over any transport, a `Dialer`'s and `connectOver`'s included; a TLS configuration never carries a
    plaintext byte.
  - `redis://` at a TLS port is told to use `rediss://`: `tools/gen-server-vectors.sh` captures that every server
    closes its TLS port on a plaintext `HELLO`, and says nothing to a ClientHello at its plaintext port.
  - The test servers' locked server listens on TLS too, requiring a client certificate, and logs one in by its CN
    where the server can (Redis 8.6+, Valkey 9.0+).
- Pub/sub (phase 4):
  - `Subscriber`, which owns its connection, under RESP3 and RESP2: `subscribe`, `psubscribe`, `ssubscribe` and the
    three unsubscribes each return once the server has confirmed every name, matched by name; `next(timeout:)` gives
    each `Delivery` (a `Message`, or a shard channel the server `Unsubscribed` on its own), None when the time
    passes with the connection kept open; `ping()`; `release()` unsubscribes from everything and hands the
    `Connection` back. `Subscriber.over`, `connect` and `connectWith`.
  - `Message`: its `ChannelKind`, channel, pattern and payload as bytes, and `channelText()`, `patternText()` and
    `text()`, which refuse bytes that are not UTF-8.
  - `Connection.takePushes()` and `droppedPushes()`: the pushes set aside in place of replies, at most 1024 and
    within `maxReplyBytes`, the oldest dropped and counted past either.
  - `CLIENT TRACKING` and `CLIENT CACHING` join the commands a connection refuses before writing them, until
    client-side caching comes (0.3.0): turned on by hand, invalidations would pile up unread.
  - `tools/gen-server-vectors.sh` captures pub/sub on all eight servers under both protocols: confirmations,
    messages from a second connection, PING's two shapes, refusals, invalidations redirected to a subscriber, and,
    on two cluster nodes joined by hand, CROSSSLOT, MOVED and the server's own sunsubscribe.
- Commands (phase 3):
  - `RedisArg`, a value that writes itself as a command's argument: the integers, `isize`, the floats (shortest
    round trip, `inf`/`-inf`, NaN refused), `string`, `DynamicArray<uint8>` (one binary argument), any
    `DynamicArray` of these (an argument per element) and `Uuid`. `Command.add(value:)` and `argFloat(value:)` take
    them.
  - The `cmd"…"` tag: literal words and whole-argument holes. Text touching a hole, two holes side by side, a quote
    and an empty literal are `Usage`, refused before anything is written.
  - `RedisError::Value`: an argument refused while a command was built (`Command.refuse`), or a reply that does not
    read as the type asked for.
  - Commands a connection does not carry are refused before anything is written: pub/sub, `MONITOR`, `SYNC`,
    `PSYNC`, `CLIENT REPLY`, `SCRIPT DEBUG`, `HELLO`, `RESET`, `QUIT`, `MULTI`, `EXEC`, `DISCARD`.
  - Typed replies through `Deserializable`: `reply::<T>`, `replyOpt::<T>`, `replyOpts::<T>`, `replyRecord::<T>`
    and `replyRecordOpt::<T>`, one rule set for RESP2 and RESP3, every failure naming its place in the reply
    (`reply[1].f2`), a missing field included.
  - Pipelines: `Pipeline` and `Connection.run`, one write and one deadline; `Replies.take` once per reply.
  - Blocking commands wait for their own timeouts on top of `command_timeout`, from a table checked against every
    server's `ACL CAT blocking` and `COMMAND DOCS`.
  - Transactions: `Connection.transact` (MULTI to EXEC in one write) with `TxOutcome { Committed, WatchConflict }`,
    and `Connection.watched` with a `TxBody`, retrying a stated number of times.
  - Scripts: `Script` (SHA-1 computed here), `ScriptCall`, `Connection.eval` (EVALSHA, EVAL on NOSCRIPT), the `_RO`
    forms, and `Pipeline.addScript`.
  - `Scan`: SCAN, SSCAN, HSCAN and ZSCAN a page at a time, with MATCH, COUNT, TYPE and NOVALUES.
  - `resp::Writer.raw(bytes:)`.
  - `tools/gen-server-vectors.sh` captures typed pairs under RESP2 and RESP3 with their setups, transactions,
    scripts, SCAN pages, BLPOP, and each server's blocking commands and their COMMAND DOCS.
  - `tools/check-readme.sh` builds the README's programs and runs them against a live server.
- `redis::Connection`, over TCP or a Unix-domain socket, non-blocking, with `connect_timeout` per address and
  `command_timeout` per call:
  - the handshake is one round trip: `HELLO 3` with `AUTH` and `SETNAME`, then `SELECT` and `CLIENT SETINFO`
    (lib-name `kama-redis`) in the same write;
  - a proxy that refuses `HELLO` gets the RESP2 path (`AUTH`, `CLIENT SETNAME`, `SELECT`). The refusal is told by
    its code: Envoy's from 1.32 to 1.39 each work, and twemproxy's hangup names `protocol=2`;
  - `call` sends a `Command` and returns its reply. A push message in place of a reply is set aside;
  - `connectWith` takes a `Dialer` and `connectOver` a `Transport`, for tunnels, proxies and tests;
  - `server()` gives `ServerInfo`, the server's own account of itself from `HELLO`.
- `redis::Config`: `Config.parse` reads a URL with the options `protocol`, `connect_timeout`, `command_timeout`,
  `client_name` and `keepalive`, and refuses any other. `Config.tcp`, `Config.unix` and typed setters build one
  without a URL. Defaults: 5 s timeouts, keepalive 15 s, RESP3.
- `redis::RedisError`: `Config`, `Io`, `Timeout`, `Protocol`, `Unexpected`, `Server`, `Connect`, `Closed` and
  `Usage`, in hiredis's and redis-cli's words. `ServerError.code()` is a `ServerCode`, read as the server reads
  it, with a variant for each of the 36 codes the servers send.
- `tools/gen-server-vectors.sh`: the codes the servers can send, read from their binaries; each server's replies to
  every handshake step and error; Envoy's answers to `HELLO`, from its source.
- `tests/integration`, run by `tools/test-integration.sh` on all eight servers, debug and release, and in CI.
- `redis::resp`: `Value` (every RESP2 and RESP3 type), `Reader` and `Writer`.
  - The reader is incremental, reading the socket straight in through `spare`/`commit`, and bounded by
    `resp::Limits`.
  - It matches hiredis v1.4.1 on 593 vectors from hiredis's tests, the RESP specification and eight live servers.
    It also reads RESP3's blob errors, streamed forms and attributes.
- `redis::RedisUrl`:
  - `redis://` and `rediss://` as redis-cli 8.10 reads them, and `valkey://` and `valkeys://` as valkey-cli 9.1
    does, each asked live;
  - `unix://` as redis-py and go-redis document it;
  - a refusal, saying how to write it, for anything a CLI would misread.
- `redis::cluster`: `crc16`, `keySlot` and `SLOT_COUNT`. They are checked against the cluster specification and
  against `CLUSTER KEYSLOT` on Redis 6.2–8.10 and Valkey 7.2–9.1.
- Vector generators: `tools/gen-resp-vectors.sh` (with `tools/resp-dump.c`), `tools/gen-slot-vectors.sh` and
  `tools/gen-url-vectors.sh`.
- Registry metadata in `kama.json` (`description`, `repository`, `keywords`), new in kama 0.9.523, so the
  registry's catalog and `kama pkg search` can say what the package is.
- The package scaffold: manifest, agent files, hermetic unit-test program (`tools/test.sh`).
- The integration servers: `tools/redis.sh` runs the official Redis (6.2, 7.2, 7.4, 8.2, 8.10) and Valkey (7.2,
  8.1, 9.1) images under podman or docker, with TLS on and one ACL user per authentication case;
  `tools/gen-test-certs.sh` generates their throwaway PKI. `tools/redis.sh smoke` passes all 16 checks on
  Redis 6.2.24, 7.2.16, 7.4.11, 8.2.10 and 8.10.2, and Valkey 7.2.14, 8.1.10 and 9.1.2.
