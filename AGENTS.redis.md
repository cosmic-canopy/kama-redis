# @kama/redis — what is true in THIS repo

The two generated files carry the general rules: `AGENTS.md` covers the language, and `AGENTS.package.md`
covers what a publishable library needs. `kama agents install` writes both, so they are **not**
hand-edited; a re-install rewrites them. This file is the project-specific third, and it is the one to
edit.

**Read [docs/ROADMAP.md](docs/ROADMAP.md) first.** It gives the order of work, where the next phase starts, and every
decision made so far with its reason. Read [KAMA_GAPS.md](KAMA_GAPS.md) for the compiler gaps this package has hit.

**The sibling `@kama/postgres` (`../kama-postgres`) is the model.** It is the same kind of package (a native wire
protocol over `std::net`, a non-blocking `Transport` with deadlines, TLS from `@kama/tls`, typed values through
`Deserializable`, a scripted fake server), and its `AGENTS.postgres.md` records what it took to get there. Read
the matching part of its code before designing something here. Copy what fits; do not depend on it.

- **A gap goes in KAMA_GAPS.md the moment it is hit**, reduced to a repro and run on the named compiler.
  The cstar project reads that file and fixes from it, usually within a session. So do not build a
  workaround you would not want to delete. If a workaround is unavoidable, name it in the entry.

**The package needs kama ≥ 0.9.667**, declared as `"kama"` in every manifest here, and CI pins `v0.9.667`. That is the
first tagged compiler with everything this package relies on (users install tagged releases):
- the registry keys `description`, `repository` and `keywords` in `kama.json` (0.9.523);
- `copy` through an enum whose payloads copy, `Optional<string>` included (0.9.527, KRD-4);
- `DynamicArray.addAll`, `View.copyFrom` and `capacity()`, one `memcpy` each (0.9.528, KRD-3);
- an isolate's stack stated as the main thread's, which `resp::Limits.maxDepth` = 1024 relies on (0.9.529, KRD-2);
- one adapter vtable per release build, however many files convert (0.9.543, KPG-38);
- `std::memory::replace` (0.9.563), which `Replies.take` uses;
- std's `deserialize` reading a program's types in the program's scope (0.9.565, KRD-8), and an adapter's signature
  read in the adapter's module (0.9.566, KRD-7), which the bytes, list and Uuid adapters need;
- `DeErrorKind`, `failWith(kind:)` and `DeError.field()` (0.9.569), which the reply reader implements;
- the `Deserializer` members `peekKind`/`readNumberText`, `unknownField` and `atKeyedMap` (all in v0.9.667), which the
  reader implements too, and `std::memory::replace`, which `ServerInfo` reads its HELLO reply with (v0.9.667's
  borrow rule refuses a borrow of a field across a call that may write it).

