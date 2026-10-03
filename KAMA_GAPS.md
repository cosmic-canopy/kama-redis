# Gaps found in kama, from building @kama/redis

It is written **for the cstar project**: each entry is reduced to the smallest program or file that shows it.
Every entry with a repro was **run** on the version named. Nothing is inferred from reading the spec. An entry
that is an absence cites the cstar files that show it instead. This file is excluded from the published
package, as it is in `@kama/postgres` and `@kama/sodium`.

**Current compiler:** `kama 0.9.523`.

**Reporter:** the `@kama/redis` repo. Each open entry names the workaround this package uses, so the workaround
can be deleted when the gap closes. **We are not attached to any workaround.** If a fix changes the right design
here, say so and we will follow it.

**Open now:** KRD-1 (MED), KRD-2 (MED), KRD-3 (MED), KRD-4 (LOW). Entries are numbered KRD-1, KRD-2, …. A gap this package hits that `@kama/postgres` already
filed is cited by its KPG number rather than filed again.

**Priorities:**
- **HIGH:** wrong or dangerous behaviour today: a crash, or a permanent bad publish.
- **MED:** a real capability missing, with a workaround that costs something.
- **LOW:** ergonomics or docs.

---

## OPEN

### KRD-4 · LOW · `copy` does not reach through an `Optional`

**Found** writing phase 1's URL type, on `kama 0.9.523+gfc170153`: an accessor that hands back a copy of an optional
string field.

```kama
import { core::println, std::collections::DynamicArray };

type resource Named {
    Optional<string> label;
    public ctor make() { this.label = Optional::Some(value: "a label"); }
    // A string copies; an Optional of one does not.
    public const fn Optional<string> get() { return copy this.label; }
}

fn int32 main() {
    Named n = Named.make();
    Optional<string> a = n.get();
    Optional<string> b = copy a;
    DynamicArray<string> xs = DynamicArray.empty();
    xs.add(item: "x");
    DynamicArray<string> ys = copy xs;
    println(s: "ok");
    return 0;
}
```

