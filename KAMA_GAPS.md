# Gaps found in kama, from building @kama/redis

It is written **for the cstar project**: each entry is reduced to the smallest program or file that shows it.
Every entry with a repro was **run** on the version named. Nothing is inferred from reading the spec. An entry
that is an absence cites the cstar files that show it instead. This file is excluded from the published
package, as it is in `@kama/postgres` and `@kama/sodium`.

**Current compiler:** `kama 0.9.719` (tag `v0.9.719`), which CI pins and the manifests' floor names. It moved from
`v0.9.667` to `v0.9.690` on 2026-10-20, which closed KRD-11, to `v0.9.707` on 2026-10-21, which closed KRD-9 and
KRD-12, and to `v0.9.719` on 2026-10-22, which closed KRD-13, KRD-14 and KRD-16: the tree carries no workaround. Each repro is
also run on cstar's newest build, which the registry publishes with: on 2026-10-22, `0.9.719+g00e13b15`. On
2026-10-26 the package, both test programs and every example checked clean on v0.9.734, the newest tag, and on
`0.9.744+g90169f87`; the floor stays v0.9.719 until the package needs more. `@kama/tls` 0.1.5 did not build on 0.9.696 and later (four
statements after a `while (true)`, and from 0.9.706 a `string.find` whose type changed); 0.1.6 does, and this
package needs `^0.1.6`.

**Reporter:** the `@kama/redis` repo. Each open entry names the workaround this package uses, so the workaround
can be deleted when the gap closes. **We are not attached to any workaround.** If a fix changes the right design
here, say so and we will follow it.

**Open now:** none. Entries are numbered KRD-1, KRD-2, …. A gap this package hits that `@kama/postgres` already
filed is cited by its KPG number rather than filed again.

**Finding a fix:** since 0.9.532, cstar's commit messages describe a defect in kama's own terms and cite no other
project's gap ids. A fix is found by re-running the entry's repro on the newest compiler, and recorded here with
the commit that made it pass.

**Priorities:**
- **HIGH:** wrong or dangerous behaviour today: a crash, or a permanent bad publish.
- **MED:** a real capability missing, with a workaround that costs something.
- **LOW:** ergonomics or docs.

---

## OPEN

None, since 2026-10-26.

## FIXED — kept for the record

KRD-7, KRD-8 and KPG-38's citation were verified on `0.9.573` (tag `v0.9.573`) and `0.9.577+g135c27c5`, each with
the repro it was filed with; each still fails on `0.9.542`. The package's floor and CI pin moved to `0.9.573` in the
same change, the first tag with all three.

### KRD-15 · MED · No shared mutable state across isolates: a cache per pool, a shared slot map and a shared master hint wait for KR-226 — FIXED in v0.9.734 (KR-226)

**Found** 2026-10-21, planning 0.3.0. An absence: cstar's ROADMAP KR-226 (`Locked<T>`, a lock window), which names "a
shared cache, a connection table" as its case.

**What it costs.** Isolates share nothing mutable. `Shared` is not `Sendable`, and `Atomic<T>` holds a scalar
(`lib/std/concurrent/atomic.kama`). So state that a pool's isolates would share must live behind an owner isolate, at
a channel round trip (2.5 µs, KRD-14) per access. That defeats the four designs the peers use:
- **One client-side cache per pool,** as redis-py, go-redis, Jedis and node-redis keep. A local cache's hit should cost
  a hash lookup, not a hop. 0.3.0 keeps one cache per connection instead (rueidis's design, production-grade on its
  own), at the price of hits split across the pool's connections and a cache's memory per connection.
- **One slot map and per-node pools under one cluster client** (go-redis, redis-py, Jedis). 0.3.0's cluster pool
  leases whole `Cluster`s instead. Each costs about 320 KiB resident and a link to every primary it uses (measured: 64
  Clusters on a three-primary cluster held 21.9 MiB and 256 sockets), and each reads the map and follows MOVED alone.
- **A found-master hint shared by a pool's connections,** so a Sentinel failover is asked of the sentinels once, not
  once per pooled connection.
- **One token cache across a credentials provider's forks,** so a provider that fetches tokens over the network
  fetches once per pool, not once per connection.

**What would close it:** KR-226 as designed, a `Sendable` `Locked<T>` whose payload is reached only inside a `borrow`
window.

**Workaround:** none built. The per-connection cache, the whole-`Cluster` lease and the per-connection provider fork
are designs of their own, documented with their costs, not stand-ins to delete.

