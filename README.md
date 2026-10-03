# @kama/redis

The Redis and Valkey client for [kama](https://kama-lang.org). It will speak RESP2 and RESP3 directly, in kama,
over `std::net`, as redis-rs, go-redis and Lettuce do. There is no hiredis and nothing to install. TLS will come
from [`@kama/tls`](https://github.com/cosmic-canopy/kama-tls).

> **Status: scaffold, not yet published.** The package builds and its test servers run. The protocol comes next;
> see [docs/ROADMAP.md](docs/ROADMAP.md). Needs **kama ≥ 0.9.523**.

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

The unit tests need no server. Each test server is one container running two servers, configured from
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
