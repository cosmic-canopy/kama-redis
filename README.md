# @kama/redis

The Redis and Valkey client for [kama](https://kama-lang.org). It will speak RESP2 and RESP3 directly, in kama,
over `std::net`, as redis-rs, go-redis and Lettuce do. There is no hiredis and nothing to install. TLS will come
from [`@kama/tls`](https://github.com/cosmic-canopy/kama-tls).

> **Status: the protocol layer, not yet published.** RESP2 and RESP3, connection URLs and cluster key slots are in
> and tested. The connection itself comes next; see [docs/ROADMAP.md](docs/ROADMAP.md). Needs **kama ≥ 0.9.523**.

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
    | Nesting | 128 deep |
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

## What it will cover

- **Servers:** Redis 6.2 to 8.x and Valkey 7.2 to 9.x, tested on every one.
- **Connecting:**
  - TCP and Unix-domain sockets, with connect and command timeouts.
  - `redis://`, `rediss://` and `unix://` URLs.
  - ACL users and passwords through `HELLO 3`, the single-argument `AUTH` of a server's default user, and
    database selection.
- **Protocol:** RESP3 by default, with typed replies and push messages; RESP2 for proxies that speak only that.
- **Commands:**
  - Typed arguments, and a `cmd"SET ${key} ${value}"` tag whose holes are always whole arguments.
  - Replies read into kama types through `Deserializable`, `@generate` structs included.
  - Pipelining, transactions (`MULTI`/`EXEC`/`WATCH`), scripts and functions, `SCAN` cursors, and blocking
    commands.
- **Push:** pub/sub (sharded too) and client-side caching.
- **Security:** TLS with verification, client certificates and SNI.
- **Topologies:** Cluster (slots, `MOVED`/`ASK`, replica reads) and Sentinel.
- **A connection pool** shared across isolates.

## Tests

```sh
KAMA=/path/to/kama tools/test.sh          # hermetic unit tests, debug and release
tools/redis.sh list                       # the servers in the matrix
tools/redis.sh up --server valkey-9.1     # start one (podman or docker); its ports go to out/redistest-valkey-9.1.env
tools/redis.sh smoke --server valkey-9.1  # one check per authentication case and transport, with the server's own redis-cli
tools/redis.sh down --server valkey-9.1
```

The unit tests need no server. Their vectors come from upstream by script: `tools/gen-resp-vectors.sh`,
`tools/gen-slot-vectors.sh` and `tools/gen-url-vectors.sh`. Each pins its sources by SHA256 and asks the servers and
CLIs in throwaway containers.

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