**Closed** 2026-10-26, on v0.9.734 (2026-10-24), release, on the Apple M4. `Locked<T>` and `ReadWriteLocked<T>` are
`Sendable` handles whose copies share one cell, and the payload is reached only inside a `borrow` window that may not
wait or take another lock (`@parks`). The repro: a `Locked<Map<int64, int64>>`, one `copy` given to each isolate; each
access is one window, a lookup and a put on a miss, over 1000 keys:

```kama
borrow this.cache.lock().value() as m {
    Optional<int64> hit = m.get(key: k);
    bool missed = match (hit) { case Some(value: v): false; case None: true; };
    if (missed) { m.put(key: k, value: i); }
}
```

| isolates, 1 000 000 accesses each | wall time over all accesses, two runs |
|---|---|
| 1 | 7 ns, 9 ns |
| 4 | 16 ns, 23 ns |
| 8 | 26 ns, 24 ns |

So an access costs 7–9 ns alone, and about 200 ns for each isolate with eight of them at once, against the 2.5 µs
round trip to an owner isolate this entry measured. Each design it names is possible now, and they are under
"Carried, to be placed in a release" in docs/ROADMAP.md. Using one moves the floor to v0.9.734.

### KRD-14 · MED · An isolate cannot wait on a socket and a channel at once, so a connection shared by isolates cannot multiplex — FIXED in 0.9.719 (KR-201), tagged in v0.9.719

**Found** 2026-10-21, planning 0.3.0 (docs/ROADMAP.md, "Phase 7b: where to start"). An absence, so it cites cstar's
files rather than a repro.

**What it costs.** Five of the eight Redis clients surveyed share one connection per server among their callers and
pipeline what they send. rueidis does this by default (`PipelineMultiplex`); node-redis writes a tick's commands as one
batch; GLIDE and Lettuce multiplex; go-redis 9.22 offers it as an option. 0.3.0 ships a pool instead, as redis-py,
go-redis and Jedis do. A pool is production-grade, but under concurrency each command pays a whole round trip.

**Measured** on an Apple M4 (10 cores), on `0.9.713+g03d52a6b`, release, against Redis 8.10.2 in podman:

| | each |
|---|---|
| a channel round trip between two isolates (two bounded channels, 100 000 rounds) | 2.5 µs |
| PING over a `Connection`, one at a time, through podman's port forwarder | 220 µs |
| the same, inside the container (`redis-benchmark -c 1 -P 1`) | 70 µs |
| PING over a `Connection`, pipelined 100 at a time | 2.4 µs |
| the same, inside the container (`-P 100`) | 0.9 µs |

So the hop to an isolate that owns the socket costs about one pipelined command, and 1–4 % of a round trip. With many
isolates sending at once, it would pay for itself many times over.

**What blocks it.** An isolate that owns the socket must wait for two things together: its callers' requests and the
server's replies. `std::net::Poller` waits on descriptors only (`lib/std/net/poll.kama:31-74`, `add(fd:)` and
`wait`). A `Channel` is a mutex with a condition variable and has no descriptor or waker
(`lib/std/concurrent/channel.kama:21-22`, with `recv`, `tryRecv` and `recvTimeout` only). So the owner can only
alternate a channel wait and a socket wait, each with a timeout, which adds latency to every call, or spin.