`kama build` refuses lines 7 and 13: `` `Optional<string>` has no `copy` method — add `implements Copyable(bare: …)`, or
use `give` to move it ``. Line 16, the same `copy` of a `DynamicArray<string>`, is accepted: a collection copies when
its element does, and `Optional` is the one generic wrapper that does not. A package cannot add `Copyable` to
`Optional` (it is the language's).

**What would close it:** `Optional<T>` copyable when `T` is, as `DynamicArray<T>` is.

**Workaround** (src/url.kama, `copied`): a borrowing `match` that copies the payload into a new `Optional`.

### KRD-3 · MED · no bulk append to a `DynamicArray`, and no `capacity()`

**Found** writing phase 1's reader, on `kama 0.9.523+gfc170153`. A bulk string's payload moves from the receive
buffer into the `DynamicArray<uint8>` a `Value::Bulk` holds; a string may be 512 MiB.

```kama
import { core::println, std::collections::DynamicArray, std::collections::FixedArray, std::collections::ConstView,
         std::collections::View, std::time::monotonicNow, std::time::Instant, std::time::Duration };

// There is no bulk copy: a ConstView goes into a DynamicArray or a View one element at a time.
fn void appendBytes(ref DynamicArray<uint8> to, ConstView<uint8> from) {
    isize i = 0;
    while (i < from.length()) { to.add(item: from[i]); i = i + 1; }
}

fn isize copyBytes(View<uint8> to, ConstView<uint8> from) {
    isize i = 0;
    while (i < from.length()) { to[i] = from[i]; i = i + 1; }
    return from.length();
}

fn int32 main() {
    isize size = 268435456;   // 256 MiB
    FixedArray<uint8> src = FixedArray.make(size: size);
    isize k = 0;
    while (k < size) { src[k] = truncate<uint8>(k * 7); k = k + 4096; }
    FixedArray<uint8> dst = FixedArray.make(size: size);
    Instant a = monotonicNow();
    isize n = copyBytes(to: dst.viewMut(), from: src.view());
    Instant b = monotonicNow();
    DynamicArray<uint8> grown = DynamicArray.empty();
    grown.reserve(n: size);
    appendBytes(to: grown, from: src.view());
    Instant c = monotonicNow();
    Duration d1 = b - a;
    Duration d2 = c - b;
    int64 viewMs = d1.asNanos() / 1000000i64;
    int64 addMs = d2.asNanos() / 1000000i64;
    uint8 x = dst[size - 4096];
    uint8 y = grown[size - 4096];
    println(s: "256 MiB: View to View ${viewMs} ms, DynamicArray.add ${addMs} ms (check ${x} ${y})");
    return 0;
}
```

On macOS arm64, `--release` prints `View to View 18 ms, DynamicArray.add 155 ms`, and `--debug` prints 1276 ms and
1502 ms. The view loop is fast in release only because the C compiler recognizes it as a memcpy. `add` keeps its
length, capacity and modification count in memory across a `uint8` store that may alias them, so it costs about
0.6 ns a byte: 0.3 s for one 512 MiB string, and 3 s in a debug build.

Nothing in `std::collections` copies a run of elements: `DynamicArray` has `add`, `insertAt` and `reserve`, `View`
has indexing, `swap` and `reverse` (`lib/std/collections/dynamic_array.kama`, `view.kama`). There is also no
`capacity()`, and `reserve(n)` grows to exactly `n` (`dynamic_array.kama:183`), so a caller growing an array as
data arrives must keep its own count of the capacity, or call `reserve` with the running total and copy the whole
array each time.

**What would close it:** `DynamicArray.addAll(items: ConstView<T>)` for a copyable `T` (one `reserve`, one
`memcpy`), `View.copyFrom(source: ConstView<T>)`, and `capacity()`.

**Workaround** (src/resp/reader.kama, `copyBytes`, and the string loop in `Reader.stepBody`; src/resp/writer.kama,
`putBytes`): byte loops, with the reader keeping its own capacity count (`textCap`) and growing it geometrically.

### KRD-2 · MED · an isolate's stack is the OS default, so a depth that works on the main thread crashes in one

**Found** proving phase 1's reply tree before writing the reader, on `kama 0.9.523+gfc170153`. A RESP reply nests, so
dropping, comparing and serializing one recurses once per level. The reader bounds the depth, and the bound has to
hold wherever a reply is used, including inside an isolate.

```kama
import { core::println, std::concurrent::Isolate };

// A plain recursion, nothing kept on the heap. Its frames are whatever the C compiler gives it.
fn int64 down(int64 n) {
    if (n == 0) { return 0; }
    return down(n: n - 1) + 1;
}

type resource Job implements Sendable {
    int64 depth = 0;
    int64 got = -1;
    public ctor make(int64 depth) { this.depth = depth; }
    public fn void run() { this.got = down(n: this.depth); }
    public const fn int64 result() { return this.got; }
}

fn void worker(ref Job j) { j.run(); }

fn int32 main() {
    int64 depth = 20000;
    int64 here = down(n: depth);
    println(s: "main thread: ${here}");
    Job j = Job.make(depth: depth);
    scope { spawn worker(j: ref j); }
    int64 there = j.result();
    println(s: "isolate: ${there}");
    return 0;
}
```

`kama build --debug` on macOS arm64 prints `main thread: 20000`, then the isolate dies with SIGBUS (exit 138). The
main thread has the process's 8 MiB stack. An isolate gets `pthread_create(&t, NULL, …)` (`include/kama_isolate.h:22`),
so the OS default thread stack: 512 KiB on macOS, 8 MiB with glibc, 128 KiB with musl. Nothing in `spawn` or
`Isolate` chooses it, and the SPEC does not say what it is. So the same code works on the main thread and on Linux
with glibc, and crashes in an isolate on macOS or Alpine.

Measured on the reply tree itself (a `type enum` recursing through `DynamicArray<Self>`, debug build, macOS isolate):
dropping a value 4000 levels deep is fine and 8000 crashes; a hand-written recursive compare crashes between 900 and
1000. hiredis 1.4.1 lets a reply nest 1024 deep.

**What would close it:** a stated isolate stack size, the same on every target (or at least a floor), and a way for
the spawner to ask for more (`spawn(stack: …)`, or a field of the handle form).

**Workaround** (src/resp/reader.kama, `Limits.maxDepth`): the reader's default depth is 128, not hiredis's 1024. That
leaves the recursive walks this package and serde do about 8x headroom on macOS's 512 KiB, and room on musl's 128 KiB.
A caller can raise it. hiredis's own depth cases run with their 1024 on the main thread.

### KRD-1 · MED · a local that was given away cannot be assigned again

**Found** proving phase 1's reply tree, on `kama 0.9.523+gfc170153`. Wrapping a value in place, `t = Node(give t)`,
is how a parser closes an aggregate and how a test builds a deep reply.

```kama
import { core::println, std::collections::DynamicArray };

type enum Tree { Leaf, Node(DynamicArray<Tree> kids); }

fn int32 main() {
    Tree t = Tree::Leaf;
    DynamicArray<Tree> one = DynamicArray.empty();
    one.add(item: give t);
    t = Tree::Node(kids: give one);
    isize n = match (t) { case Leaf: 0; case Node(kids: k): k.length(); };
    println(s: "kids ${n}");
    return 0;
}
```

`kama build` refuses it: `reassign.kama:9:0: error: use of `t` after it was moved (a `give` consumed it)`. Line 9 is
the assignment, which reads nothing from `t`: it gives the moved-from local a new value, after which every later use
is sound. In a loop the same shape (`one.add(item: give t); t = Tree::Node(kids: give one);`) is refused twice, as
"cannot `give` `t` inside a loop — it would be moved again on the next iteration" and as the use after move, though
the assignment comes before the next iteration can see `t`. The SPEC's move rules ("moving inside a loop a value
declared outside it … rejected") do not say whether an assignment re-arms the local; a reader of the source takes it
to.

**Workaround** (src/resp/reader.kama and tests/unit/src/resp_test.kama): the value lives in a `DynamicArray` of zero
or one, taken out with `pop()` and put back with `add`, so no local is ever given and reassigned. The reader's value
stack works that way anyway; the test builders pay the extra `match` on `Optional`.

## FIXED — kept for the record

(none)
