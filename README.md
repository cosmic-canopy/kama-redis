# @kama/redis

The Redis and Valkey client for [kama](https://kama-lang.org). It speaks RESP2 and RESP3 directly, in kama, over
`std::net`, as redis-rs, go-redis and Lettuce do. There is no hiredis and nothing to install. TLS will come from
[`@kama/tls`](https://github.com/cosmic-canopy/kama-tls).

> **Status: commands work; not yet published.** A connection authenticates, picks its protocol and database, and
> sends commands, pipelines, transactions and scripts with deadlines; replies read into kama types. It is tested live
> on Redis 6.2–8.10 and Valkey 7.2–9.1. Push messages, TLS and cluster come next; see
> [docs/ROADMAP.md](docs/ROADMAP.md). Needs **kama ≥ 0.9.667**.

## Connecting

```kama
import { core::println, redis::Config, redis::Connection, redis::Command, redis::RedisError, redis::cmd,
         redis::reply, redis::replyOpt };

fn int32 main() {
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
  go in the same write. A proxy that refuses `HELLO` gets the RESP2 path on the same connection.
- **URL options.** Every option is honoured, and any other is refused. docs/ROADMAP.md has what the other clients
  call each one, and why these defaults.

  | option | value | default |
  |---|---|---|
  | `protocol` | `2` or `3` | RESP3, or RESP2 where the server refuses `HELLO` |
  | `connect_timeout` | seconds, to the millisecond; `0` is no limit | 5 |
  | `command_timeout` | seconds, to the millisecond; `0` is no limit | 5 |
  | `client_name` | `CLIENT SETNAME`'s name | none |
  | `keepalive` | whole seconds, as hiredis sets it; `0` is off | 15 |

  `Config.tcp`, `Config.unix` and typed setters do the same without a URL.
- **Errors are values.** An error reply is `RedisError::Server`. Its code (`WRONGTYPE`, `NOAUTH`, `MOVED`, …) is a
  `ServerCode` to match, beside the server's message, and the connection goes on. A failure of the connection itself
  (I/O, bytes that are not RESP, a call past its deadline) closes it.
- **The connection belongs to one isolate at a time,** and moves between them whole.

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

fn int32 main() {
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
  unix://[[user]:password@]/path/to/socket[?db=N&key=value&…]
  ```

  - `redis://` URLs mean what they mean to `redis-cli -u`, and `valkey://` URLs what they mean to `valkey-cli`.
    Both CLIs were asked live, URL by URL.
  - Where a CLI would quietly misread a URL (a port of `6379x`, an `@` in a password that is not written as `%40`),
    this package refuses it and says how to write it.
  - `unix://` is the form redis-py and go-redis document.
  - A password in a URL can end up in logs and process listings, so prefer giving it separately where you can.
- **`redis::cluster::keySlot`**, a key's hash slot with hash tags. It is checked against the cluster specification
  and against `CLUSTER KEYSLOT` on every server.

- **`redis::Connection`**, `Config` and `RedisError`, as above:
  - TCP and Unix-domain sockets, non-blocking, with connect and command deadlines and TCP keepalive;
  - ACL users and passwords, the password alone of a server's default user, the client's name and the database;
  - RESP3 by default, and RESP2 for proxies such as twemproxy and Envoy;
  - `server()`, the server's own account of itself from `HELLO`.

## What it will cover

- **Servers:** Redis 6.2 to 8.x and Valkey 7.2 to 9.x, tested on every one.
- **Push:** pub/sub (sharded too) and client-side caching.
- **Security:** TLS (`rediss://`) with verification, client certificates and SNI.
- **Topologies:** Cluster (slots, `MOVED`/`ASK`, replica reads) and Sentinel.
- **A connection pool** shared across isolates.

## Tests

```sh
KAMA=/path/to/kama tools/test.sh                    # hermetic unit tests, debug and release
KAMA=/path/to/kama tools/test-integration.sh        # the live suite on every server, debug and release
tools/test-integration.sh --server valkey-9.1       # … on one
tools/redis.sh list                                 # the servers in the matrix
tools/redis.sh up --server valkey-9.1               # start one (podman or docker); its ports go to out/redistest-valkey-9.1.env
tools/redis.sh smoke --server valkey-9.1            # one check per authentication case and transport, with the server's own redis-cli
tools/redis.sh down --server valkey-9.1
tools/check-readme.sh --server redis-8.10           # build this README's programs and run them against the server
```

The unit tests need no server: a scripted server plays real servers' bytes to the connection, a byte at a time.
Their vectors come from upstream by script: `tools/gen-resp-vectors.sh`, `tools/gen-slot-vectors.sh`,
`tools/gen-url-vectors.sh` and `tools/gen-server-vectors.sh`. Each pins its sources by SHA256 and asks the servers
and CLIs in throwaway containers.

Each test server is one container running two servers, configured from
`tests/integration/server/`:
- the main server, in plaintext, over TLS and on a Unix socket, with one ACL user per authentication case;
- a locked server, whose default user has a password.

Its test certificates are generated into `out/` and never committed.

## License

`@kama/redis` is licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option. It vendors nothing.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in
`@kama/redis` by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any
additional terms or conditions.
