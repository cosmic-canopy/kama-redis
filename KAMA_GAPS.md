# Gaps found in kama, from building @kama/redis

It is written **for the cstar project**: each entry is reduced to the smallest program or file that shows it.
Every entry with a repro was **run** on the version named. Nothing is inferred from reading the spec. An entry
that is an absence cites the cstar files that show it instead. This file is excluded from the published
package, as it is in `@kama/postgres` and `@kama/sodium`.

**Current compiler:** `kama 0.9.667` (tag `v0.9.667`), which CI pins and the manifests' floor names. Each repro is
also run on cstar's newest build. The package was last verified on `v0.9.673` (2026-10-19, the newest tag and cstar's
newest build): unit and live gates green, debug and release, nothing changed.

**Reporter:** the `@kama/redis` repo. Each open entry names the workaround this package uses, so the workaround
can be deleted when the gap closes. **We are not attached to any workaround.** If a fix changes the right design
here, say so and we will follow it.

**Open now:** KRD-9, KRD-10. Entries are numbered KRD-1, KRD-2, …. A gap this package hits that `@kama/postgres` already
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

### KRD-9 · HIGH · 0.9.675 refuses copying between two windows of one buffer, and std has no in-place copy

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

**Workaround:** none taken. The package's floor and CI's pin (`v0.9.667`) and the newest tag (`v0.9.673`) build it.
Until the fix, this package's gate uses `v0.9.673` in place of cstar's newest build.

### KRD-10 · MED · An application named like a dependency's module breaks that dependency's imports

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

## FIXED — kept for the record

KRD-7, KRD-8 and KPG-38's citation were verified on `0.9.573` (tag `v0.9.573`) and `0.9.577+g135c27c5`, each with
the repro it was filed with; each still fails on `0.9.542`. The package's floor and CI pin moved to `0.9.573` in the
same change, the first tag with all three.

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
