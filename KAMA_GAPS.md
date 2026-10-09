# Gaps found in kama, from building @kama/redis

It is written **for the cstar project**: each entry is reduced to the smallest program or file that shows it.
Every entry with a repro was **run** on the version named. Nothing is inferred from reading the spec. An entry
that is an absence cites the cstar files that show it instead. This file is excluded from the published
package, as it is in `@kama/postgres` and `@kama/sodium`.

**Current compiler:** `kama 0.9.542` (tag `v0.9.542`).

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

(none)

## FIXED — kept for the record

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
