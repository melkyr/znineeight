# Z98 Standard Library — User Guide

The Z98 standard library is the set of `std_*.zig` modules shipped with the
self-hosted `zig1` compiler. It is written in Z98 — a deliberately concrete
subset of Zig — and compiled in-process, on demand, when a user program imports
a module. The module sources in `sf/src/std_*.zig` are the source of truth; this
page is the curated entry point, and each domain has its own detailed doc under
[`sf/docs/std_lib/`](#domain-docs).

Because Z98 has no generics, the library is **concrete**: each function and
container is written for exact types (`u32`, `[]const u8`, `*void`, …). The
language surface is slices (`[]u8` / `[]const u8`), optionals (`?T`), error
unions (`!T`), `try` / `catch`, and `if (x) |v| { … }` unwrapping. OS-specific
work is hidden behind private per-target PAL units, so the public API is the
same on linux and win32.

## What the standard library is not

- **Not the official Zig standard library.** Z98 is an independent project and
  intentionally differs from Zig.
- **Not generic.** There is no `ArrayList(T)`, no traits, no comptime
  parameterization; the three hash maps and one heap are the only containers.
- **Not an allocator framework.** There is no allocator interface, no `free`,
  and no reference counting — the arena is the only allocation mechanism (R1).
- **Not concurrent.** No threads, locking, or atomics (R5).
- **Not a hidden runtime.** Coroutines have no executor and no poll loop; the
  caller drives the scheduler (R4).
- **Not a grab-bag.** Image/compression formats, graph algorithms, application
  math, Win32/DirectX/COM declarations, regex, container types beyond the three
  maps and one heap, and a testing framework are explicitly out of scope.
- **Not a set of public PAL modules.** The private `std_<module>_pal.zig` units
  are implementation details and are never imported directly.

## How to import

Twelve core modules are re-exported through `@import("std")` — reach them as
`std.<name>`:

> `io`, `arena`, `str`, `mem`, `math`, `debug`, `net`, `async`, `bits`, `os`,
> `time`, `buf`

```zig
const std = @import("std");
std.io.write("hello\n");
```

Every other module is imported by path. The bare name resolves (the search path
appends `.zig`), and the sibling `.zig` form also works; the `.zig` form is the
canonical style used by the `stdlib_test/` usage programs:

```zig
const std_file = @import("std_file");        // resolves to std_file.zig
const std_crypto = @import("std_crypto.zig"); // equivalent, explicit
```

## Layer model (L0–L6)

The library is layered so dependencies only ever point downward. Imports are
strict: lower layers only, never siblings, never higher (R3).

| Layer | Meaning | Modules |
|---|---|---|
| Core | Builtin-backed console + descriptor I/O | `std.io` |
| **L0** | Foundation — no library imports; arena, raw memory, pure bit/integer math | `std.arena`, `std.mem`, `std.bits`, `std.math` |
| **L1** | Process, clocks, and diagnostics over the builtins and a per-OS PAL | `std.os`, `std.time`, `std.debug` |
| **L2** | Data layer built on L0 — string slices and growable buffers | `std.str`, `std.buf` |
| **L3** | Resources — owned-handle files, stdin, and sockets | `std_file`, `std_stdin`, `std.net` |
| **L4** | Collections — concrete maps, sort/search, a stable min-heap, RLE | `std_map`, `std_sort`, `std_heap`, `std_rle` |
| **L5** | Codecs — base64/hex, UTF-8, streaming hashes, number parse/format | `std_base64`, `std_hex`, `std_utf8`, `std_crypto`, `std_parse` |
| **L6** | Composition — coroutine-aware line and frame readers | `std_stream` |
| async runtime | Outside L0–L6 — the cooperative scheduler and child-frame pool | `std.async` |

## Rules (R1–R7)

These rules hold across the whole library. Each domain doc states the ones that
apply to its modules.

- **R1 — Arena.** Every allocating function takes `arena: *std.arena.Arena` as
  its first parameter and returns `error.OutOfMemory` (alone or inside the
  module's error set) when the caller-owned backing buffer is exhausted.
  Functions never own memory across calls, and memory is reclaimed only in bulk
  by `std.arena.reset` — there is no `free`. The caller keeps the backing buffer
  alive and aligned for as long as any pointer from the arena is used.
- **R2 — One error set per module.** Each module declares a single named error
  set at the top of its file. Translation between modules happens at the call
  site; there is no `catch unreachable` in the library.
- **R3 — Imports.** Import direction is strict — lower layers only, never
  siblings, never higher. All twelve core names are re-exported through
  `std.zig`; everything else is imported by path. Two sanctioned exceptions:
  `std_debug` (L1) imports `std_buf` (L2) and `std_io` for `backtrace` and
  logging, and `std_stdin` (L3) imports `std_file` (L3) to share the
  handle-based read path.
- **R4 — Coroutines (Model C).** A suspending operation comes in three flavors
  where meaningful — pure, `Sync`, and `Async` (the same signature plus an
  `Async` suffix, in the same module). The async form is a **separate
  implementation** that yields via the `@asyncSuspend` builtin; there is no
  executor and no poll loop, and no transitive coloring. The caller owns the
  scheduler and advances the world explicitly with `std.async.tick`.
- **R5 — Single-threaded.** No locking, no atomics, no concurrency.
- **R6 — Determinism.** No output may depend on addresses, the wall clock, or
  the process ID unless the module's contract says so. The `-fsafe` `0xAA`
  undefined-fill is not a contract.
- **R7 — Verification.** Every public function is covered by an automated
  regression check under `repro/mi_matrix/stdlib_<module>_<name>_xmod`; a module
  is complete when its checks pass and the dependency-graph check passes. Layer
  bands also ship composed usage programs under `stdlib_test/`.


## Which module for which job

| Job | Module | Domain doc |
|---|---|---|
| Console output and simple descriptor file I/O | `std.io` | [io.md](sf/docs/std_lib/io.md) |
| Open/read/write/seek files by owned handle; whole-file helpers | `std_file` | [io.md](sf/docs/std_lib/io.md) |
| Read lines or all of standard input | `std_stdin` | [io.md](sf/docs/std_lib/io.md) |
| Allocate scratch or owned memory | `std.arena` | [memory.md](sf/docs/std_lib/memory.md) |
| Raw byte/u32/u64 copy, zero, and equality | `std.mem` | [memory.md](sf/docs/std_lib/memory.md) |
| String search, compare, trim, split, join, replace | `std.str` | [text.md](sf/docs/std_lib/text.md) |
| Growable byte buffer with endian appends | `std.buf` | [text.md](sf/docs/std_lib/text.md) |
| Popcount, rotate, bit-reverse, bitfield extract/insert | `std.bits` | [bits_math.md](sf/docs/std_lib/bits_math.md) |
| Integer min/max/clamp/abs and power-of-two alignment | `std.math` | [bits_math.md](sf/docs/std_lib/bits_math.md) |
| Program arguments, environment, working directory, exit | `std.os` | [os_time.md](sf/docs/std_lib/os_time.md) |
| Monotonic/wall clocks and sleep | `std.time` | [os_time.md](sf/docs/std_lib/os_time.md) |
| Logging, assertions, panic, trap hook, core dump, backtrace | `std.debug` | [os_time.md](sf/docs/std_lib/os_time.md) |
| TCP/UDP sockets, `select`, non-blocking transfers | `std.net` | [net.md](sf/docs/std_lib/net.md) |
| Cooperative scheduler and child-frame pool | `std.async` | [async_stream.md](sf/docs/std_lib/async_stream.md) |
| Coroutine-aware line and length-prefixed frame readers | `std_stream` | [async_stream.md](sf/docs/std_lib/async_stream.md) |
| Hash maps (`u32→u32`, `u32→*void`, string→`*void`) | `std_map` | [collections.md](sf/docs/std_lib/collections.md) |
| In-place sort and `u32` binary search | `std_sort` | [collections.md](sf/docs/std_lib/collections.md) |
| Stable min-heap priority queue | `std_heap` | [collections.md](sf/docs/std_lib/collections.md) |
| Run-length encode/decode | `std_rle` | [collections.md](sf/docs/std_lib/collections.md) |
| Base64 encode/decode | `std_base64` | [codecs.md](sf/docs/std_lib/codecs.md) |
| Hex encode/decode | `std_hex` | [codecs.md](sf/docs/std_lib/codecs.md) |
| UTF-8 validate, decode, encode, count | `std_utf8` | [codecs.md](sf/docs/std_lib/codecs.md) |
| SHA-1, SHA-256, MD5, CRC-32 | `std_crypto` | [codecs.md](sf/docs/std_lib/codecs.md) |
| Parse/format integers and fixed-point `f64` | `std_parse` | [codecs.md](sf/docs/std_lib/codecs.md) |

## Worked example

A complete program that reads a file, sums its integer lines, and prints the
total plus a CRC-32 of the raw bytes. It composes six modules: `std.arena`
(ownership), `std_file` (resource), `std.str` (text), `std_parse` (format),
`std_crypto` (hash), and `std.io` (output). Illustrative, not compiled by a
gate.

```zig
const std = @import("std");
const std_file = @import("std_file");
const std_crypto = @import("std_crypto");
const std_parse = @import("std_parse");

var backing: [8192]u8 = undefined;

pub fn main() !void {
    // The arena wraps caller-owned storage; nothing here owns memory (R1).
    var arena = std.arena.init(backing[0..]);

    // Whole-file read into one arena allocation.
    const data = try std_file.readAll(&arena, "numbers.txt");

    // splitLines allocates the outer array; each segment aliases `data`.
    const lines = try std.str.splitLines(&arena, data);

    // Sum every line that parses as an i32; non-numbers are skipped.
    var total: i32 = 0;
    for (lines) |line| {
        if (std_parse.parseInt(line)) |n| {
            total += n;
        }
    }

    // Format into a caller-owned stack buffer and write it.
    var numbuf: [16]u8 = undefined;
    std.io.write(std_parse.itoa(numbuf[0..], total));
    std.io.writeByte('\n');

    // Fingerprint the raw input with CRC-32.
    const crc = std_crypto.crc32Final(
        std_crypto.crc32Update(std_crypto.crc32Init(), data),
    );
    var crcbuf: [16]u8 = undefined;
    std.io.write(std_parse.utoa(crcbuf[0..], crc));
    std.io.writeByte('\n');

    // Reclaim every allocation at once; there is no free.
    std.arena.reset(&arena);
}
```

## Domain docs

Every domain has a full doc with an overview, a quick start, and a structured
entry for each public function. Read the one for the job at hand:

- [memory.md](sf/docs/std_lib/memory.md) — `std.arena`, `std.mem`: the arena
  ownership model and raw memory operations.
- [text.md](sf/docs/std_lib/text.md) — `std.str`, `std.buf`: string slices and
  growable byte buffers.
- [bits_math.md](sf/docs/std_lib/bits_math.md) — `std.bits`, `std.math`: bit
  twiddling and integer math.
- [os_time.md](sf/docs/std_lib/os_time.md) — `std.os`, `std.time`,
  `std.debug`: process primitives, clocks, and diagnostics.
- [io.md](sf/docs/std_lib/io.md) — `std.io`, `std_file`, `std_stdin`: console,
  file, and stdin I/O.
- [net.md](sf/docs/std_lib/net.md) — `std.net`: TCP/UDP sockets and
  non-blocking primitives.
- [async_stream.md](sf/docs/std_lib/async_stream.md) — `std.async`,
  `std_stream`: the Model C scheduler and stream readers.
- [collections.md](sf/docs/std_lib/collections.md) — `std_map`, `std_sort`,
  `std_heap`, `std_rle`: maps, sort/search, heap, and RLE.
- [codecs.md](sf/docs/std_lib/codecs.md) — `std_base64`, `std_hex`,
  `std_utf8`, `std_crypto`, `std_parse`: encoders/decoders, hashes, and number
  parsing.

## Further reading

- [docs/reference/Language_Spec_Z98.md](docs/reference/Language_Spec_Z98.md) —
  the Z98 language specification.
- [sf/docs/tech_docs/12_async_coroutines.md](sf/docs/tech_docs/12_async_coroutines.md) —
  the compiler-side async/coroutine deep dive.
- [docs/sf/QUICK_REF.md](docs/sf/QUICK_REF.md) — the build / compile / gate
  command cheat sheet.
- `stdlib_test/` — runnable usage programs that compose the modules per layer
  band.
- `repro/mi_matrix/stdlib_*_xmod/` — the per-function regression checks (R7).