**What would close it**, in either order:
- **A channel a `Poller` can wait on** (its readiness as a descriptor: eventfd, or kqueue's `EVFILT_USER`). A
  socket-owning isolate with auto-pipelining becomes possible today, at about one hop a call.
- **KR-3 (fibers, thread-per-core)** removes the hop as well: one multiplexed connection per core, its callers fibers
  on the same scheduler.

Either one makes a multiplexed client the better design here, and this package would add one beside the pool.

**Workaround:** none. The pool is the design until one lands (ROADMAP, phase 7b, decision 1).

**Since:** cstar's 0.9.719 (KR-201) adds `Poller.waker(token:)` and `Receiver.wakeOnSend`, "a channel is one more
thing a loop waits on", and the v0.9.719 tag carries it (2026-10-22). This entry's repro and a multiplexed connection
are to be tried on it, and the entry closed or narrowed.

**Closed** 2026-10-22, on v0.9.719, release, against Redis 8.10.2 through podman's forwarder, on the Apple M4 the
entry was measured on. One isolate owns a connection and waits on its socket and on a channel of requests through one
`Poller`: `p.waker(token:)`, given to `Receiver.wakeOnSend`, and the socket added under a token of its own. It writes
every request queued since its last wait as one batch, and gives each `+PONG` to the oldest request waiting. The core
of the owner's loop:

```kama
Result<Waker, IoError> rw = p.waker(token: WORK);
Waker w = match (give rw) { case Ok(value: x): give x; case Err(error: e): { return; } };
asks.wakeOnSend(waker: give w);                                  // a send to an empty queue ends the wait
Result<Unit, IoError> added = p.add(fd: link.rawHandle(), interest: Interest::Read, token: SOCKET);
Events ev = Events.withCapacity(capacity: 4);
while (answered < total) {
    Result<int32, IoError> n = p.wait(events: ev, timeoutMs: 5000);
    // drain `asks` with tryRecv into one write; if an event has token SOCKET, read the replies and answer in order
}
```

| | each |
|---|---|
| a request through a channel to an isolate waiting in `Poller.wait`, and its answer (100 000 rounds, no socket) | 5.3 µs |
| 1 caller, 2000 PINGs: one shared connection, or a connection of its own | 227 µs, or 209 µs |
| 4 callers, 2000 PINGs each | 58 µs, or 89 µs |
| 16 callers, 2000 PINGs each (the shared one wrote 32 000 PINGs in 6989 batches) | 16.5 µs, or 47 µs |

So a connection shared by isolates can multiplex now, and with 16 callers it costs a third of a connection each. A
multiplexed connection beside the pool is under "Carried, to be placed in a release" in docs/ROADMAP.md. KR-3 (fibers)
would remove the hop as well.

### KRD-16 · MED · KR-230 removed `std::net::Ready` with no tag that has `Event`: no source builds on both the newest tag and cstar's newest build, so 0.3.0 cannot publish — FIXED by the v0.9.719 tag

**Found** 2026-10-21, gating 0.3.0. cstar's KR-230 (`Poller` over each OS's own mechanism, 0.9.717–0.9.718) replaced
`Ready` with `Event` and `Events`, and `Poller.add`/`wait` now take a token and a ready list. No tag carries it: the
newest is v0.9.707. This package's users install tags, so its floor is v0.9.707 and CI pins it, while the registry
checks a publish with cstar's newest build. Each half refuses what the other needs, so a release built on today's tag
cannot publish, and one ported to KR-230 cannot build for its users. 0.3.0 is ready, gated on v0.9.707 and on cstar's
committed 0.9.716, and waits on this.

**Repro**, two whole programs, `kama check` on each:
```kama
// old.kama
import { core::println, std::net::Poller, std::net::Interest, std::net::Ready, std::io::IoError };

fn uint8 main() {
    Result<Poller, IoError> made = Poller.create();
    match (give made) { case Ok(value: p): { println(s: "made"); } case Err(error: e): { return 1; } };
    Ready r = Ready.of(readable: false, writable: false);
    return 0;
}
```
```kama
// new.kama
import { core::println, std::net::Poller, std::net::Interest, std::net::Event, std::net::Events, std::io::IoError };

fn uint8 main() {
    Result<Poller, IoError> made = Poller.create();
    match (give made) { case Ok(value: p): { println(s: "made"); } case Err(error: e): { return 1; } };
    Events events = Events.withCapacity(capacity: 8);
    return 0;
}
```

| | `old.kama` | `new.kama` |
|---|---|---|
| v0.9.707 | OK | FAILED (4 errors) |
| `0.9.719+g44a0db85` | FAILED (3 errors) | OK |

**What it costs here.** `Transport.wait` returns `std::net::Ready`, so the type is in this package's public contract
(src/transport.kama), and `TcpTransport`, `UnixTransport`, the TLS transport, the wire and a `ClusterSubscriber`'s wait
use `Poller` and `Ready` (46 errors on 0.9.719). The unit program's scripted server and the live program's relays
implement or use them too.

