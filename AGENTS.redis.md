# @kama/redis — what is true in THIS repo

The two generated files carry the general rules: `AGENTS.md` covers the language, and `AGENTS.package.md`
covers what a publishable library needs. `kama agents install` writes both, so they are **not**
hand-edited; a re-install rewrites them. This file is the project-specific third, and it is the one to
edit.

**Read [docs/ROADMAP.md](docs/ROADMAP.md) first.** It gives the order of work, and the decisions still to
confirm. Read [KAMA_GAPS.md](KAMA_GAPS.md) for the compiler gaps this package has hit.

**The sibling `@kama/postgres` (`../kama-postgres`) is the model.** It is the same kind of package (a native wire
protocol over `std::net`, a non-blocking `Transport` with deadlines, TLS from `@kama/tls`, typed values through
`Deserializable`, a scripted fake server), and its `AGENTS.postgres.md` records what it took to get there. Read
the matching part of its code before designing something here. Copy what fits; do not depend on it.

- **A gap goes in KAMA_GAPS.md the moment it is hit**, reduced to a repro and run on the named compiler.
  The cstar project reads that file and fixes from it, usually within a session. So do not build a
  workaround you would not want to delete. If a workaround is unavoidable, name it in the entry.

**The package needs kama ≥ 0.9.520**, declared as `"kama"` in every manifest here.

## What is true here and nowhere else

- **Native protocol, no C.** This package speaks RESP2 and RESP3 in kama over `std::net`. There is no hiredis,
  no `csrc/` and no `csources`, and it should stay that way. TLS will come from `@kama/tls` (`../kama-tls`, on the
  registry), which vendors Mbed TLS. What this package needs from TLS that `@kama/tls` lacks is added THERE, with
  its own tests, not worked around here.

- **Two test programs, and neither is typed from memory.**
  - `tests/unit` is hermetic. It needs no server and no network, and runs through `tools/test.sh`, debug and
    release. From phase 2 it holds a scripted fake server for every hostile path: a reply a byte at a time,
    silence, hangups, oversized lengths.
  - `tests/integration` (from phase 2) needs a live server and runs on every server in the matrix.
  - Vectors come from upstream by script: the RESP specification, hiredis's reader tests, the cluster
    specification's CRC16 vectors, and the container's own redis-cli and server asked live. A generator pins
    each upstream file by SHA256.

- **`tools/redis.sh` is the server.**
  - It runs the official images under podman or docker: `redis:6.2`, `7.2`, `7.4`, `8.2` and `8.10`, and
    `valkey/valkey:7.2`, `8.1` and `9.1`. `tools/redis.sh list` names them, and `--server redis-7.4` picks one.
  - One container per server runs two servers, configured from `tests/integration/server/`:
    - the main server, in plaintext and over TLS (`tls-auth-clients optional`), and on a Unix socket in the
      container;
    - the locked server, whose default user has a password, for NOAUTH and the single-argument AUTH.
  - Each container gets three host ports, bound to 127.0.0.1: base, base + 100 (TLS) and base + 200 (locked).
    `out/redistest-<server>.env` holds them.
  - There is one ACL user per authentication case. A test picks the case by picking the user:
    - `default`: no password;
    - `kr_acl`: a user with a password;
    - `kr_ro`: read commands only;
    - `kr_off`: disabled;
    - `kr_nopass`: any password.
  - `tools/redis.sh smoke` checks each case and transport with the container's own redis-cli. When an
    integration test fails, run it first: it separates "the server is misconfigured" from "the client is wrong".
  - The test PKI is generated into `out/test-certs` by `tools/gen-test-certs.sh` and is never tracked. `kama
    publish` refuses a tracked `*.key`, and so does the registry.

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
  - A value declared outside a loop cannot be given inside it: set a flag, leave the loop, then give.
  - A field cannot be moved out (`give this.x`). Drain a `DynamicArray` with `pop()`.
  - A `ref` parameter cannot name an `Owned<T>`. Pass the `Owned` by value and hand it back.
  - No shadowing: a parameter cannot have the name of a function in scope, nor a match binding the name of a local.
  - A `ConstView` local must be rooted: pass the view as a by-value parameter to a helper instead.
  - A `break` in a `match` arm leaves the match, not the loop (KPG-32 in `../kama-postgres/KAMA_GAPS.md`): end
    such a loop on a flag.
  - A static function is called with `::`; `.` on a type calls a constructor.
  - A method cannot take type parameters (a cstar decision), so typed access is a free generic function.
  - Never put a `Shared` in anything that must be `Sendable`; its count is not atomic.
  - An `IoError` is a value: branch on `e.kind()`.
  - Reserved words bite as names: every C keyword (`out`, `float`, `register`, …) and kama's own (`base`, `addr`,
    `ref`, `in`, `const`, `final`).

- **Publishing** goes through `../kama-registry` (`./ops publish ../kama-redis/kama.json`) and happens only when
  the user says so, because a version is permanent. `kama publish kama.json --dry-run` must list no certificates
  and none of the agent files.
