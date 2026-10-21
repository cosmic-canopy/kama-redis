# @kama/redis

The Redis and Valkey client for [kama](https://kama-lang.org). It speaks RESP2 and RESP3 directly, in kama, over
`std::net`, as redis-rs, go-redis and Lettuce do. There is no hiredis and nothing to install. TLS comes from
[`@kama/tls`](https://github.com/cosmic-canopy/kama-tls).

> **Status: 0.2.0: one server, Sentinel and Cluster.** A connection authenticates, picks its protocol and database,
> connects over TLS, and sends commands, pipelines, transactions and scripts with deadlines; replies read into kama
> types. A subscriber listens to channels, patterns and shard channels. A lost connection is made again by its next
> call, a subscriber's with every subscription, and nothing is sent twice. Through sentinels, a connection finds its
> master, and every reconnect asks again. A cluster sends each command where its keys are, follows MOVED and ASK,
> spreads a command over its nodes as the servers' own command tips say, and reads from replicas when asked. It is
> tested live on Redis 6.2–8.10 and Valkey 7.2–9.1, alone, under Sentinel and as a cluster. See the
> [roadmap](https://github.com/cosmic-canopy/kama-redis/blob/main/docs/ROADMAP.md). Needs **kama ≥ 0.9.707**.

## Connecting

```kama
import { core::println, redis::Config, redis::Connection, redis::Command, redis::RedisError, redis::cmd,
         redis::reply, redis::replyOpt };

fn uint8 main() {
    Result<Config, RedisError> parsed = Config.parse(url: "redis://127.0.0.1:6379/0?client_name=example");
    Config config = match (give parsed) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Result<Connection, RedisError> opened = Connection.connect(config: config);
    Connection conn = match (give opened) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };

    // Each hole is one whole argument, spaces and line breaks included: never text spliced into a word.
    string key = "greeting";
    string value = "hello, world";
    int32 ttl = 60;
    Command set = cmd"SET ${key} ${value} EX ${ttl}";
    Result<string, RedisError> stored = reply::<string>(result: conn.call(command: set));

    Command get = cmd"GET ${key}";
    Result<Optional<string>, RedisError> got = replyOpt::<string>(result: conn.call(command: get));
    match (give got) {
        case Ok(value: found): {
            match (give found) {
                case Some(value: text): { println(s: give text); }
                case None: { println(s: "(no such key)"); }
            };
        }
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    conn.close();
    return 0;
}
```

- **The handshake is one round trip.** `HELLO 3` carries `AUTH` and `SETNAME`, and `SELECT` and `CLIENT SETINFO`
  go in the same write. A proxy that refuses `HELLO` gets the RESP2 path on the same connection: `AUTH`,
  `CLIENT SETNAME` and `SELECT` as needed, or a `PING` when it needs none, so a connect always knows its link is
  open. A server with no room left (`maxclients`) refuses the connection as it accepts it, and the connect fails
  with that refusal, in the server's words.
- **URL options.** Every option is honoured, and any other is refused. docs/ROADMAP.md has what the other clients
  call each one, and why these defaults.

  | option | value | default |
  |---|---|---|
  | `protocol` | `2` or `3` | RESP3, or RESP2 where the server refuses `HELLO` |
  | `connect_timeout` | seconds, to the millisecond; `0` is no limit | 5 |
  | `command_timeout` | seconds, to the millisecond; `0` is no limit | 5 |
  | `client_name` | `CLIENT SETNAME`'s name | none |
  | `keepalive` | whole seconds, as hiredis sets it; `0` is off | 15 |
  | `reconnect` | `on` or `off` | `on` |
  | `reconnect_timeout` | seconds, to the millisecond; `0` is no limit | 5 |
  | `master_name` | the name the sentinels monitor (`redis-sentinel://`, and needed there) | none |
  | `role` | `master` or `replica` (`redis-sentinel://`) | `master` |
  | `read_from` | `primary` or `replica` (a cluster's) | `primary` |
  | `max_redirects` | how many MOVED and ASK one call follows, 0 to 100 (a cluster's) | 5 |

  `Config.tcp`, `Config.unix`, `Config.sentinel` and typed setters do the same without a URL. Several hosts, comma
  separated (`redis://h1:7000,h2:7001`), are a cluster's seeds, or sentinels; a connection takes one host, and refuses
  several, or a cluster's options, naming what to use.
- **Errors are values.** An error reply is `RedisError::Server`. Its code (`WRONGTYPE`, `NOAUTH`, `MOVED`, …) is a
  `ServerCode` to match, beside the server's message, and the connection goes on. A failure of the connection itself
  (I/O, bytes that are not RESP, a call past its deadline) loses it, and the next call makes it again.
- **Reconnecting never resends.** The call that meets a lost connection fails with what happened, because its command
  may have run; retrying it is the caller's choice. The next call makes the connection again: every address, the TLS
  files read again, the handshake in the protocol it spoke, with the database and user `select` and `authenticate`
  last set, then a `PING`. While the server is down, restarting, full or still loading, that call keeps trying, with a
  backoff, for up to `reconnect_timeout`. If it gives up, its error is `Reconnect`, which carries why, and nothing of
  the call was sent. A transaction whose `WATCH` was lost with the connection answers `WatchConflict` without being
  sent, so `watched` runs its body again. `reconnect=off` leaves a lost connection closed. A connection over your own
  transport (`connectOver`) has nothing to redial with, so it stays closed too.
- **The connection belongs to one isolate at a time,** and moves between them whole.

## Credentials that change

A password that rotates, or a token that expires (ElastiCache IAM, Entra ID), comes from a provider: a type of yours
that implements `Credentials`, set on the configuration with `Config.setCredentials`. It is then the server's one
source of a user and password, and a URL's password or `setAuth` beside it is refused.

```kama
// Reads the user, password and lifetime a sidecar keeps current; `fork` gives each connection one of its own.
type resource SecretFile implements Credentials, Sendable {
    string path;
    public ctor make(string path) { this.path = give path; }
    public unsafe fn Result<Login, RedisError> login() {
        // … read the file …
        return Login.of(user: Optional::Some(value: "app"), password: token, refreshAfter: Optional::Some(value: Duration.fromSecs(s: 600i64)));
    }
    public unsafe fn Owned<Credentials> fork() {
        Owned<Credentials> f = new SecretFile.make(path: copy this.path);
        return give f;
    }
}
```

- **It is asked at every connect and every redial,** so a connection made after a rotation logs in with the new
  login. The sentinels keep their own (`setSentinelAuth`); a cluster's nodes each ask a fork of their own.
- **A login may say when to ask again** (`refreshAfter`). Once that has passed, the connection's next call asks again
  and logs in anew (`AUTH`) before it writes anything, so a token never lapses on a live connection. A subscriber
  under RESP3 logs in anew where it is; under RESP2, which takes no `AUTH` while subscribed, it makes its connection
  again, and `Reconnected` marks the gap.
- **It fails closed.** A provider that fails, or a login the server refuses, closes the connection: the call fails
  with `Credentials`, nothing of it was sent, and the next call makes the connection again, asking anew. The server
  itself keeps a connection logged in as it was whatever its user's passwords become (`ACL SETUSER … resetpass`, or
  `off`), so closing is what ends a connection whose credentials were revoked. Every peer re-authenticates on its own
  schedule; rueidis also closes on a refusal, while go-redis, redis-py and node-redis go on as the old user.
- **The password is not kept with the connection.** Each redial asks the provider again, and `fork` may be called
  more often than connections are made, so keep it cheap. `authenticate` on such a connection is `Usage`.

## TLS

`rediss://` (and `valkeys://`) connect over TLS, from [`@kama/tls`](https://github.com/cosmic-canopy/kama-tls), which
vendors Mbed TLS: still nothing to install.

```kama
import { core::println, redis::Config, redis::Connection, redis::RedisError, redis::cmd, redis::reply };

fn uint8 main() {
    // The server's certificate must chain to this CA and name 127.0.0.1; a client certificate goes with it.
    string url = "rediss://127.0.0.1:6380?tls_ca=/etc/redis/ca.crt&tls_cert=/etc/redis/client.crt&tls_key=/etc/redis/client.key";
    Result<Config, RedisError> parsed = Config.parse(url: url);
    Config config = match (give parsed) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Result<Connection, RedisError> opened = Connection.connect(config: config);
    Connection conn = match (give opened) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Result<string, RedisError> pong = reply::<string>(result: conn.call(command: cmd"PING"));
    match (give pong) {
        case Ok(value: p): { println(s: give p); }
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    conn.close();
    return 0;
}
```

- **Verified by default.** The certificate must chain to a trusted root (the system's bundle, unless `tls_ca` names
  others) and must name the server: its host name among the certificate's DNS names, or its IP address among its IP
  addresses. go-redis, redis-py, redis-rs and Lettuce verify the same; redis-cli checks only the chain. The host name
  is sent as SNI, and an IP address is not (RFC 6066).
- **The TLS options**, each refused on `redis://` and `unix://`:

  | option | value | default |
  |---|---|---|
  | `tls_verify` | `full`: the chain and the name; `chain`: the chain alone; `none`: nothing | `full` |
  | `tls_ca` | a PEM file of roots to trust instead of the system's | the system's bundle (`SSL_CERT_FILE` overrides) |
  | `tls_cert`, `tls_key` | a client certificate and its key, in PEM: both, or neither | none |
  | `tls_server_name` | the name the certificate must carry, and the SNI sent | the host |

  `Config.tls` and its setters do the same, and more: roots and an identity as PEM bytes, an encrypted key's
  password, and the TLS versions (1.2 and 1.3 by default, the servers' own).
- **Files are read at each connect,** never when the configuration is made, so a renewed certificate is read by the
  next connection.
- **A TLS failure is `RedisError::Tls`**, in redis-cli's words, carrying `@kama/tls`'s `TlsError`, whose
  `Certificate(flags, reasons)` names each check that failed. It is final: the next address is not tried.
  `connect_timeout` bounds the TLS handshake with the rest. `Connection.tlsSession()` says what was agreed.
- **The wrong port.** A server's plaintext port says nothing to a TLS client, so `rediss://` there times out; its TLS
  port closes on a plaintext one, and `redis://` there is told to use `rediss://`.
- **Not offered:** cipher choice (Mbed TLS's defaults), a CA directory, CRLs and session resumption, each refused as
  an unknown option.

## Sentinel

A connection, or a subscriber, through sentinels: `redis-sentinel://` (`rediss-sentinel://` for TLS to the sentinels
and the servers both).

```kama
import { core::println, redis::Config, redis::Connection, redis::RedisError, redis::cmd, redis::reply };

fn uint8 main() {
    // The sentinels (26379 unless one says otherwise), and the name they monitor the master by.
    Result<Config, RedisError> parsed = Config.parse(url: "redis-sentinel://127.0.0.1:26379?master_name=mymaster");
    Config config = match (give parsed) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Result<Connection, RedisError> opened = Connection.connect(config: config);
    Connection conn = match (give opened) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Result<int64, RedisError> n = reply::<int64>(result: conn.call(command: cmd"INCR visits"));
    match (n) { case Ok(value: v): { println(s: "visits: ${v}"); } case Err(error: e): { println(s: e.message()); return 1; } };
    conn.close();
    return 0;
}
```

- **Finding the master is Sentinel's client specification, in full.** The sentinels are asked in turn, each within
  `connect_timeout`, for the master's address (`GET-MASTER-ADDR-BY-NAME`). The one that answers is asked first from
  then on, and the sentinels it knows (`SENTINEL SENTINELS`) join the list, at most 16. The server named must say it
  is the master, in its `HELLO` (or `ROLE` under RESP2); one that does not, a sentinel still behind a failover, is
  asked for again after a pause, within `reconnect_timeout`.
- **A failover is followed by the next call.** A sentinel kills every client of the servers a failover reconfigures,
  and every reconnect asks the sentinels again, so the next call reaches the new master. A call the failover cut off
  fails, since it may have run. A write the old master refuses as `READONLY` never ran, so it is sent once more, on
  the new master.
- **`role=replica`** connects to a replica that is up, at random (`SENTINEL REPLICAS`), or to the master when none
  is. A replica may be behind its master.
- **Credentials.** The URL's user and password are the servers'. Sentinels that want their own get them in code,
  `config.setSentinelAuth(user:, password:)`, never in a URL. `tls_server_name` names the servers' certificate; the
  sentinels' are checked against the hosts in the URL.
- **The errors:** no sentinel reached is `Connect`, an attempt per sentinel; sentinels that answered without an
  address (none knows the name, a password they want), and a server that never confirms its role, are
  `RedisError::Sentinel`, with what each said.

## Cluster

```kama
import { core::println, redis::Config, redis::Cluster, redis::Pipeline, redis::TxOutcome, redis::RedisError,
         redis::cmd, redis::reply, redis::resp::Value };

fn uint8 main() {
    // Seeds, asked in turn for the map; each node's connection opens when a call first goes there.
    Result<Config, RedisError> parsed = Config.parse(url: "redis://127.0.0.1:7000,127.0.0.1:7001");
    Config config = match (give parsed) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Result<Cluster, RedisError> opened = Cluster.connect(config: config);
    Cluster cluster = match (give opened) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    // Keys in three slots: the MSET goes as a piece per slot, each to its node.
    Result<string, RedisError> set = reply::<string>(result: cluster.call(command: cmd"MSET user:1 a user:2 b user:3 c"));
    match (set) { case Ok(value: ok): { println(s: "MSET ${ok}"); } case Err(error: e): { println(s: e.message()); return 1; } };
    // One hash tag, one slot, one node: this transaction is all or nothing.
    Pipeline tx = Pipeline.make();
    tx.add(command: cmd"SET {cart:7}:items 3");
    tx.add(command: cmd"INCR {cart:7}:version");
    Result<TxOutcome, RedisError> ran = cluster.transact(pipeline: tx);
    bool committed = match (ran) { case Ok(value: o): match (o) { case Committed(replies: rs): true; case WatchConflict: false; }; case Err(error: e): false; };
    if (!committed) { return 1; }
    println(s: "committed");
    Result<int64, RedisError> gone = reply::<int64>(result: cluster.call(command: cmd"DEL user:1 user:2 user:3 {cart:7}:items {cart:7}:version"));
    match (gone) { case Ok(value: n): { println(s: "deleted ${n}"); } case Err(error: e): { println(s: e.message()); return 1; } };
    cluster.close();
    return 0;
}
```

- **Where a command goes is the servers' own word.** A table read from every server's `COMMAND` (keys and command
  tips) is checked against each one's `COMMAND GETKEYS`. A command goes to the primary of its keys' slot, and one
  without keys to a primary. Keys in two slots are refused (`Usage`, naming a hash tag), as the server would refuse
  them.
- **A command the tips spread goes as they say.** `MGET`, `MSET`, `DEL`, `EXISTS`, `UNLINK`, `TOUCH` and `MSETEX` split
  by slot, a piece per slot; `DBSIZE`, `KEYS`, `FLUSHALL`, `SCRIPT EXISTS`, `WAIT`, … go to every primary; `SCRIPT
  LOAD`, `CONFIG SET`, … to every node. Their replies make one as the tips say: in the order of the keys, a sum, the
  least, all OK.
  - **A split command is atomic in each slot, not across the cluster.** When one piece fails, others may have run.
    Give keys one hash tag (`{user:1}:name`, `{user:1}:email`) to keep a command whole.
  - **A command each node answers for itself** (`INFO`, `RANDOMKEY`, `LATENCY`, `SCAN`) is refused, naming
    `callEach(command:, on: ClusterTarget::Primaries)`, which gives every node's reply as it is (`NodeReply`). A
    command the table does not know (a module's) is refused, naming `callFor(key:, command:)`, which sends it to the
    node a key names.
- **What the cluster answers on the way is followed.** `MOVED` goes into the map at once, and the map is read whole
  again before the next call, at most once a second. `ASK` is `ASKING` and the command in one write. `TRYAGAIN`,
  `CLUSTERDOWN`, `LOADING` and `MASTERDOWN` ran nothing, and are waited out, as is a node that cannot be reached: the
  map is read again and the call goes where it now says, within `reconnect_timeout`. At most `max_redirects`.
  Anything that may have run is the call's error, never sent again.
- **Pipelines, transactions, `watched`.** `run` sends each node its commands in one write, every node's before any is
  read, and gives the replies in the pipeline's order; a node lost on the way fails only its own commands.
  `transact` and `watched` run at the node of their keys' slot, which they must share. A slot that moves while a
  transaction queues sends it all again where it went; one half moved under its keys is waited out.
- **Replica reads, when asked.** `read_from=replica` sends a command the servers flag readonly to a replica of its
  slot, at random. A replica may be behind its primary, so a read there can miss a write just made: `WAIT` first
  when it must not. A read the replica will not serve goes to the primary.
- **`Scan.nextIn(cluster:)`** walks every primary in turn; SSCAN, HSCAN and ZSCAN go to their key's node.
- **`ClusterSubscriber`** subscribes channels and patterns at one primary and shard channels at their slots'
  primaries, and its `next` waits on every node at once. A shard channel whose slot moves is followed to the new
  owner, and `Delivery::Moved` says that messages in between may be lost.
- **Each node's connection is a `Connection`**, with what one has: TLS (each node's certificate checked against the
  address it announces), the database (Valkey 9's `cluster-databases`; Redis refuses one at connect), and a reconnect
  that never resends. `Cluster.connectWith(dialers:)` opens every connection through a dialer of yours (a tunnel, a
  NAT's mapping of the nodes' addresses).

## Commands

- **`cmd"…"`** is a `Command`. Its literal text splits on whitespace into arguments, and each hole is a value that
  writes itself as an argument (`RedisArg`):

  | type | becomes |
  |---|---|
  | `int8` to `int64`, `isize`, `uint16` to `uint64` | its decimal |
  | `float32`, `float64` | the shortest decimal that reads back the same; `inf`, `-inf`; a NaN is refused |
  | `string` | its bytes |
  | `DynamicArray<uint8>` | one binary argument, even when empty |
  | `DynamicArray<T>` of any of these | one argument per element, so an empty list is none (`DEL ${keys}`) |
  | `Uuid` | its text |

  Anything else is refused where it is written: a `bool`, a `char` or an `Optional` has no one meaning on the wire.
  A literal that touches a hole (`user:${id}`), puts two holes side by side, or quotes a word is refused when the
  command is sent, before anything is written.
- **`Command`** builds one by hand: `Command.of(name:)`, then `arg(text:)`, `argBytes(bytes:)`, `argInt(value:)`,
  `argFloat(value:)` and `add(value:)` for any `RedisArg`.
- **Commands a connection does not carry** are refused, by name, before anything is written: the pub/sub commands,
  `MONITOR`, `SYNC`, `PSYNC`, `CLIENT REPLY`, `SCRIPT DEBUG`, `HELLO`, `RESET`, `QUIT`, and `MULTI`, `EXEC` and
  `DISCARD`, since `transact` sends a transaction whole.
- **What sets what a connection is goes through the connection,** because a reconnect would quietly undo a command
  that set it. `conn.select(db: 3)` and `conn.authenticate(user: Optional::Some(value: "app"), password: pw)` send
  `SELECT` and `AUTH`, and every reconnect keeps what they set. A connection whose link was lost makes it again as
  the new user, never logging in as the old one first; credentials that change by themselves are a provider's (above). `SELECT` and `AUTH` themselves are refused, and so are
  `CLIENT SETNAME` and `SETINFO` (the `Config`'s `client_name` and identity, sent by the handshake), `CLIENT
  NO-EVICT`, `NO-TOUCH`, `CAPA` and `IMPORT-SOURCE`, `READONLY` and `READWRITE`, each saying what to do instead. The
  table is checked against every server's `ACL CAT connection`.
- **Blocking commands wait for their own timeouts.** `BLPOP k 5` waits 5 s plus `command_timeout`, and a timeout of 0
  has no deadline. The table covers every command each server calls blocking, and is checked against their
  `COMMAND DOCS`: `BLPOP`, `BRPOP`, `BZPOPMIN`, `BZPOPMAX`, `BRPOPLPUSH`, `BLMOVE`, `BLMOVEM`, `BLMPOP`, `BZMPOP`,
  `XREAD` and `XREADGROUP`'s `BLOCK`, `WAIT` and `WAITAOF`.

## Replies, pipelines, transactions, scripts and SCAN

```kama
import { core::println, std::collections::DynamicArray, redis::Config, redis::Connection, redis::Command,
         redis::Pipeline, redis::Replies, redis::RedisError, redis::TxOutcome, redis::Script, redis::ScriptCall,
         redis::Scan, redis::cmd, redis::reply, redis::replyRecordOpt };

// A struct reads by its fields' names: HGETALL's map under RESP3, and its flat list under RESP2.
@generate(Deserializable)
type resource Account {
    @field string owner;
    @field int64 balance;
    public const fn string describe() { int64 b = this.balance; return copy this.owner.concat(other: ": ${b}"); }
}

// BLPOP's [key, value] reads by position, as a record.
@generate(Deserializable)
type resource Popped {
    @field string list;
    @field string item;
    public const fn string describe() { return copy this.list.concat(other: " gave ").concat(other: this.item); }
}

fn uint8 main() {
    Result<Config, RedisError> parsed = Config.parse(url: "redis://127.0.0.1:6379");
    Config config = match (give parsed) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Result<Connection, RedisError> opened = Connection.connect(config: config);
    Connection conn = match (give opened) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    string account = "account:42";
    string owner = "ada";
    int64 balance = 100;

    // A pipeline: every command in one write, every reply in order.
    Pipeline setup = Pipeline.make();
    Command clear = cmd"DEL ${account} jobs";
    Command fill = cmd"HSET ${account} owner ${owner} balance ${balance}";
    Command queue = cmd"RPUSH jobs first";
    setup.add(command: clear);
    setup.add(command: fill);
    setup.add(command: queue);
    Result<Replies, RedisError> ran = conn.run(pipeline: setup);
    match (ran) { case Ok(value: r): { } case Err(error: e): { println(s: e.message()); return 1; } };

    // Typed replies: a struct from a hash.
    Command all = cmd"HGETALL ${account}";
    Result<Account, RedisError> read = reply::<Account>(result: conn.call(command: all));
    match (read) {
        case Ok(value: a): { println(s: a.describe()); }
        case Err(error: e): { println(s: e.message()); return 1; }
    };

    // A transaction: MULTI, the commands and EXEC in one write. A key changed under WATCH is WatchConflict.
    int64 debit = -30;
    Pipeline tx = Pipeline.make();
    Command take = cmd"HINCRBY ${account} balance ${debit}";
    Command log = cmd"RPUSH jobs debited";
    tx.add(command: take);
    tx.add(command: log);
    Result<TxOutcome, RedisError> outcome = conn.transact(pipeline: tx);
    match (give outcome) {
        case Ok(value: o): {
            match (give o) {
                case Committed(replies: r): {
                    Replies replies = give r;
                    Result<int64, RedisError> left = reply::<int64>(result: replies.take(index: 0));
                    match (left) { case Ok(value: n): { println(s: "balance ${n}"); } case Err(error: e): { println(s: e.message()); } };
                }
                case WatchConflict: { println(s: "a watched key changed"); }
            };
        }
        case Err(error: e): { println(s: e.message()); return 1; }
    };

    // A script: by its SHA-1, and by its source the first time a server lacks it.
    Script bump = Script.of(source: "return redis.call('HINCRBY', KEYS[1], 'balance', ARGV[1])");
    ScriptCall call = ScriptCall.of(script: bump);
    int64 tip = 5;
    call.addKey(value: account);
    call.addArg(value: tip);
    Result<int64, RedisError> bumped = reply::<int64>(result: conn.eval(call: call));
    match (bumped) { case Ok(value: n): { println(s: "balance ${n}"); } case Err(error: e): { println(s: e.message()); return 1; } };

    // A blocking pop: a record, or None when nothing came within its timeout.
    Command pop = cmd"BLPOP jobs 1";
    Result<Optional<Popped>, RedisError> popped = replyRecordOpt::<Popped>(result: conn.call(command: pop));
    match (popped) {
        case Ok(value: o): { match (o) { case Some(value: p): { println(s: p.describe()); } case None: { println(s: "nothing"); } }; }
        case Err(error: e): { println(s: e.message()); return 1; }
    };

    // SCAN, a page at a time: each `next` is one round trip.
    Scan scan = Scan.keys();
    string pattern = "account:*";
    scan.matching(pattern: pattern);
    isize found = 0;
    while (!scan.isDone()) {
        Result<DynamicArray<string>, RedisError> page = reply::<DynamicArray<string>>(result: scan.next(conn: conn));
        match (page) { case Ok(value: keys): { found = found + keys.length(); } case Err(error: e): { println(s: e.message()); return 1; } };
    }
    println(s: "${found} accounts");
    conn.close();
    return 0;
}
```

- **Typed replies** read any reply through `Deserializable`, the same way under RESP2 and RESP3:
  - `reply::<T>`, `replyOpt::<T>` (None for a null), `replyOpts::<T>` (MGET: each element may be null),
    `replyRecord::<T>` and `replyRecordOpt::<T>` (a top-level array read by position);
  - integers in the server's own grammar, floats (`inf` and `nan` included), bools, strings (UTF-8, or
    `DynamicArray<uint8>` for any bytes), lists, sets, std `Map`, and `@generate` structs: by name from a map, by
    position from an array inside another reply (XRANGE's entries);
  - an error inside a reply (one of EXEC's) is `RedisError::Server` with its code when it is read; anything that
    does not read is `RedisError::Value`, naming where: `reply[3].score: a bulk string "x" cannot be read as
    float64`.
- **Pipelines** (`Connection.run`): one write, one deadline, and each reply stands alone (`Replies.take`).
- **Transactions** (`Connection.transact`, and `watched` to run one under WATCH as many times as you say): every
  reply is read before the outcome is decided. A command refused while queueing aborts it as `Server`; one that fails
  when EXEC runs it fails alone.
- **Scripts:** `Connection.eval` sends EVALSHA, and EVAL on NOSCRIPT; `Script.readOnly` uses the `_RO` forms (7.0+);
  `Pipeline.addScript` sends EVAL.
- **SCAN, SSCAN, HSCAN and ZSCAN** a page at a time, with `matching`, `countHint`, `ofType` and `noValues`.

## When the connection is lost

A connection is lost when the server restarts, kills it (`CLIENT KILL`, its idle `timeout`, a full output buffer),
or the network fails. The call that meets the loss fails with what happened, and nothing is ever sent again on its
own: a command that may have run is yours to retry or not. The next call makes the connection again, as the first was
made, then sends.
- **Before each call writes,** it reads whatever came while the connection sat idle. A close found there (the usual
  case after a kill or an idle timeout) means nothing was sent, so the call makes the connection again and sends,
  and never sees the loss. A close can still land between that read and the write, so this is usual, not certain.
- **Making it again** tries every address, reads the TLS files again (a renewed certificate is used), and runs the
  handshake in the protocol the connection spoke, as the user and database that `authenticate` and `select` last
  set, then a `PING`. While the server is down, restarting, full (`maxclients`) or still loading its data, the call
  keeps trying, with a backoff (100 ms doubling to 1 s, jittered), for up to `reconnect_timeout` (5 s). A wrong
  password, a refused certificate or bytes that are not RESP end it at once.
- **A transaction whose `WATCH` was lost** with the connection answers `WatchConflict` and is not sent, so `watched`
  runs its body again on the new connection.
- **`reconnect=off`** leaves a lost connection closed, and so does `close()`. A connection over a transport you
  opened (`connectOver`) has nothing to make it again with.

Whether a failed call's command could have run:

| error | sent? | what it means |
|---|---|---|
| `Usage`, `Value`, `Config` | no | refused before anything was written; the connection goes on |
| `Reconnect` | no | the connection was lost earlier and could not be made again; `cause()` says why, and the next call tries again |
| `Closed` | no | closed by `close()`, or lost with nothing to make it again with |
| `Connect`, `Tls` while connecting | no | no connection was made |
| `Server` | yes | the server answered with an error; `LOADING`, `BUSY`, `TRYAGAIN` and `MASTERDOWN` mean it did not run it |
| `Io`, `Timeout`, `Protocol`, `Unexpected`, `Tls` during a call | maybe | the connection was lost with the command sent or half answered: it may have run |
| `Sentinel` | no | the sentinels gave no address, or the server they named never said it was the master |
| `PoolTimeout` | no | every connection of a pool stayed leased past its `acquireTimeout` |
| `Credentials` | no | the credentials provider failed, or the server refused its new login: the connection is closed, and the next call makes it again |
| a cluster's `Server` `MOVED` or `ASK` | no | past `max_redirects`: the node named was asked, and did not run it |
| any error from a command a cluster split by slot | partly | `MSET`, `DEL` and their kin go as a piece per slot: the others may have run |

A [reliable queue](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/job_queue/src/main.kama) shows one way to
live with "maybe": BLMOVE into a processing list, so a job that may have been taken is found again.

## A pool shared by isolates

`redis::pool` holds connections that the isolates of a program share, as redis-py, go-redis and Jedis pool theirs.
`acquire()` lends one, as a `Lease`, which gives it back when it is dropped, on every path out of its scope.

```kama
// A pool of at most four connections, and one isolate's call on a lease.
PoolOptions options = PoolOptions.defaults();
options.maxSize = 4;
Result<Pool, RedisError> made = Pool.make(config: config, options: options);
// …
Result<Lease, RedisError> got = pool.acquire();
match (give got) {
    case Ok(value: l): {
        Lease lease = give l;
        Command incr = cmd"INCR ${key}";
        Result<int64, RedisError> n = reply::<int64>(result: lease.conn().call(command: incr));
    }
    case Err(error: e): { println(s: e.message()); }
};
```

- **A pool belongs to one isolate.** `pool.share()` makes a `PoolShare`, which is `Sendable`, and `Pool.join(share:)`
  in another isolate makes a pool over the same connections, within the same `maxSize`.
- **A lease is a whole `Connection`:** commands, pipelines, transactions, `watched`, `Scan`, blocking commands. Where
  a function takes `ref Connection`, borrow the lease's: `borrow lease.conn() as conn { keys.next(conn: conn); }`.
  A lost link is made again by the lease's next call, as on any connection, and nothing is ever sent twice.
- **`PoolOptions`**, in code (a URL option would be a second way to say the same):

  | option | default |
  |---|---|
  | `maxSize` | the larger of 4 and the CPUs online |
  | `acquireTimeout` | 6 s (go-redis's rule: a command's timeout and one more); then `PoolTimeout`, nothing sent |
  | `lifetime` | none (go-redis and rueidis set none); a connection past it is closed when it is next released or acquired |
  | `lifetimeJitter` | 90 s, a random part of it added to each connection's lifetime |
  | `minIdle` | 0: the fewest idle connections the maintenance keeps open |
  | `idleTimeout` | 30 minutes (go-redis's): how long idle connections the pool has not needed are watched before they are closed |
  | `healthCheck` | 60 s: how often the maintenance runs |
  | `pingTimeout` | 5 s: how long a probe's `PING` may take |
- **Release puts back only what the lease changed:** `UNWATCH` for a `WATCH` in force and `SELECT` for a database
  `select` changed, in one write sent as the lease drops, so a failure is the releaser's, never the next lease's. The
  command timeout comes back, and pushes set aside are dropped (counted in `droppedPushes`). A connection whose link
  is lost, one that was closed, one whose user `authenticate` changed, one past its lifetime and one whose put-back
  failed is closed instead, and its place goes to a new connection. No `RESET` is sent: it would log the connection
  out and drop its name, protocol and tracking.
- **An idle connection is checked before it is lent,** with no round trip: one the server let go while it sat (an
  idle timeout, a kill) is closed and its place used. The pool never makes a link again on its own time.
- **A maintenance isolate keeps the pool** (@kama/postgres's, after pgxpool and Npgsql), stopped and joined when the
  pool that made it drops. It connects until `minIdle` are idle. Every `healthCheck` it closes connections past their
  lifetime and those the pool has not needed, by the median of the idle counts over `idleTimeout` (Npgsql's pruning,
  never below `minIdle`). It probes each connection idle for more than a second: what came while it sat, a fresh login
  once a credentials provider's time has come, then `PING` within `pingTimeout`. One that fails is closed.
- **A scan stays on its link.** A `Scan` continued on another lease's connection ends with `Usage`, since its cursor
  means nothing on another link.
- **`Pool.makeWith(dialers:)`** opens each connection's transports through a dialer of yours (`PoolDialers`).

## Pub/sub

```kama
import { core::println, std::collections::DynamicArray, std::time::Duration, redis::Config, redis::Connection,
         redis::Subscriber, redis::Delivery, redis::Message, redis::Command, redis::RedisError, redis::cmd,
         redis::reply };

fn string describe(const ref Message m) {
    Result<string, RedisError> channel = m.channelText();
    Result<string, RedisError> payload = m.text();
    return match (channel) {
        case Ok(value: c): match (payload) { case Ok(value: p): c.concat(other: ": ").concat(other: p); case Err(error: e): e.message(); };
        case Err(error: e): e.message();
    };
}

fn uint8 main() {
    Result<Config, RedisError> parsed = Config.parse(url: "redis://127.0.0.1:6379");
    Config config = match (give parsed) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    // A subscriber owns a connection of its own, under RESP3 and RESP2 alike.
    Result<Subscriber, RedisError> made = Subscriber.connect(config: config);
    Subscriber sub = match (give made) {
        case Ok(value: s): give s;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    // Each call returns once the server has confirmed every name.
    DynamicArray<string> channels = DynamicArray.empty();
    channels.add(item: "news");
    channels.add(item: "alerts");
    Result<Unit, RedisError> subscribed = sub.subscribe(names: channels);
    match (subscribed) { case Ok(value: u): { } case Err(error: e): { println(s: e.message()); return 1; } };
    Result<Unit, RedisError> patterned = sub.psubscribe(names: "log:*");
    match (patterned) { case Ok(value: u): { } case Err(error: e): { println(s: e.message()); return 1; } };

    // Publishing is an ordinary command, on any other connection. It answers how many subscribers got the message.
    Result<Connection, RedisError> opened = Connection.connect(config: config);
    Connection conn = match (give opened) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Command publish = cmd"PUBLISH news hello";
    Result<int64, RedisError> count = reply::<int64>(result: conn.call(command: publish));
    match (count) { case Ok(value: n): { println(s: "${n} subscriber got it"); } case Err(error: e): { println(s: e.message()); return 1; } };

    // Wait up to a second for the next message. None means the time passed; the subscriber goes on.
    Optional<Duration> second = Optional::Some(value: Duration.fromSecs(s: 1i64));
    Result<Optional<Delivery>, RedisError> next = sub.next(timeout: second);
    match (give next) {
        case Ok(value: o): {
            match (give o) {
                case Some(value: d): {
                    match (give d) {
                        case Message(message: m): { println(s: describe(m: m)); }
                        case Unsubscribed(kind: k, channel: c): { println(s: "the server ended a subscription"); }
                        case Reconnected(cause: e): { println(s: "reconnected, and messages may have been missed"); }
                        // A later release may add a kind of delivery (Delivery is @nonExhaustive).
                        case _: { }
                    };
                }
                case None: { println(s: "nothing within a second"); }
            };
        }
        case Err(error: e): { println(s: e.message()); return 1; }
    };

    // Unsubscribe from everything and take the connection back, for commands.
    Result<Connection, RedisError> released = sub.release();
    Connection again = match (give released) {
        case Ok(value: c): give c;
        case Err(error: e): { println(s: e.message()); return 1; }
    };
    Command ping = cmd"PING";
    Result<string, RedisError> pong = reply::<string>(result: again.call(command: ping));
    match (give pong) { case Ok(value: p): { println(s: give p); } case Err(error: e): { println(s: e.message()); return 1; } };
    conn.close();
    again.close();
    return 0;
}
```

- **A `Subscriber` owns its connection**, as every peer client gives pub/sub a connection of its own: waiting for
  messages blocks it, and under RESP2 a subscribed connection takes no other command. `Subscriber.over` takes a
  `Connection` you already have, and `release()` gives it back; `Connection.call` refuses the (un)subscribe
  commands.
- **`subscribe`, `psubscribe` and `ssubscribe`**, and the three unsubscribes, take one name or a list (strings, or
  `DynamicArray<uint8>` for bytes). Each returns once the server has confirmed every name. An unsubscribe given an
  empty list unsubscribes from every name of its kind. An error in place of the confirmations (NOPERM, or in a
  cluster CROSSSLOT or MOVED) is `RedisError::Server`, and the subscriber goes on.
- **`next(timeout:)`** gives the messages: those that arrived while a call waited, then the next to arrive. None
  waits as long as it takes, and zero takes only what has already arrived. A `Message` has its kind, channel,
  pattern and payload as bytes, with `channelText()`, `patternText()` and `text()` refusing bytes that are not UTF-8.
  A shard channel the server unsubscribes on its own (its slot moved) comes as `Delivery::Unsubscribed`.
- **Delivery is at most once**, as the server's own is. Unread messages wait in the socket and the server's buffer,
  and the server disconnects a subscriber that falls too far behind (`client-output-buffer-limit pubsub`).
- **A lost subscriber is made again**, by `next` itself (nothing of it was sent), or by the next subscribe,
  unsubscribe or ping. Every channel, pattern and shard channel is subscribed again (shard channels a slot at a
  time), and `Reconnected(cause)` comes first, after what was already queued: messages published meanwhile were
  missed, and you are told so. A name the server refuses then (`NOPERM` after an ACL change, `MOVED`) comes as
  `Unsubscribed`, and an unsubscribe that failed with the connection is never undone. TCP keepalive (on, 15 s)
  finds a peer that went away silently; over your own dialer, or with `keepalive=0`, `ping()` is the check.
- **Sharded pub/sub** (`SSUBSCRIBE`, `SPUBLISH`) needs Redis 7.0 or Valkey 7.2. On a cluster, `ClusterSubscriber`
  sends each shard channel to the node that serves its slot, and follows it when the slot moves (see Cluster).
- **`Delivery` is `@nonExhaustive`**: a `match` on one needs `case _:`, since a later release may add a kind.
- **Pushes that are not pub/sub** (an invalidation another connection's `CLIENT TRACKING … REDIRECT` sends) are set
  aside on the connection: `Connection.takePushes()` hands them over, at most 1024 and within `maxReplyBytes`, and
  `droppedPushes()` counts any past that. `CLIENT TRACKING` and `CLIENT CACHING` are refused until client-side
  caching comes (0.3.0).

## Underneath

- **`redis::resp`**, the protocol as data. A proxy, a fake server or a test harness can use it on its own.
  - `Reader` takes bytes in any pieces and returns each value when it is whole.
  - `Writer` writes every wire form: RESP2's nulls, and RESP3's streamed strings and aggregates.
  - `Value` is every RESP2 and RESP3 type, attributes included.
  - The reader matches hiredis, the reader redis-cli uses, on 593 inputs: hiredis's own tests, every example in
    the RESP specification, and what Redis 6.2–8.10 and Valkey 7.2–9.1 actually send.
  - Nothing from the server is trusted. These limits are configurable (`resp::Limits`):

    | Limit | Default |
    |---|---|
    | One string | 512 MiB |
    | One aggregate | 2³²−1 elements |
    | Nesting | 1024 deep |
    | One reply | 1 GiB |

    A malformed reply is an error, never a crash, and memory grows only with bytes that actually arrived.
- **`redis::RedisUrl`**:

  ```
  redis://[[user]:password@][host][:port][/db][?key=value&…]      also valkey://
  rediss://…                                                       TLS; also valkeys://
  redis://[[user]:password@]h1:port,h2:port[/db][?…]               a cluster's seeds
  redis-sentinel://[[user]:password@]s1[:port],s2…[/db]?master_name=NAME[&role=replica]
  rediss-sentinel://…                                              TLS to the sentinels and the servers
  unix://[[user]:password@]/path/to/socket[?db=N&key=value&…]
  ```

  - `redis://` URLs mean what they mean to `redis-cli -u`, and `valkey://` URLs what they mean to `valkey-cli`.
    Both CLIs were asked live, URL by URL.
  - Where a CLI would quietly misread a URL (a port of `6379x`, an `@` in a password that is not written as `%40`),
    this package refuses it and says how to write it.
  - `unix://` is the form redis-py and go-redis document.
  - A password in a URL can end up in logs and process listings, so prefer giving it separately where you can.
- **`redis::cluster`**, what a cluster client is made of, for use beside one:
  - `keySlot`, a key's hash slot with hash tags, checked against the cluster specification and `CLUSTER KEYSLOT` on
    every server;
  - `CommandTable`, a command's keys (as `COMMAND GETKEYS` finds them) and slot, from every server's key
    specifications;
  - `SlotMap` and `ClusterNode`, a cluster's map from `CLUSTER SLOTS`; `Redirect`, what a `MOVED` or `ASK` says.

- **`redis::Connection`**, `Config` and `RedisError`, as above:
  - TCP, TLS (`redis::secure`, internal, over any transport) and Unix-domain sockets, non-blocking, with connect and
    command deadlines and TCP keepalive;
  - ACL users and passwords, the password alone of a server's default user, the client's name and the database;
  - RESP3 by default, and RESP2 for proxies such as twemproxy and Envoy;
  - `server()`, the server's own account of itself from `HELLO`.

## Examples

Each is a program of its own under [`examples/`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples), built by `tools/test.sh` and run against every
server in the matrix by `tools/check-examples.sh`. Run one with `REDIS_URL=redis://127.0.0.1:6379 kama run
examples/quickstart/kama.json`.
- [`quickstart`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/quickstart/src/main.kama): connect, store and read a value, count, close.
- [`typed_replies`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/typed_replies/src/main.kama): a struct from a hash, a list, MGET's Optionals,
  a sorted set as a Map.
- [`transactions`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/transactions/src/main.kama): a pipeline, and a transfer under WATCH that runs
  again from fresh reads.
- [`pubsub_worker`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/pubsub_worker/src/main.kama): a subscriber that handles every delivery,
  `Reconnected` included, fed from another isolate.
- [`job_queue`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/job_queue/src/main.kama): a reliable queue with BLMOVE and a processing list, so
  that a call that failed after it was sent loses no job.
- [`tls_connection`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/tls_connection/src/main.kama): TLS verified against a CA, and what the
  handshake settled.
- [`scan`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/scan/src/main.kama): keys a page at a time, with MATCH and COUNT.
- [`scripts`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/scripts/src/main.kama): a rate limiter as a Lua script, by its SHA-1.
- [`sentinel`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/sentinel/src/main.kama): the master found through sentinels, and what a
  failover does to a call.
- [`cluster`](https://github.com/cosmic-canopy/kama-redis/blob/main/examples/cluster/src/main.kama): a cluster from its seeds, a split MSET and MGET, a
  transaction under one hash tag, a pipeline over the nodes.

## What comes next

On Redis 6.2 to 8.x and Valkey 7.2 to 9.x, tested on every one:
- **0.1.0, one server, complete.**
- **0.2.0, topologies:** Cluster and Sentinel. This release.
- **0.3.0, scale:** a connection pool shared across isolates, client-side caching, and a credentials provider.
- **0.4.0, typed commands:** a method per command, and the Redis 8 modules (JSON, search, time series, probabilistic)
  with typed replies.

## Tests

```sh
KAMA=/path/to/kama tools/test.sh                    # hermetic unit tests, debug and release
KAMA=/path/to/kama tools/test-integration.sh        # the live suite on every server, debug and release
tools/test-integration.sh --server valkey-9.1       # … on one
tools/redis.sh list                                 # the servers in the matrix
tools/redis.sh up --server valkey-9.1               # start one (podman or docker); its ports go to out/redistest-valkey-9.1.env
tools/redis.sh smoke --server valkey-9.1            # one check per authentication case and transport, with the server's own redis-cli
tools/redis.sh up --server valkey-9.1 --topology cluster   # … a cluster of six nodes; --topology sentinel for Sentinel
tools/redis.sh down --server valkey-9.1
tools/check-readme.sh --server redis-8.10           # build this README's programs and run them against the server
tools/check-examples.sh --server redis-8.10         # build examples/ and run them against the server
tools/mutate.sh tools/mutations/7a-s5.json          # each mutation of the source must make the case it targets fail
```

The unit tests need no server: a scripted server plays real servers' bytes to the connection, a byte at a time.
Their vectors come from upstream by script: `tools/gen-resp-vectors.sh`, `tools/gen-slot-vectors.sh`,
`tools/gen-url-vectors.sh`, `tools/gen-server-vectors.sh`, `tools/gen-topology-vectors.sh` (a cluster's nodes and
Sentinel) and `tools/gen-command-table.sh` (every server's commands, keys and tips). Each pins its sources by SHA256 and asks the servers
and CLIs in throwaway containers.

Each test server is one container running two servers, configured from
`tests/integration/server/`:
- the main server, in plaintext, over TLS and on a Unix socket, with one ACL user per authentication case;
- a locked server, whose default user has a password.

Its test certificates are generated into `out/` and never committed.

## License

`@kama/redis` is licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](https://github.com/cosmic-canopy/kama-redis/blob/main/LICENSE-APACHE))
- MIT license ([LICENSE-MIT](https://github.com/cosmic-canopy/kama-redis/blob/main/LICENSE-MIT))

at your option. It vendors nothing.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
`@kama/redis` by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any
additional terms or conditions.
