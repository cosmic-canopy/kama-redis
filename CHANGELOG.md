# Changelog

All notable changes to this package are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/). In 0.x, a minor bump may break.

## [Unreleased]

Needs **kama ≥ 0.9.573**, the first tagged release with the fixes this package relies on (KAMA_GAPS.md).

### Added
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