Verified on v0.9.675 (2026-10-19, the build the registry published 0.1.0 with), and for 0.2.0 on v0.9.667 and on the
v0.9.690 tag (2026-10-20, through KRD-11's scratch copy, since that tag refuses `fn int32 main()`), so the floor and
the pin stay: `ci.yml` moves the pin only with the floor. Gate on CI's tag, and on cstar's newest build when it has one (`~/Documents/cstar/out/<platform>/kama`): that build
is under active work and has regressed before (KRD-8; KRD-9, where 0.9.675 refused `Reader.spare`'s copy). **The
registry checks a publish with cstar's newest build**, so a package that only builds on the tags does not publish:
gate on that build too before calling a release ready. Install a tag beside your own with cstar's `install.sh`
(`KAMA_HOME=<dir> KAMA_VERSION=v0.9.667`), and run the gates with `KAMA=<dir>/bin/kama`.
- **KRD-11, since cstar's 0.9.684:** it refuses `fn int32 main()`, which every tag requires, and every tag refuses `fn uint8
  main()`. The library is unaffected. Gate the newest build on a scratch copy whose ten `main`s (`tests/*/src/main.kama`,
  `examples/*/src/main.kama`) say `fn uint8 main()`. When a tag carries the rule, the floor, CI's pin and the `main`s
  move in one commit.

**Every step of a phase is proven by mutation** (`tools/mutate.sh tools/mutations/<file>.json`, `--server S` for the
live ones): each mutation of the source must make the case it names fail, or the test is not good yet. A step adds
its file (`tools/mutations/7a-sN.json`); re-run the older files when their code changes, since a `BAD-PATTERN` means
the source moved on. Run the live mutations after the matrix, not beside it: both use the same servers.

## What is true here and nowhere else

- **Native protocol, no C.** This package speaks RESP2 and RESP3 in kama over `std::net`. There is no hiredis,
  no `csrc/` and no `csources`, and it should stay that way. TLS comes from `@kama/tls` (`../kama-tls`, on the
  registry), which vendors Mbed TLS. What this package needs from TLS that `@kama/tls` lacks is added THERE, with
  its own tests, not worked around here: 0.1.3 (no IP address as SNI, an IP matched against IP SANs alone,
  `TlsError` `Sendable`) was this package's ask.

- **TLS is `redis::secure`, internal** (src/secure/), postgres's layering: `TransportStream` makes any `Transport` a
  `ReliableStream`, and `TlsTransport` makes the session a `Transport` again. `Connection.opened` secures a TLS
  configuration's link for all three entry points (`connect`, `connectWith`, `connectOver`) before HELLO, within the
  address's `connect_timeout`, and nothing else dials one: a TLS configuration never carries a plaintext byte. A
  `TlsConfig` is built for each attempt (`prepareTls`), so files are read at connect, never by `Config.parse`. The
  settings' enums are this package's own (`TlsVerify`, `TlsVersion`): a consumer cannot name a `tls::` type without
  declaring `@kama/tls` itself.
  - A handshake that waits to read counts only a readable transport. The scripted server is always writable, so a
    loop that took either side spun on a silent server.
  - The scripted server's `secure` runs Mbed TLS as the server, checks the SNI it receives (`"-"` for none), and
    sends each step's bytes as records of their own, as a server does; `Truncate` ends a reply mid-record with no
    close_notify. The unit tests read the PKI through `REDISTEST_CERTDIR`, which `tools/test.sh` sets after running
    `tools/gen-test-certs.sh` (OpenSSL or LibreSSL).

- **A lost connection is made again by its next call, and nothing is ever sent twice** (docs/ROADMAP.md, "Phase
  7a"). Keep it that way.
  - Every call path goes `settle()` (what came while idle: a close found there is made good before anything is
    written), then `ready()` (the link, or `redial()`), then writes. The call that meets a loss returns it.
  - A redial is `reach` + `secure` + the handshake (`again: true`) + a PING. `transient()` decides what is tried
    again within `reconnect_timeout`; its backoff lives on the connection across calls. The protocol is pinned in
    the kept `Config` after the first handshake, and `select`/`authenticate` record what they set there.
  - Through podman's (or docker's) port forwarder a server that is down is never refused: the forwarder accepts,
    then closes. A live redial meets that close, not `Connect`.
  - A WATCH lost with the link makes the next transaction `WatchConflict`, unsent.
  - Commands that set what a connection is (SELECT, AUTH, CLIENT SETNAME, …) are refused in `call`; the table is
    checked against every server's `ACL CAT connection`, so a new server's entry fails a test until it is placed.
  - A `Subscriber` redials in `linked()`, queues `Reconnected(cause)`, and subscribes again from the kept sets
    (sorted, shard channels a slot at a time). `RedisError` copies, so the cause is kept while the failed call returns
    it.

- **Two test programs, and neither is typed from memory.**
  - `tests/unit` is hermetic. It needs no server and no network, and runs through `tools/test.sh`, debug and
    release. Its scripted server (`fake_server.kama`) is an in-memory `Transport` that plays real servers' bytes from
    the vectors, a byte at a time, written three bytes at a time, for every hostile path: silence, late replies,
    hangups at every step, garbage, oversized lengths, a server that stops reading.
  - `tests/integration` needs a live server. `tools/test-integration.sh` runs it on every server in the matrix,
    debug and release (`--server S` for one), and CI runs it after `smoke`.
    - Its Unix-socket test listens on a socket of its own and relays to the server's TCP port, because macOS cannot
      reach the container's socket (as postgres's `socket_test` does).
    - It starts with FLUSHALL, so the debug and release runs share the server cleanly.
    - `restart_test.kama` runs last: each restart loses every other connection to the server.
    - Right after a CLIENT KILL, a call is either answered (the close was found before it wrote) or fails on I/O; a
      test takes either, and checks that the connection came back as a new client.
  - The scripted server's steps include `ExpectBytes` (a command's binary arguments, byte for byte), `Patient`
    (a reply given only to a wait that allows a stated time, which shows how long a connection waited) and `Pause`
    (nothing more of the server's own accord until the client's next wait comes back empty, which splits a message
    across a subscriber's timeout).
  - `tools/check-readme.sh` builds every complete program in README.md and runs it against a live server.
  - Vectors come from upstream by script. Each generator pins every upstream file by SHA256 and dies on a
    mismatch. Run it, and `git diff` must be empty unless a server image moved.
  - `tools/gen-resp-vectors.sh` writes `resp_vectors.kama`, with hiredis v1.4.1's reading of every input:
    - its inputs are hiredis's own reader tests, every example in RESP3.md and protocol-spec.md, what all eight
      servers send for 29 commands under RESP2 and RESP3, and a hostile list;
    - `tools/resp-dump.c` (generator-only C, never shipped) compiles hiredis's `test.c` with `redisReaderFeed`
      wrapped to capture those inputs, then replays any input through hiredis;
    - an input in what hiredis lacks reads as hiredis reads its equivalent (`canon` in the script);
    - a deliberate difference from hiredis goes in `%DEVIATIONS` with its reason, and is never silent;
    - a case that is malformed in a RESP3 form hiredis lacks has no upstream reading, so the script refuses it.
      Test such a case in `resp_test.kama`.
  - `tools/gen-slot-vectors.sh` writes `slot_vectors.kama` from the cluster specification's check value, its
    crc16tab and its tag examples, plus `CLUSTER KEYSLOT` on all eight servers, which must agree.
  - `tools/gen-url-vectors.sh` writes `url_vectors.kama` from redis-cli 8.10 and valkey-cli 9.1, given each URL
    beside a recorder. Its `misread` rules are the URLs this package refuses although the CLI accepts them.
  - `tools/gen-server-vectors.sh` writes `server_vectors.kama`, for the connection's tests to replay:
    - the error codes each server can send, read out of its own binary in the image (each `-CODE message` literal,
      and MOVED and ASK from cluster.c's format); `ServerCode` must name every one;
    - each server's raw reply to every handshake step and to every error a standalone server can be made to send;
    - the wrong port (phase 5): what the plaintext port sends back to the image's own `redis-cli --tls` ClientHello
      (nothing, and it stays open: the inline parser's strchr stops at the ClientHello's NUL), and what a TLS port
      does with a plaintext HELLO (closes). The script requires both, since the client's words rest on them;
    - Envoy's redis proxy's answers to HELLO at 1.32, 1.36 and 1.39, from its pinned source, in the order that
      source checks them. The script verifies that order before it uses it. And its own `+PONG` to PING, which the
      RESP2 path sends when it has nothing else to send.
    - how a server lets a client go (phase 7a): CLIENT KILL (idle, and in a BLPOP), SHUTDOWN NOSAVE (its caller and
      an idle client), a restart, the idle timeout, a flooded subscriber, `maxclients`, a server reloading its data
      (`key-load-delay` with 1 MiB values saved uncompressed, since 6.2 serves its event loop only every 2 MB while
      it loads), and `ACL CAT connection`. The script requires no bytes and a close for each drop, the words of
      maxclients, and LOADING's refusals; it also refuses any line that is not a case (a server that printed).
    - typed pairs (phase 3): each case under RESP2 and RESP3 on a fresh connection after FLUSHALL, with its setup
      written beside it (`replySetups`), so tests derive expected values from the setup; transactions, scripts,
      SCAN pages and BLPOP; each server's `ACL CAT blocking`, sorted, and COMMAND DOCS's arguments for each
      blocking command. Every capture must come out the same on every run (intsets, explicit stream IDs).
    - pub/sub (phase 4): scenes on a pair of connections (a subscriber and another client) under both protocols,
      every step's confirmations recorded as a case of its own, so a test replays a scene in the order a server sent
      it. An unsubscribe-all confirms in the order of a hash Redis seeds at random in each process, so the script
      checks the names and counts and records one canonical order (`canonical()`); the unit test plays every order.
      Two cluster nodes joined by hand (ADDSLOTSRANGE, CLUSTER MEET: `redis-cli --cluster create` wants three)
      give CROSSSLOT, MOVED and the server's own sunsubscribe. Run it twice: the two outputs must be the same.
    A case that needs a server setting Redis lacks (Valkey's `extended-redis-compatibility`) is started by
    product: Redis 8 passes a setting it does not know to its modules and fails only after daemonizing.
  - The live parts run in throwaway `--network none` containers of the matrix's images. They never touch the
    `tools/redis.sh` servers.
  - The unit program's run-time tests check properties instead: every split of an input reads the same, every
    prefix of a reply is incomplete, and what the writer writes reads back.

- **The examples** (`examples/<name>/`, each its own project with a path dependency on the package) are built by
  `tools/test.sh` and run live by `tools/check-examples.sh --server S`, as `tools/check-readme.sh` runs the README's
  programs; CI's integration job runs both. They read `REDIS_URL` (and `REDIS_TLS_URL`, `REDIS_SENTINEL_URL`, `REDIS_CLUSTER_URL`) and check their own results.
  Their `kama.lock`s pin the newest `@kama/tls` the package's range admits, as a consumer's would; the package's own
  locks pin its floor. No example (nor any project using this package) may be named `tls`: KRD-10.

- **`tools/redis.sh` is the server.**
  - It runs the official images under podman or docker: `redis:6.2`, `7.2`, `7.4`, `8.2` and `8.10`, and
    `valkey/valkey:7.2`, `8.1` and `9.1`. `tools/redis.sh list` names them, and `--server redis-7.4` picks one.
  - One container per server runs two servers, configured from `tests/integration/server/`:
    - the main server, in plaintext and over TLS (`tls-auth-clients optional`), and on a Unix socket in the
      container. `start.sh` runs it in a loop, so a live test can stop it (`SHUTDOWN NOSAVE`) and it is back, empty,
      half a second later; a container made before that loop existed must be made again (`down`, then `up`);
    - the locked server, whose default user has a password, for NOAUTH and the single-argument AUTH, and over TLS
      requiring a client certificate (`tls-auth-clients yes`). `start.sh` gives it `tls-auth-clients-user CN` on
      the servers that have the setting (Redis 8.6+, Valkey 9.0+), so the client certificate logs in as `kr_cert`.
  - Each container gets four host ports, bound to 127.0.0.1: base, base + 100 (TLS), base + 200 (locked) and
    base + 300 (locked, TLS). `out/redistest-<server>.env` holds them.
  - There is one ACL user per authentication case. A test picks the case by picking the user:
    - `default`: no password;
    - `kr_acl`: a user with a password;
    - `kr_ro`: read commands only;
    - `kr_off`: disabled;
    - `kr_nopass`: any password.
  - `tools/redis.sh smoke` checks each case and transport with the container's own redis-cli. When an
    integration test fails, run it first: it separates "the server is misconfigured" from "the client is wrong".
  - The test PKI is generated into `out/test-certs` by `tools/gen-test-certs.sh` and is never tracked: a CA and an
    untrusted one, the server's certificate (localhost, 127.0.0.1, ::1) and one for another name, a client
    certificate, its key encrypted, and one the untrusted CA signed. `kama publish` refuses a tracked `*.key`, and
    so does the registry.
  - The live TLS test relays through a listener of its own that reads the ClientHello's server name (SNI on the
    wire), and meets silence at one that never accepts. An accepted stream starts in its listener's mode (on every OS
    since kama 0.9.671, on macOS before it too): set it blocking before reading from a non-blocking listener.
  - **The topologies** (phase 6): `--topology cluster|sentinel` on `up`, `down`, `env`, `cli`, `logs` and `smoke`. Each
    runs in a container of its own (`kama-redis-cluster-S`, `kama-redis-sentinel-S`), its settings in
    `out/redistest-<topology>-S.env`.
    - Their ports are published 1:1 and announced as 127.0.0.1. A server names its peers' addresses to clients
      (MOVED, CLUSTER SLOTS, GET-MASTER-ADDR-BY-NAME), and such an address must mean the same inside the container and
      out. The ranges are 17000 + 20k (cluster) and 18000 + 20k (sentinel), where k is the base port less 16300.
    - **The cluster** is three primaries with a replica each (`tests/integration/server/cluster.sh`), every node in
      plaintext and over TLS, with `tls-cluster yes` on every server. Under it, 6.2 gives a plaintext client the
      plaintext port too (`pport`). It is created once, over the TLS ports, since a CLUSTER MEET's bus port is the
      given port's. A test that MIGRATEs keys between nodes names the target's TLS port: MIGRATE uses TLS under
      `tls-cluster yes`.
    - **Sentinel** is two groups, each a master, two replicas and three sentinels monitoring `kr`
      (`tests/integration/server/sentinel.sh`). A sentinel names the port it monitors, so one group is plaintext and
      the other TLS only. The TLS group's sentinels have their default user off: log in as `kr_sentinel`.
    - **A node's own links** (the cluster bus, replication, a sentinel's connections) present the test client
      certificate (`tls-client-cert-file`). The server's certificate is for serverAuth only, and a bus link that
      presents it never completes its handshake.
    - Every server and sentinel runs in a restart loop, as the standalone server does.
    - **After a failover, wait before checking.** Sentinel turns the old master into a replica only on a later INFO poll,
      up to 10 s on, so a check right after SENTINEL FAILOVER can see two masters. The smoke checks pass again once it
      settles.

- **`redis::resp`'s reader is built so that nothing is read twice and memory follows the bytes that came.** Keep it
  that way when changing it. The rules are in `src/resp/reader.kama`'s header:
  - Lines are searched once (`scanned`).
  - Payloads leave the buffer as they arrive (`addAll`), into a string that doubles as it grows but never past its
    declared length.
  - Open aggregates are plain `Frame` values over one `vals` stack. Nothing is allocated from a declared count.
  - The first error is final, and `ProtocolError` has scalar payloads so it can be handed back on every call.
  - `spare`/`commit` let a connection read straight into the buffer.

- **`RedisArg`'s adapters write through `Command`'s `arg*` methods**, and `uint8` has none on purpose: that is what
  lets `DynamicArray<uint8>` be bytes (one argument) beside `<DynamicArray> when [T: RedisArg]` (an argument per
  element). An adapter must live in the contract's module (src/arg.kama).

- **A `Subscriber` reaches its connection only through the private members `Connection` grants it, method by
  method** (`transmit`, `receiveFrame`, `lose`, `setAside`, `budget`, for reconnecting `lost` and `ready`, and
  `rawHandle` for a `ClusterSubscriber`'s `Poller`). Nothing on
  `Connection` is public for it. Pub/sub
  frames are read by one classifier (`classify` in src/subscriber.kama) for both protocols; a push that is not pub/sub
  goes to the connection's bounded set-aside list, never to a subscriber's deliveries.

- **A `Cluster` is a 7a `Connection` per node** (src/cluster.kama), and where a command goes is the servers' own word:
  the table of commands (src/wire/commands.kama, from `tools/gen-command-table.sh`) gives its keys and its tips. Never
  route by a guessed key position.
  - A node's `Config` (`Config.forNode`, granted to `Cluster.nodeConfig`) sets `reconnect_timeout` to 1 ms, so the
    node's own redial is one try. The cluster paces the next and reads the map between them.
  - What ran nothing (MOVED, ASK, TRYAGAIN, CLUSTERDOWN, LOADING, MASTERDOWN, a node that would not open, a failed
    redial) is sent again (`recourseFor`); anything else is the call's.
  - A transaction follows ASK only when every command with keys was answered ASK. A source queues a command whose key it
    still has, and the importing node would run the transaction without that key's value; a mixed answer waits.
  - A pipeline writes every node's batch before it reads any (`Connection.begin`, `finish`), and a node lost mid-batch
    fails only its own commands.
  - Its unit tests give each connection the cluster opens the next scripted dialer (`ScriptDialers`), keyed by its
    place, so a test lists its connections in the order the cluster opens them.

- **Nothing from the server is trusted.**
  - Every length is bounded before it is used, and so is every nesting depth.
  - A malformed reply is `RedisError::Protocol`, never a panic. The unit tests feed truncated and oversized
    replies to prove it.

- **Language habits from `@kama/postgres`,** each learned from a compiler error there:
  - A `resource` field is always private.
  - Match a resource payload through a named local and `give`: `Optional<T> x = f(); match (give x) { … }`.
  - `new` goes only in a local initializer: `Owned<H> h = new Impl.make(); this.h = give h;`.
  - A value-producing `match` may only initialize a local or be returned. A block arm that yields a value ends
    with `:= expr;`.
  - A value declared outside a loop may be given inside it only if every path back to the loop's start assigns it
    again (0.9.526). A local moved on only some paths cannot be assigned at all.
  - A field cannot be moved out (`give this.x`). Hand out what a place holds with `std::memory::replace(place:,
    with:)`, stating its type (`replace::<Value>(…)`), or drain a `DynamicArray` with `pop()`.
  - A `ref` parameter cannot name an `Owned<T>`. Pass the `Owned` by value and hand it back.
  - No shadowing: a parameter cannot have the name of a function in scope, nor a match binding the name of a local.
  - A `ConstView` local must be rooted: pass the view as a by-value parameter to a helper instead.
  - A static function is called with `::`; `.` on a type calls a constructor.
  - A method cannot take type parameters (a cstar decision), so typed access is a free generic function.
  - Never put a `Shared` in anything that must be `Sendable`; its count is not atomic.
  - An `IoError` is a value: branch on `e.kind()`.
  - Reserved words bite as names: every C keyword (`out`, `float`, `double`, `register`, …) and kama's own (`base`,
    `addr`, `ref`, `in`, `const`, `final`).
  - A view local must be rooted. Open a window (`borrow s.bytes() as b { … }`), or pass the view as a by-value
    parameter to a helper.
  - A value-producing `match` is not an assignment's right side. Bind it to a local, or move it into a helper.
  - A local moved on one branch must be moved on every branch, a failure branch included:
    `case Err(error: e): { Connection failed = give c; return …; }`.
  - A `Result`'s error type must implement `Error`: `Result<T, string>` is refused. Return a `RedisError`.
  - A struct with a `string` field owns, so it is a `type resource`, and its fields are private. A typed reply's
    struct gives its caller accessors.
  - A constructor that delegates the whole job is a private ctor (`Connection.establish`), not a static returning
    the type. A type's fields are assigned in its constructor itself, not in a method it calls, so several public
    constructors share a private one and return it (`Scan.named`).
  - A `friend` grant to a free function in the same file is unqualified (`friend readerOf[over];`); across files it
    is qualified (`friend redis::wire::admit[problem];`).
  - `try cast` has no float form, and an out-of-range float cast traps: compare the range first, then `cast`
    (which truncates a fraction).
  - A string literal cannot contain `${` except as a hole; a hole takes an identifier with accessors only, so bind
    a call (`isize n = xs.length();`) first.
  - A local may not share a name with a field, nor with a local of an enclosing scope.
  - A `Template<C>`'s holes are `const ref`, so a contract method a tag calls on one is a `const fn`.
  - A `match` on a std enum marked `@nonExhaustive` (`Utf8Error`, `Interest`, …) needs `case _:`, since a later std
    may add a case.
  - A block arm that yields a `string` says `:= give s;` (or `copy`): every arm is a hand-off.
  - A borrow of a field's payload does not live across a call that may write `this`; hold the value aside with
    `replace` (`ServerInfo.read`).
  - A hand-written `Deserializer` latches a `DeErrorKind` (`failWith(kind:)`, `errorKind()`); the derive adds where
    on the way out, so a `DeError` recovered with `e.as<DeError>()` names its field (`c.field()`: `f2`, `[1].f2`).
  - A path dependency's path is relative to its manifest; an absolute one is not found.
  - `Err`, `Ok`, `Some` and `None` are language names: no type may take one.
  - A contract-typed parameter (`RedisArg names`) is a borrow: pass a value to it as it is, never with `give` or `copy`.
  - A `DynamicArray<uint8>` is `Equatable` but not `Hashable`: a std `Set` of byte names needs a small key type that
    hashes them (`Name` in src/subscriber.kama).
  - A `Deque` gives O(1) push and pop at both ends (`pushBack` is `unsafe`): the bounded queues use it.
  - A field cannot be the `const ref` argument of a method that writes `this`: copy it into a local first
    (`Config c = copy this.settings;`), as a redial does.
  - A `Set` iterates its keys only when the key is `Copyable`: `Name` has a copy constructor for that.
  - A project's name is its root module, and it shadows a dependency's module of the same name (KRD-10).

- **Publishing** goes through `../kama-registry` (`./ops publish ../kama-redis/kama.json`) and happens only when
  the user says so, because a version is permanent. `kama publish kama.json --dry-run` must list no certificates
  and none of the agent files.
