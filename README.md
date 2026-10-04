# @kama/redis

The Redis and Valkey client for [kama](https://kama-lang.org). It speaks RESP2 and RESP3 directly, in kama, over
`std::net`, as redis-rs, go-redis and Lettuce do. There is no hiredis and nothing to install. TLS will come from
[`@kama/tls`](https://github.com/cosmic-canopy/kama-tls).

> **Status: connecting works; not yet published.** A connection authenticates, picks its protocol and database, and
> sends commands with deadlines. It is tested live on Redis 6.2–8.10 and Valkey 7.2–9.1. Typed commands and replies
> come next; see [docs/ROADMAP.md](docs/ROADMAP.md). Needs **kama ≥ 0.9.529**.

## Connecting

```kama
import { core::println, std::encoding::utf8::decode, std::encoding::utf8::Utf8Error,
         redis::Config, redis::Connection, redis::Command, redis::RedisError, redis::resp::Value };

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

    Command set = Command.of(name: "SET");
    set.arg(text: "greeting");
    set.arg(text: "hello");
    Result<Value, RedisError> stored = conn.call(command: set);

    Command get = Command.of(name: "GET");
    get.arg(text: "greeting");
    Result<Value, RedisError> got = conn.call(command: get);
    match (got) {
        case Ok(value: v): {
            match (v) {
                case Bulk(bytes: b): {
                    Result<string, Utf8Error> text = decode(bytes: b.view());
                    match (give text) { case Ok(value: t): { println(s: give t); } case Err(error: e): { } };
                }
                case _: { }
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
  (I/O, bytes that are not RESP, a call past `command_timeout`) closes it.
- **The connection belongs to one isolate at a time,** and moves between them whole.

## What is here now

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

- **`redis::Connection`**, `Config`, `RedisError` and `Command`, as above:
  - TCP and Unix-domain sockets, non-blocking, with connect and command deadlines and TCP keepalive;
  - ACL users and passwords, the password alone of a server's default user, the client's name and the database;
  - RESP3 by default, and RESP2 for proxies such as twemproxy and Envoy;
  - `server()`, the server's own account of itself from `HELLO`.

## What it will cover

- **Servers:** Redis 6.2 to 8.x and Valkey 7.2 to 9.x, tested on every one.
- **Commands:**
  - Typed arguments, and a `cmd"SET ${key} ${value}"` tag whose holes are always whole arguments.
  - Replies read into kama types through `Deserializable`, `@generate` structs included.
  - Pipelining, transactions (`MULTI`/`EXEC`/`WATCH`), scripts and functions, `SCAN` cursors, and blocking
    commands.
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
