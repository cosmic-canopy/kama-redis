# Changelog

All notable changes to this package are recorded here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and versions follow
[SemVer](https://semver.org/). In 0.x, a minor bump may break.

## [Unreleased]

Needs **kama ≥ 0.9.523**.

### Added
- Registry metadata in `kama.json` (`description`, `repository`, `keywords`), new in kama 0.9.523, so the
  registry's catalog and `kama pkg search` can say what the package is.
- The package scaffold: manifest, agent files, hermetic unit-test program (`tools/test.sh`).
- The integration servers: `tools/redis.sh` runs the official Redis (6.2, 7.2, 7.4, 8.2, 8.10) and Valkey (7.2,
  8.1, 9.1) images under podman or docker, with TLS on and one ACL user per authentication case;
  `tools/gen-test-certs.sh` generates their throwaway PKI. `tools/redis.sh smoke` passes all 16 checks on
  Redis 6.2.24, 7.2.16, 7.4.11, 8.2.10 and 8.10.2, and Valkey 7.2.14, 8.1.10 and 9.1.2.
