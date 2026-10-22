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

## Shipped seed

The committed seed is **v115** (`release/seed/zig1-seed.tgz`, archive md5
`484ae9797545591e113f002e595a26d2`), with **44** std files (`std.zig` +
43 `std_*.zig`) and `lib/manifest.md5` md5
`576cffb600863a648f518748edad81c6`. The compiler fixed point is
`45158dcede81125a39a2c2c58478e21e` (`F_new`, unchanged since v112); v115 is
the M3 X.509/trust-store payload rotation (adds `std_asn1.zig` and
`std_x509.zig`; no compiler movement).

## Layer model (L0–L6)  [updated: 2026-10-22 — M3]

The library is layered so dependencies only ever point downward. Imports are
strict: lower layers only, never siblings, never higher (R3).

| Layer | Meaning | Modules |
|---|---|---|
| Core | Builtin-backed console + descriptor I/O | `std.io` |
| **L0** | Foundation — no library imports; arena, raw memory, pure bit/integer math | `std.arena`, `std.mem`, `std.bits`, `std.math` |
| **L1** | Process, clocks, and diagnostics over the builtins and a per-OS PAL | `std.os`, `std.time`, `std.debug` |
| **L2** | Data layer built on L0 — string slices and growable buffers | `std.str`, `std.buf` |
| **L3** | Resources — owned-handle files, stdin, and sockets | `std_file`, `std_stdin`, `std.net` |
| **L4** | Collections and byte codecs — concrete maps, sort/search, a stable min-heap, RLE, LZ4 block and zstd frame decode | `std_map`, `std_sort`, `std_heap`, `std_rle`, `std_lz4`, `std_zstd` |
| **L5** | Codecs, cryptography, numerics, and search — base64/hex, UTF-8, streaming hashes/PRFs/HKDF/BLAKE2s, RSA verify, symmetric ciphers, elliptic curves, DER/X.509 parsing and chain verification, number parse/format, explicit adaptive ODE integration, grid pathfinding, hierarchical HPA\* pathfinding, position-based physics | `std_base64`, `std_hex`, `std_utf8`, `std_crypto`, `std_cipher`, `std_ecc`, `std_asn1`, `std_x509`, `std_parse`, `std_num`, `std_pathfind`, `std_hpa`, `std_physics` |
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


## Which module for which job  [updated: 2026-10-22 — M3]

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
| PCG32 / xoshiro256\*\* pseudorandom generators | `std_rand` | [rand.md](sf/docs/std_lib/rand.md) |
| OpenSimplex 2D/3D noise and fBm | `std_noise` | [noise.md](sf/docs/std_lib/noise.md) |
| LZ4 raw block decode | `std_lz4` | [codecs.md](sf/docs/std_lib/codecs.md) |
| Zstd frame decode | `std_zstd` | [zstd.md](sf/docs/std_lib/zstd.md) |
| Adaptive ODE integration (explicit Dormand–Prince RK45) | `std_num` | [num.md](sf/docs/std_lib/num.md) |
| Grid pathfinding (JPS, preprocessed JPS+) | `std_pathfind` | [pathfind.md](sf/docs/std_lib/pathfind.md) |
| Hierarchical pathfinding (HPA\*, exact transition tiles) | `std_hpa` | [hpa.md](sf/docs/std_lib/hpa.md) |
| Position-Based Dynamics (Verlet + distance constraints) | `std_physics` | [physics.md](sf/docs/std_lib/physics.md) |
| Base64 encode/decode | `std_base64` | [codecs.md](sf/docs/std_lib/codecs.md) |
| Hex encode/decode | `std_hex` | [codecs.md](sf/docs/std_lib/codecs.md) |
| UTF-8 validate, decode, encode, count | `std_utf8` | [codecs.md](sf/docs/std_lib/codecs.md) |
| SHA-1/256/384/512, MD5, CRC-32, HMAC, HKDF, BLAKE2s | `std_crypto` | [crypto.md](sf/docs/std_lib/crypto.md) |
| RSA PKCS#1 v1.5 / PSS signature verify | `std_crypto` | [crypto.md](sf/docs/std_lib/crypto.md) |
| ChaCha20, Poly1305, ChaCha20-Poly1305 AEAD | `std_cipher` | [cipher.md](sf/docs/std_lib/cipher.md) |
| AES-128 block and AES-128-GCM AEAD | `std_cipher` | [cipher.md](sf/docs/std_lib/cipher.md) |
| X25519 key agreement | `std_ecc` | [ecc.md](sf/docs/std_lib/ecc.md) |
| P-256 keygen / ECDH / ECDSA verify; P-384 ECDSA verify | `std_ecc` | [ecc.md](sf/docs/std_lib/ecc.md) |
| DER TLV read/scan (streaming, no allocation) | `std_asn1` | [asn1.md](sf/docs/std_lib/asn1.md) |
| X.509 certificate parse, chain verify, hostname match, trust store | `std_x509` | [x509.md](sf/docs/std_lib/x509.md) |
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

