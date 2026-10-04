# Changelog

All notable changes to this package are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/). In 0.x, a minor bump may break.

## [Unreleased]

Needs **kama ≥ 0.9.529**.

### Added
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
