# Gaps found in kama, from building @kama/redis

It is written **for the cstar project**: each entry is reduced to the smallest program or file that shows it.
Every entry with a repro was **run** on the version named. Nothing is inferred from reading the spec. An entry
that is an absence cites the cstar files that show it instead. This file is excluded from the published
package, as it is in `@kama/postgres` and `@kama/sodium`.

**Current compiler:** `kama 0.9.530`.

**Reporter:** the `@kama/redis` repo. Each open entry names the workaround this package uses, so the workaround
can be deleted when the gap closes. **We are not attached to any workaround.** If a fix changes the right design
here, say so and we will follow it.

**Open now:** KRD-5 (HIGH), KRD-6 (LOW). Entries are numbered KRD-1, KRD-2, …. A gap this package hits that `@kama/postgres` already
filed is cited by its KPG number rather than filed again.

**Priorities:**
- **HIGH:** wrong or dangerous behaviour today: a crash, or a permanent bad publish.
- **MED:** a real capability missing, with a workaround that costs something.
- **LOW:** ergonomics or docs.

---

## OPEN

### KRD-6 · LOW · A branch whose every inner path moves a value and returns still counts as not moving it

**Found:** 2026-10-04, writing `Connection.call`'s read loop (phase 2). **Version:** 0.9.530 (`e01de340`), and the
same on 0.9.523, so it is not a regression.

The move check refuses a function in which every path moves `v`, when one outer branch holds an inner `if` whose
two arms both move `v` and `return`. A plain two-arm `if`/`else` that moves in both arms is accepted. So is the same
logic written as early exits. It looks as if the point after the inner `if`, which no path reaches, is merged as a
path on which `v` is still live.

Repro (an `else if` chain is the same shape, and fails the same way):

```kama
import { core::println, std::collections::DynamicArray };

type resource R {
    int32 n = 0;
    public ctor make(int32 n) { this.n = n; }
    public const fn int32 value() { return this.n; }
}

fn int32 pick(DynamicArray<R> kept, int32 which) {
    R v = R.make(n: which);
    if (v.value() == 0) {
        kept.add(item: give v);
    } else {
        if (v.value() == 1) {
            R dropped = give v;
            return 1;
        } else {
            R last = give v;
            return last.value();
        }
    }
    return -1;
}

fn int32 main() {
    DynamicArray<R> kept = DynamicArray.empty();
    int32 got = pick(kept: kept, which: 0);
    println(s: "ok ${got}");
    return 0;
}
```

```
repro.kama:22:0: error: `v` is moved on some paths but not others and is still live at scope exit — move it on all paths or none, or use Optional<T>
```

**Expected:** it builds and prints `ok -1`, since `v` is moved on every path that reaches the end of its scope.

**Workaround here:** `Connection.call` (`src/connection.kama`) is written as early exits (`if (push) { …; continue; }`
then `if (error) { …; return …; }`), which is as clear. Nothing needs undoing when this is fixed.

### KRD-5 · HIGH · A type that holds a collection of itself through a resource no longer compiles — since KRD-4's fix

**Found:** 2026-10-04, writing `src/error.kama` (phase 2). **Version:** fails on 0.9.530 (`e01de340`); the same
program prints `ok` on the 0.9.523 release (`~/.kama/versions/v0.9.523`). **Suspected:** `fdccadda` (KRD-4,
0.9.527). Its message says "a recursive mention is assumed to copy while it is being judged"; that provisional
answer appears to reach the instantiation of `DynamicArray<E>`'s `copy` ctor.

**Why HIGH:** the published **@kama/postgres 0.2.0 does not compile** on 0.9.530. `kama check kama.json` there
fails on `DynamicArray<postgres::PgError>` (`src/connection.kama:519`) and on `DynamicArray<postgres::BatchResult>`
(`src/connection.kama:1108`), with the same three errors. Any error type whose aggregate variant keeps the errors
it gathered has this shape: `PgError::Connect` → `ConnectError` → `ConnectAttempt` → `DynamicArray<PgError>`.

Repro (nothing in it copies anything):

```kama
import { core::println, std::collections::DynamicArray };

type enum E {
    A,
    B(Box box);
}

type resource Box {
    DynamicArray<E> items;
    public ctor make() { this.items = DynamicArray.empty(); }
}

fn int32 main() {
    Box b = Box.make();
    println(s: "ok");
    return 0;
}
```

On 0.9.530:

```
repro.kama:12:0: error: `std::collections::DynamicArray<E>` has no method `copyAllFrom` — it is declared `when [T: Copyable]`, and `E` (for `T`) does not satisfy `Copyable` (in `DynamicArray<E, GlobalAllocator>`, instantiated here; raised at …/std/collections/dynamic_array.kama:239)
…/std/collections/view.kama:15:0: error: `E` has no `copy` method — use `give` to move it
…/std/collections/dynamic_array.kama:23:0: error: `E` has no `copy` method — use `give` to move it
```

Adding `implements Sendable` to both types changes nothing. `E` is correctly not Copyable: its `B` payload is a
resource without a copy ctor.

**Expected:** the program builds and prints `ok`, as on 0.9.523. `DynamicArray<E>`'s `copy` ctor is not
instantiated for an `E` that does not copy.

**Workaround here:** none needed. `@kama/redis` has no such type: a connect attempt holds the `IoError` that ended
it, not a `RedisError`, because an attempt only ever fails on I/O. That is the design we would choose anyway, so
nothing will need undoing. @kama/postgres has no workaround, and its next build needs this fixed.

## FIXED — kept for the record

KRD-1 to KRD-4 were verified on 0.9.530 (`e01de340`), each with the repro it was filed with. 0.9.530 is not tagged
yet; the newest release is 0.9.523.

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