## Domain docs  [updated: 2026-10-22 — M3]

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
- [rand.md](sf/docs/std_lib/rand.md) — `std_rand`: PCG32 and xoshiro256\*\*
  deterministic pseudorandom generators.
- [noise.md](sf/docs/std_lib/noise.md) — `std_noise`: 2014 OpenSimplex 2D/3D
  noise and fBm.
- [crypto.md](sf/docs/std_lib/crypto.md) — `std_crypto`: SHA-1/256/384/512,
  MD5, CRC-32, HMAC-SHA256, HKDF, BLAKE2s/HMAC-BLAKE2s, RC4, modexp, and RSA
  PKCS#1 v1.5 / PSS verify.
- [cipher.md](sf/docs/std_lib/cipher.md) — `std_cipher`: ChaCha20, Poly1305,
  ChaCha20-Poly1305 AEAD, AES-128, and AES-128-GCM (const T-tables, GHASH).
- [ecc.md](sf/docs/std_lib/ecc.md) — `std_ecc`: X25519, P-256
  keygen/ECDH/ECDSA verify, and P-384 ECDSA verify.
- [asn1.md](sf/docs/std_lib/asn1.md) — `std_asn1`: streaming DER TLV reader
  with definite-length and minimal-encoding validation.
- [x509.md](sf/docs/std_lib/x509.md) — `std_x509`: certificate parsing,
  browser-grade leaf-to-anchor chain verification, SAN dNSName hostname
  matching, and the pinned §5.5 trust-store loader.
- [codecs.md](sf/docs/std_lib/codecs.md) — `std_base64`, `std_hex`,
  `std_utf8`, `std_parse`, `std_lz4`: encoders/decoders, number parsing, and
  raw LZ4 block decode (legacy `std_crypto` primitives are indexed in
  [crypto.md](sf/docs/std_lib/crypto.md)).
- [zstd.md](sf/docs/std_lib/zstd.md) — `std_zstd`: single-shot zstd frame
  decode with a caller-overridable window cap.
- [num.md](sf/docs/std_lib/num.md) — `std_num`: explicit adaptive
  Dormand–Prince RK45 with a caller-supplied state vector and derivative
  callback.
- [pathfind.md](sf/docs/std_lib/pathfind.md) — `std_pathfind`: JPS on dynamic
  8-connected grids and preprocessed JPS+ on static grids, with the cardinal
  10 / diagonal 14 no-corner-cut movement model.
- [hpa.md](sf/docs/std_lib/hpa.md) — `std_hpa`: exact-cost HPA\* on static
  grids, with clipped clusters, transition tiles, and cluster-local JPS
  refinement.
- [physics.md](sf/docs/std_lib/physics.md) — `std_physics`: Position-Based
  Dynamics (Verlet integration plus iterative distance projection) for cloth,
  soft bodies, and ropes.

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