**What would close it:** a tag with KR-230 (and KR-201, which this package's KRD-14 asked for), so the floor can move to
it and the port be made once; or `Ready` and the one-descriptor `add`/`wait` kept beside the new forms until a tag
carries both.

**Workaround:** none built. When a tag carries KR-230, the port is planned to give `Transport.wait` a `Ready` of this
package's own, so that a later change to `std::net` changes no user's `Transport` again (raised with the maintainer).

**Closed** 2026-10-22: cstar tagged v0.9.719 (2026-10-22), with KR-230 and KR-201, rather than keeping `Ready` beside
the new forms (GOALS #4, one way to do a thing; pre-1.0 source breaks are allowed). On v0.9.719 and
`0.9.719+g00e13b15` alike, `old.kama` fails (3 errors, "module `std.net` does not export `Ready`") and `new.kama` is
OK. The floor and CI pin moved to v0.9.719, and the port went as planned: `Transport.wait` takes `redis::Interest` and
answers `redis::Ready`, this package's own, so the contract names no `std::net` type. The socket transports wait
through one `Events` each, and register a socket again only when the side waited for changes.

### KRD-13 · MED · `kama check` takes an `Optional<R>` where a resource `R` is wanted, and only the C compiler refuses it — FIXED in 0.9.715, tagged in v0.9.719

**Found** 2026-10-21, on `0.9.707` (tag `v0.9.707`) and cstar's `0.9.713+g03d52a6b`, writing phase 7b's first repro:
`taken.add(item: this.provider.pop())`, which is wrong, since `pop()` answers `Optional<T>`. For a number the checker
refuses the same mistake, in good words: "a local is declared `int32`, so it cannot be initialized with an
`Optional<int32>` — take its value out with `match`". It also refuses an unrelated resource ("argument `b` expects a
`Box`, so it cannot be given a `Other`"). But an `Optional` of the very resource wanted passes `kama check`, as a
local's initializer and as an argument. `kama build` then fails in clang, in the generated C's names.

**Repro**, a whole program:

```kama
import { std::collections::DynamicArray };
type resource Box { int32 n; public ctor make(int32 n) { this.n = n; } }
fn void keep(Box b) { }
fn uint8 main() {
    DynamicArray<Box> from = DynamicArray.empty();
    from.add(item: Box.make(n: 1));
    from.add(item: Box.make(n: 2));
    Box b = from.pop();      // an Optional<Box> where a Box is wanted
    keep(b: from.pop());     // and as an argument
    return 0;
}
```

| | `kama check` | `kama build` |
|---|---|---|
| `v0.9.707`, `0.9.713+g03d52a6b` | `OK (4 units analyzed)` | clang: "assigning to 'k_Fkrd13__Box' … from incompatible type 'kama__Optional_k_Fkrd13__Box'" at 8:9, and "passing 'kama__Optional_k_Fkrd13__Box' to parameter of incompatible type 'k_Fkrd13__Box'" at 9:20 |

**Why MED:** the registry checks a publish with `kama check`, so a package with this mistake on a path its own build
never compiles (a `@compileFor` arm, say) would pass the registry and fail for every consumer. Here the build caught
it at once, so nothing is worked around.

**What would close it:** the number case's refusal, for a resource payload too.

**Workaround:** none needed; the code takes the value out with `match (give p) { case Some(value: x): … }`, as it
should.

**Closed** 2026-10-22: on v0.9.719 and cstar's `0.9.719+g00e13b15`, `kama check` refuses both lines of the repro in
the number case's words: "a local expects a `Box`, so it cannot be given an `Optional<Box>` — take its value out with
`match` (`case Some(value: v): …` / `case None: …`)" at 8:4, and the same for argument `b` at 9:4. cstar's `d4357ddb`
(0.9.715). Nothing here worked around it.

### KRD-12 · MED · A value-producing `match` arm that ends in `panic` has no form both kinds of compiler take — FIXED in 0.9.696, tagged in v0.9.707

**Found** 2026-10-20, on cstar's `0.9.696+gc86f3e82`, a build of work then staged and not yet committed (its
VERSION and SPEC.md, *Unreachable code is an error*). The new rule refuses a statement after one that never
completes, a `panic` among them, and lets a value-producing arm end in a `panic`. The tags take neither half: an arm
must end in `:=` or in `return`, `break` or `continue`. So an arm that can only stop the program builds on one kind of
compiler or the other, never both. The test programs had 37 such arms (`{ …; panic(msg: …); := x; }` and
`{ …; panic(msg: …); return x; }`).

**Repro**, a whole program (`fn uint8 main()` on 0.9.696, KRD-11):

```kama
import { core::println };
fn int32 viaArm(Optional<int32> o) {
    return match (o) {
        case Some(value: v): v;
        case None: { panic(msg: "none"); := -1; }   // 0.9.696: `{ panic(msg: "none"); }`
    };
}
fn int32 main() { int32 w = viaArm(o: Optional::Some(value: 4)); println(s: "${w}"); return 0; }
```

| | `{ panic(…); := -1; }` | `{ panic(…); }` |
|---|---|---|
| `v0.9.667`, `v0.9.675` | prints `4` | refused: "a value-producing `match` arm block must end in `:= <expr>;` or diverge (return/break/continue)" |
| `0.9.696+gc86f3e82` | refused: "unreachable code — the `panic` … never returns" | prints `4` |

The rest of the rule has forms every compiler takes, and the tree uses them: nothing after a `while (true)` with no
`break` (13 places in the library, 2 in the examples), nothing after a `panic` that ends a function, nothing after a
`match` whose every arm returns. The tags accept each of those as the function's end.

**What would close it:** a tag that counts a `panic` as divergence in an arm, as 0.9.696 does; or, in the new rule, a
window that takes `:=` after a `panic` with a word naming the new form.

**Workaround, since 2026-10-20:** each test program has `fn T stop<T>(const ref string msg) { panic(msg: msg); }`
(a function may end in `panic` on every compiler), and an arm that stops ends `:= stop::<T>(msg: …)`, or
`return stop::<R>(msg: …)`. When a tag counts a `panic` in an arm, the arms say `{ …; panic(msg: …); }` and `stop`
goes.

**Closed** 2026-10-21: v0.9.707 carries the rule, and the floor moved there. The 39 arms that stop say
`{ …; panic(msg: …); }`, and `stop` is gone from both test programs.

### KRD-9 · MED · 0.9.675 refuses copying between two windows of one buffer, and std has no in-place copy — FIXED in 0.9.694, tagged in v0.9.707

**Found** 2026-10-19, on cstar's `0.9.675+g4afcda97`, at its first build of this package. It is a regression of
`ada8bd36` ("check: a `ref` argument that holds the receiver is refused, and a contract receiver is judged"). The
package builds on `v0.9.667` and `v0.9.673`. Once a tag carries the rule, it does not build at all:
`src/resp/reader.kama:187`, `Reader.spare`, slides the unread bytes to the front of its buffer before it reads more.

**Repro**, a whole program:

```kama
import { core::println, std::collections::FixedArray };

// Slide the unread tail of a buffer to its front, as a reader does before it reads more: two windows of one buffer
// that do not overlap, one written and one read.
type resource Buffer {
    FixedArray<uint8> buf;
    public ctor make() {
        this.buf = FixedArray.make(size: 8);
        isize i = 0;
        while (i < 8) { this.buf[i] = cast<uint8>(i); i = i + 1; }
    }
    public fn void slide(isize start, isize unread) {
        this.buf.sliceMut(from: 0, count: unread).copyFrom(source: this.buf.slice(from: start, count: unread));
    }
    public const fn uint8 at(isize i) { return this.buf[i]; }
}

fn int32 main() {
    Buffer b = Buffer.make();
    b.slide(start: 5, unread: 3);
    uint8 a0 = b.at(i: 0); uint8 a1 = b.at(i: 1); uint8 a2 = b.at(i: 2);
    println(s: "ok ${a0} ${a1} ${a2}");
    return 0;
}
```

- `v0.9.667` and `v0.9.673`: prints `ok 5 6 7`.
- `0.9.675+g4afcda97`: refused at the `copyFrom` line, with "`this.buf` is borrowed by the view argument `source`
  while `this.buf.sliceMut(from: 0, count: unread)` is the receiver of non-`const fn` `copyFrom` — the method may
  grow the very storage that window views, leaving it dangling".

**Why it is a gap, on either reading:**
- **The reason does not hold for this receiver.** The receiver is a `View`, a window of fixed length, and its
  `copyFrom` cannot grow or free the `FixedArray` beneath it. A collection receiver (`buf.addAll(items:
  buf.view())`) could, and refusing that is right.
- **Refusing two windows of one buffer, one written, may be the intent.** Rust refuses `buf[..n].copy_from_slice(
  &buf[s..s + n])` too. But Rust answers it with `copy_within`, and std has nothing that does: `DynamicArray`'s
  `memmove` is private to its insert and remove. So kama has no safe way left to move bytes within one buffer.

**What would close it:** let the copy through for a `View` receiver; or give `FixedArray` and `View` a
`copyWithin(from:, count:, to:)` (one `memmove`, overlap allowed), which this reader would use, and which a ring
buffer or a codec also needs.

**Answered in 0.9.694 (`3aea6e59`, "std: `View.copyWithin`"),** checked 2026-10-20 on `0.9.696+gc86f3e82`. The repro
is still refused, now naming the fix ("`copyWithin(from:, to:, count:)` moves elements inside one buffer"), and the
slide written as `this.buf.viewMut().copyWithin(from: start, to: 0, count: unread)` prints `ok 5 6 7`, debug and
release. No tag has `copyWithin` yet, so the loop below stays until the floor moves to one that does; then
`Reader.spare` makes that one call, and `tools/mutations/krd9-slide.json` aims at it.

**Workaround, since 2026-10-19:** `Reader.spare` moves the unread bytes one at a time
(`this.buf[i] = this.buf[this.start + i]`), one window at a time, so the package builds on 0.9.675 too, which the
registry checks with. Refusing two windows of one buffer is defensible, so the ask is now the second reading's: a
`copyWithin` (one `memmove`). When std has it, the loop goes, and the reader moves its bytes in one call again. A unit
test (`resp slide`) makes the reader slide with part of a line unread, and a mutation of the loop fails it
(`tools/mutations/krd9-slide.json`).

**Closed** 2026-10-21: v0.9.707 is the first tag with `copyWithin`, and the floor and CI's pin moved there. `Reader.spare`
slides its unread bytes with one call, `this.buf.viewMut().copyWithin(from: this.start, to: 0, count: unread)`, the
byte loop is gone, and `tools/mutations/krd9-slide.json` aims at the call (`resp slide` catches it).

### KRD-11 · MED · `main`'s type changed with no overlap: every tag refuses `fn uint8 main()`, and 0.9.684 refuses `fn int32 main()` — CLOSED by the floor's move to v0.9.690

**Found** 2026-10-20, on cstar's `0.9.690+g735d65c8`. The rule came in `d0ffc06e` ("check: `main` returns the exit
status in the platform's own type; `fn int32 main()` is refused", 0.9.684). The library itself has no `main` and
checks clean on 0.9.690. But this package's two test programs and its eight examples, which ship in the package, have
`fn int32 main()`, and none of them builds there.

**Repro**, two whole programs:

```kama
import { core::println };
fn int32 main() { println(s: "int32 main"); return 0; }
```

```kama
import { core::println };
fn uint8 main() { println(s: "uint8 main"); return 0ui8; }
```

| | `int32` main | `uint8` main |
|---|---|---|
| `v0.9.667` | prints | refused: "`main` is declared `fn int32 main()` — it returns the exit status (0 for success)…" |
| `v0.9.675` | prints | refused, the same |
| `0.9.690+g735d65c8` | refused: "`main` returns the exit status in the platform's own type — write `fn uint8 main()`…" | prints |

**Why it is a gap:** the new rule is sound (an `int32` status was truncated at exit without a word). But no compiler
accepts both forms, so no program builds on both a tag and cstar's newest build. A package whose floor is a tag
cannot switch until a tag carries the rule, and until then cstar's newest build can only be gated on an edited
copy. Every published package with an example or a test program has this problem; for this one, that is ten
programs.

**What would close it:**
- accept `fn int32 main()` for a window, with a warning that names the new form; or
- tag a release that carries 0.9.684, so a floor can move to it. **v0.9.690 is that tag** (2026-10-20): this
  package's unit program and examples are green on it with `fn uint8 main()`. Moving the floor and CI's pin there,
  and the ten `main`s, is the maintainer's call, since a consumer then needs v0.9.690. The channel `send` (0.9.680)
  is in it too; `string.find` (0.9.706) is not.

**Workaround, since 2026-10-20:** nothing in the tree. The gate on cstar's newest build runs on a scratch copy whose
`main`s say `fn uint8 main()`, a one-line change in each, since every `main` here returns the literal 0 or 1. On that
copy, `tools/test.sh` is green on 0.9.690: the unit program, debug and release, and every example built. When a tag
carries the rule, the floor and CI's pin move to it, and the ten `main`s change, in one commit.

**A second change with no overlap, found 2026-10-20 on `0.9.692+gbc03abd0`:** a channel's `send`. `28e7e363` (0.9.680,
"channels return `Result`") made it return `Result<Unit, Undelivered<T>>` and removed `SendResult`, which every tag
has and needs. The live test program's Unix-socket relay sends its result on a channel, so it builds on no compiler
of the two kinds either. Repro, run with `fn uint8 main()` on 0.9.692 and `fn int32 main()` on the tags:

```kama
import { core::println, std::concurrent::Channel, std::concurrent::Sender, std::concurrent::SendResult };
fn int32 main() {
    Channel<int32> ch = Channel.bounded(capacity: 1);
    Sender<int32> tx = ch.sender();
    SendResult<int32> r = tx.send(item: 7);   // 0.9.680 on: Result<Unit, Undelivered<int32>> r = …
    println(s: "sent");
    return 0;
}
```

| | `SendResult<int32> r = tx.send(…)` | `Result<Unit, Undelivered<int32>> r = tx.send(…)` |
|---|---|---|
| `v0.9.667`, `v0.9.675` | prints | refused: "`std.concurrent` does not export `Undelivered`" |
| `0.9.692+gbc03abd0` | refused: "`std.concurrent` does not export `SendResult`" | prints |

**A third, found 2026-10-20 on `0.9.707+ga9f325c3`:** `string.find` answers `Optional<isize>` since `a9f325c3` (0.9.706,
"`find` answers `isize`"), where every tag answers `Optional<usize>`. This package does not call it, but `@kama/tls`
0.1.5 does (`src/tls.kama:85`, `Optional<usize> dash = text.find(substring: " - ")`), so nothing that depends on it
builds on 0.9.706 and later. Run on both, `fn uint8 main()` on 0.9.707:

| | `Optional<usize> d = t.find(…)` | `Optional<isize> d = t.find(…)` |
|---|---|---|
| `v0.9.667` | prints | refused: "a local expects an `Optional<isize>`, so it cannot be given an `Optional<usize>`" |
| `0.9.707+ga9f325c3` | refused: "a local expects an `Optional<usize>`, so it cannot be given an `Optional<isize>`" | prints |

The same fix closes all three: a window in which the old form is accepted with a word naming the new one, or a tag
that carries them. The scratch copy for cstar's newest build would edit the relay's two sends too, if the
live program were gated there; today only the unit program and the examples are.

**Closed** 2026-10-20: the floor and CI's pin moved to `v0.9.690`, the first tag that carries 0.9.684's rule and
0.9.680's `send`, and the ten `main`s, the README's programs and the live program's two relays took the new forms in
the same commit. The tree now builds unedited on `v0.9.690` and on `0.9.707+g789c49cc`, and the scratch copy is gone.
`string.find` still differs between them, but nothing here calls it, and `@kama/tls` 0.1.6 no longer does.

### KRD-10 · MED · An application named like a dependency's module broke that dependency's imports — FIXED in 0.9.693

**Found** 2026-10-19, building this package's examples: one named `tls` would not build, its errors all inside
`@kama/redis` (`module tls is not visible from redis`). A project's name is its root module, and kama resolved
`@kama/redis`'s own `import { tls::… }` to the application instead of to `@kama/tls`. Any application named `tls`
that uses `@kama/redis`, or `@kama/postgres`, fails the same way, with errors that point at the library.

**Repro**, three files and two applications that differ only in their name:

```
middle/kama.json      { "name": "@repro/middle", "version": "0.1.0", "kind": "library", "kama": ">=0.9.667",
                        "dependencies": { "@kama/tls": { "version": "^0.1.3" } },
                        "modules": { ".": { "visibility": "public" } } }
middle/src/middle.kama
                      import { tls::version };
                      export { engine };
                      fn string engine() { return version(); }
app-NAME/kama.json    { "name": "NAME", "version": "0.1.0", "kind": "executable", "kama": ">=0.9.667",
                        "entry": "src/main.kama", "dependencies": { "@repro/middle": { "path": "../middle" } },
                        "modules": { ".": { "visibility": "internal" } } }
app-NAME/src/main.kama
                      import { core::println, middle::engine };
                      fn int32 main() { string e = engine(); println(s: give e); return 0; }
```

- NAME `other`: prints `4.1.1` on `v0.9.667`, `v0.9.673` and `0.9.675+g4afcda97`.
- NAME `tls`: refused on all three, in the library's file: "`.kama/deps/middle/src/middle.kama:1:9: error: module
  `tls` is not visible from `middle` — its `visibility` in `kama.json` does not name this module`", then "`module
  `tls` does not export `version`".

**What would close it:** a library's imports resolve within the library's own dependencies, whatever the
application is called. Short of that, an application whose name is the module of one of its dependencies, direct
or not, could be refused when its manifest is read, naming the clash, as a reserved word already is ("`name` is
"base", but a project's name is its root module…").

**Workaround:** the example is named `tls_connection`, which it can keep either way. Nothing else here depends on it.

**Fixed** by the second of the two ways asked, in 0.9.693 (`f1e73abc`, "pkg: a project named like a dependency's
module is refused"). Checked 2026-10-20 on `0.9.696+gc86f3e82`: `kama pkg install` of the app named `tls` refuses
it, naming the clash ("'@kama/tls' (required by @repro/middle) imports as 'tls', which is this project's own name …;
rename the project"), and the app named `other` installs. AGENTS.redis.md's rule against an example named `tls`
stays: it is what the refusal now enforces.

### KRD-8 · HIGH · std's `deserialize`, instantiated with a type of the program's, resolved its names in std — FIXED in 0.9.565

Fixed by `f29e282c` ("construction: the into decision reads a ctor's return type in the ctor's own context, not the
caller's"). It was a regression of 0.9.559/0.9.560 (KR-120). The repro prints `entries 1` again, and the unit
program, which `XREAD`'s typed pair reads as `Map<string, DynamicArray<Entry>>`, builds and passes. Nothing here
had a workaround to undo.

### KRD-7 · MED · An adapter over a std type could not name a type of its own module in a method's signature — FIXED in 0.9.566

Fixed by `bb3eef09` ("adapter: an adapter method's signature is read in the adapter's module, not the target's").
The repro prints `total 6`. `RedisArg` now has its `DynamicArray<uint8>` (one binary argument), `<DynamicArray> when
[T: RedisArg]` (an argument per element) and `Uuid` (its text) adapters, which the workaround (`argBytes`, a loop
of `add`, a Uuid's text by hand) stood in for. The coherence the design relies on holds: `<DynamicArray<uint8>>`
beside `<DynamicArray> when [T: RedisArg]` builds, because `uint8` has no adapter.

### KPG-38 (cited) · HIGH · Two files that converted the same primitive to the same contract failed every release build — FIXED in 0.9.543, tagged in v0.9.573

Fixed upstream by `7872c6b6` (KR-114). The two-file repro prints `18 18` in a release build. Each test program's
"one conversion file" rule is gone: `arg_test.kama` no longer holds the helpers the scan tests converted through, and
the README no longer warns about it.

KRD-5 and KRD-6 were verified on 0.9.542 (`99ae9a22`), each with the repro it was filed with. KRD-1 to KRD-4 were
verified on 0.9.530 (`e01de340`) the same way.

### KRD-6 · LOW · A branch whose every inner path moved a value and returned still counted as not moving it — FIXED in 0.9.533

Fixed by `de4de6cf`: a branch's move state is merged at its join only if control can reach the join, judged
structurally (a block diverges when any statement in it does; an `if` when both arms do; a `match` when every arm
does). The repro prints `ok -1` (it was refused with "`v` is moved on some paths but not others"). It was the same on
0.9.523, so not a regression. `Connection.call`'s early exits were never a workaround to undo; they stay, because
the package's floor is 0.9.529.

### KRD-5 · HIGH · A type that held a collection of itself through a resource did not compile — FIXED in 0.9.531

Fixed by `09ff9968`: whether an enum copies now rests on what each payload type declares, a fact settled before
generic instances register, so `DynamicArray<E>` no longer keeps a `copy` ctor for an `E` that does not copy. It was
a regression of 0.9.527 (KRD-4's fix), which judged an enum "owning nothing" before that was known. The repro prints
`ok` (it failed with "`DynamicArray<E>` has no method `copyAllFrom`"). `kama check` on @kama/postgres, which broke the
same way on `DynamicArray<PgError>` and `DynamicArray<BatchResult>`, is clean again. Nothing here needed undoing: a
connect attempt holds an `IoError` by design.

### KRD-4 · LOW · `copy` did not reach through an `Optional` — FIXED in 0.9.527

Fixed by `fdccadda`: an enum copies exactly when every payload it can hold copies, as a collection does when its
elements do. The repro builds and prints `ok` (both `copy`s of an `Optional<string>` were refused). `RedisUrl`'s
accessors `copy` their optional fields, and the `copied` helper in src/url.kama is gone.

### KRD-3 · MED · No bulk append to a `DynamicArray`, and no `capacity()` — FIXED in 0.9.528

Fixed by `ad253e47`: `DynamicArray.addAll(items:)`, `View.copyFrom(source:)` and `DynamicArray.capacity()`, each one
`memcpy` for plain elements in every build. On the repro's 256 MiB, `addAll` takes 57 ms in debug and 56 ms in release
(the `add` loop took 1502 ms and 155 ms), and `copyFrom` 55 ms and 27 ms. The reader's payloads, its buffer's slide
and growth, `feed`, and the writer's `putBytes` use them; the reader reads its string's capacity rather than keeping
its own count (`textCap` is gone). Growth is still the reader's own, doubling but never past a string's declared
length.

### KRD-2 · MED · An isolate's stack was the OS default — FIXED in 0.9.529

Fixed by `9cb1578e`: an isolate's stack is stated, and is the main thread's (8 MiB on a 64-bit native target, 2 MiB
on 32-bit, 256 KiB on wasm); `spawn(stack: n)` asks for more. The repro prints `isolate: 20000` (it died with SIGBUS).
`resp::Limits.maxDepth` is back to hiredis's 1024 (it was 128 because of this), and resp_test.kama walks a reply that
deep inside an isolate, in a debug build.

### KRD-1 · MED · A local that was given away could not be assigned again — FIXED in 0.9.526

Fixed by `3cd26bbd`: assignment re-arms a moved local. A local moved on only some paths still cannot be assigned, and
inside a loop a value declared outside it may be moved only if every path back to the loop's start assigns it again.
The repro prints `kids 1`. Nothing here was left to undo: the reader's value stack is its design, not a workaround,
and the test builders that needed it were written another way.
