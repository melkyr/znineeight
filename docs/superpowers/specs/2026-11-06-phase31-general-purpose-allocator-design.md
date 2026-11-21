# Phase 3.1 — General-Purpose Allocator design

**Status:** reconciled with the pre-implementation review, 2026-11-06. Operator ruling: fold-era
battery accounting — the `sf/src/std.zig` barrel change proceeds and the 8 dump-md5 pins and
marker counts are re-baselined once, per the fold-era procedure recorded below. This document
is the binding authority for the plan.
**Plan:** `docs/superpowers/plans/2026-11-06-phase31-general-purpose-allocator-plan.md`.

## Intent / why

The arena is the right default for scoped compiler and application work, but it cannot serve
non-nested lifetimes, object-granular reuse, or large individually freed objects. Phase 3.1
adds a general-purpose allocator to the standard library without migrating the compiler's
own memory architecture. The compiler migration remains Phase 3.5d; doing it now would raise
compiler memory and time before there is a demonstrated win.

The result must be a small, auditable, pure-Z98 allocator that works on the 32 MB Win9x target
and on Linux 2.2/2.4 through modern Linux, while keeping the compiler agnostic: `std.page` is
a library with a thin target PAL, not a compiler runtime feature.

## Source blueprint and claim evaluation

The blueprint is `examples/phase 3.1.txt`. Its useful architecture is kept; its Zig-specific
API claims and several numbers are not.

| Claim | Verdict | Consequence for this design |
|---|---|---|
| `extern fn` declarations and calls | PASS | PAL externs are allowed. |
| Function-pointer fields and indirect calls | PASS | `PageConfig.madvise_fn` and optional typed patterns are expressible. |
| Manual vtable with `*const VTable` | PARTIAL | Not used in 3.1. The blueprint's `Allocator` vtable is deferred; no `create(T)`. |
| `*void` | PASS | Use `*void`; `*anyopaque` is not supported. |
| `*anyopaque`, `@alignCast`, `Alignment` enum | FAIL | Use `*void`, numeric alignment (`usize`), manual pointer rounding. |
| Generics, `comptime`, `anytype`, `allocator.create(T)` | FAIL | Concrete byte API plus documented per-type helpers. |
| `allocator.free(buf)` method syntax | FAIL | Free functions with explicit `self`: `gpaFree(&gpa, ptr)`. |
| `-fsafe` automatically enables library checks | FAIL | `GpaConfig.safe_checks` is explicit; `-fsafe` does not auto-enable it. |
| Compile-time GCC `-fanalyzer`-style UAF/leak parity | FAIL for 3.1 | Only same-block GPA-aware ownership, UAF, double-free, and leak checks; no interprocedural/alias claims. |
| `std.heap.GPA` namespace | FAIL | `std_heap.zig` is the binary heap and is not re-exported. Use `std.gpa`. |
| Page reserve/commit/decommit through OS APIs | PASS | `VirtualAlloc`/`VirtualFree` are already Win9x-whitelisted; POSIX needs `mmap`/`mprotect`/`munmap` externs. |
| Compiler currently spills at a 16 MB threshold | STALE | Compiler uses a 256 MiB static pool, five arenas, unconditional `-s0` spills; latest self-compile is about 18.7 MB pool / 20.7 MB RSS. |
| GPA alone fixes compiler memory | NOT ACCEPTED | Compiler migration is out of 3.1; likely raises RSS/peak first. |
| 256 KB medium tier is safe on 32 MB | NOT ACCEPTED as default | Default medium cap is 64 KB; 256 KB is only for 256/512 MB profiles. |
| `madvise` is required for page release | NOT ACCEPTED | `munmap` + `mmap(MAP_FIXED)` is the portable baseline; `madvise` is an optional user callback. |
| Real Win9x `VirtualAlloc` behavior is proven by modern docs | NOT PROVEN | Modern Microsoft docs do not prove Win9x; cross-build/Wine is evidence only, never a real-hardware claim. |

## Goals

1. `std.page`: reserve/commit/decommit/release pages with explicit POSIX and Win32 PALs.
2. `std.gpa`: single-threaded GPA with:
   - TLSF small blocks below 4 KiB;
   - separate 4 KiB page-run free lists for 4 KiB through the profile's medium cap;
   - direct page mappings above the medium cap;
   - trim/decommit of empty medium runs and small regions when `safe_checks` is enabled.
3. `std.pool`: caller-backed fixed-block pool for real-time/typed use, independent of GPA.
4. Limited GPA-aware analyzer: recognize `gpaAlloc`/`gpaAllocZeroed`/`gpaFree`; same-block
   double-free, use-after-free, and leak diagnostics; no interprocedural/alias claims.
5. Compiler support only for a header-only `std_page_prelude.h`, emitted when `std.page` is
   reachable.
6. Seed, fixtures, docs, and Win9x/POSIX gates for all of the above, including the
   blueprint §5 `docs/reference/Language_Spec_Z98.md` updates (§2 non-nested lifetimes point
   to `std.gpa`; §7 "no malloc" wording re-scoped to arena-default + `std.gpa`/`std.pool`;
   §5 notes `safe_checks` is explicit).

## Non-goals

- Migrating `sf/src/allocator.zig`, `sf/src/main.zig`, compiler tiers, spill stores, or
  `type_db` to GPA.
- A Zig-compatible `std.mem.Allocator` vtable, `create(T)`, `anytype`, or generic containers.
- Thread-local heaps, TLS allocation, cross-thread free, or locking. Design notes only.
- `.encrypted` free-list metadata; `shuffle` is optional and non-security.
- C runtime/shim (`std_page_runtime.c`), `zig_runtime.c` changes, or new DLLs.
- Real Win9x hardware certification.
- Performance acceptance against the blueprint's cycle targets.
- Allocations with alignment stricter than 4096 (`allocAligned` beyond a page is deferred).

## Anti-goals

- Replacing the arena as the default model.
- Claiming `gpaFree` lowers the compiler's `pool.peak` (it does not; the monotonic compiler
  pool is untouched).
- Treating header magic, `0xDD` fill, `shuffle`, or `.encrypted` as security boundaries.
- Silent OOM, silent decommit failure, or silent double-free acceptance.
- Silently re-baselining a battery anchor that moved without the authorized attribution.

## Architecture

### Layer 1: `std.page`

`std.page` owns OS mappings. It does not own chunk lists; callers own the ranges they reserve.

```zig
pub const PosixMode = enum { auto, remap, protect, modern };

pub const PageConfig = struct {
    posix_mode: PosixMode,
    madvise_fn: ?fn (*void, usize, i32) i32,
};

pub const PageAllocator = struct {
    cfg: PageConfig,
    mode: u8,
};

pub const PageError = error{InvalidConfig};

pub fn pageInit(cfg: PageConfig) PageError!PageAllocator;
pub fn pageConfigDefault() PageConfig;
pub fn pageReserve(self: *PageAllocator, bytes: usize) ?[*]u8;
pub fn pageCommit(self: *PageAllocator, ptr: [*]u8, bytes: usize) bool;
pub fn pageDecommit(self: *PageAllocator, ptr: [*]u8, bytes: usize) bool;
pub fn pageRelease(self: *PageAllocator, ptr: [*]u8, bytes: usize) void;
```

Constants: `PAGE_SIZE = 4096`, `RESERVE_GRANULARITY = 65536`.

`pageConfigDefault()` returns `{ posix_mode = .auto, madvise_fn = null }`. `PageAllocator.mode`
is the resolved concrete mode after `auto` resolution (`native`, `remap`, `protect`, or
`modern`); it is fixed at init and read-only afterward.

Modes:

- `auto`: Win9x/Win32 native; POSIX uses `modern` if `madvise_fn != null`, else `remap`.
- `remap`: decommit by `munmap` then `mmap(MAP_FIXED|MAP_ANON|MAP_PRIVATE, PROT_NONE)`;
  commit by `mprotect(PROT_READ|PROT_WRITE)`. The address is stable.
- `protect`: decommit by `mprotect(PROT_NONE)`; commit by `mprotect(PROT_READ|PROT_WRITE)`.
  Access is revoked, but RSS/page return is not guaranteed.
- `modern`: decommit by `madvise(ptr, bytes, 4)` (`MADV_DONTNEED`); commit by `mprotect`.
  Requires the callback; `pageInit` returns `error.InvalidConfig` if it is null.
- Win9x/Win32: `VirtualAlloc(MEM_RESERVE/MEM_COMMIT)` and
  `VirtualFree(MEM_DECOMMIT/MEM_RELEASE)`; every `posix_mode` resolves to the native path.

Pinned contracts:

- `pageReserve` rounds to `RESERVE_GRANULARITY`; `pageCommit`/`pageDecommit` require
  page-aligned pointers and page-multiple lengths; a misaligned pointer or non-multiple length
  returns `false` (no silent rounding).
- `pageReserve(0)` returns `null`. `pageCommit`/`pageDecommit` with `bytes == 0` return
  `false`. `pageRelease(ptr, 0)` is a no-op.
- POSIX `mmap` reports failure as `MAP_FAILED` (`(void*)-1`), not NULL. `pageReserve` must
  convert it to `null` using the z9git rule: `@ptrToInt(raw) >= 0xFFFFF000 -> null`
  (`examples/z98/z9git/main.zig:55-56`, `sf/src/std_file.zig:89`). The `mmap` extern is
  declared returning `*void` (non-optional); the check lives in Z98 code.
- Win32 `VirtualAlloc` is likewise declared `*void` (non-optional) and `VirtualFree` takes
  `*void`; NULL becomes `null` via `@ptrToInt(raw) == 0` (z9git shape,
  `examples/z98/z9git/main.zig:31-32`). The `<windows.h>`/stdcall ABI rejects optional-pointer
  wrappers at the extern boundary.
- Win32 `MEM_RELEASE` requires `dwSize == 0`. `pageRelease(self, ptr, bytes)` on Win32 calls
  `VirtualFree(ptr, 0, MEM_RELEASE)` and **ignores** `bytes`; POSIX calls
  `munmap(ptr, roundUp(bytes, RESERVE_GRANULARITY))` so the whole reservation is released.
  The size asymmetry is part of the API contract; callers pass the same `bytes` they gave
  `pageReserve`.
- A failed remap/decommit returns `false`; the range is left unmapped and the caller must not
  assume the old contents survived.
- Double `pageRelease` of the same range is a caller bug (undefined), as with `munmap`; the
  GPA never releases a range twice.

### Layer 2: `std.gpa`

`Gpa` is single-threaded and deterministic unless `shuffle` is requested. It owns:

- small TLSF regions (64 KiB each);
- medium chunks (2 MiB default) with page metadata and page-run free lists;
- direct large mappings;
- statistics and optional safe-checks state.

```zig
pub const TargetProfile = enum { target32, target64, target128, target256, target512, modern };

pub const GpaConfig = struct {
    page: page_mod.PageConfig,
    target: TargetProfile,
    medium_max: usize,
    chunk_bytes: usize,
    safe_checks: bool,
    shuffle: bool,
    shuffle_seed: u32,
};

pub const GpaStats = struct {
    small_bytes: usize,
    medium_bytes: usize,
    large_bytes: usize,
    live_allocs: usize,
    chunks: usize,
    regions: usize,
};

pub fn gpaConfigDefault() GpaConfig;        // target64
pub fn gpaConfigTarget32() GpaConfig;       // 64 KB medium, 1 MiB chunk
pub fn gpaConfigTarget64() GpaConfig;       // 64 KB medium, 2 MiB chunk
pub fn gpaConfigTarget128() GpaConfig;      // 128 KB medium, 4 MiB chunk
pub fn gpaConfigTarget256() GpaConfig;      // 256 KB medium, 8 MiB chunk
pub fn gpaConfigTarget512() GpaConfig;      // 256 KB medium, 16 MiB chunk
pub fn gpaConfigTargetModern() GpaConfig;   // 1 MiB medium, 16 MiB chunk

pub fn gpaInit(cfg: GpaConfig) page_mod.PageError!Gpa;
pub fn gpaDeinit(g: *Gpa) void;
pub fn gpaAlloc(g: *Gpa, size: usize, align: usize) ?[*]u8;
pub fn gpaAllocZeroed(g: *Gpa, size: usize, align: usize) ?[*]u8;
pub fn gpaFree(g: *Gpa, ptr: [*]u8) bool;
pub fn gpaResize(g: *Gpa, ptr: [*]u8, new_size: usize, align: usize) ?[*]u8;
pub fn gpaStats(g: *Gpa) GpaStats;
```

#### Configuration contract

- `target` is the profile identity set by the constructors. `medium_max` and `chunk_bytes`
  are the authoritative fields: if a caller overwrites them after construction, the manual
  values win. The profile constructors set both consistently with the table above.
- `gpaInit` validates: `medium_max > 0`, `medium_max % PAGE_SIZE == 0`,
  `chunk_bytes % RESERVE_GRANULARITY == 0`, and `chunk_bytes > medium_max`; violation returns
  `error.InvalidConfig`. `posix_mode = .modern` with `madvise_fn = null` also returns
  `error.InvalidConfig`.
- `gpaConfigDefault()` = `gpaConfigTarget64()` with `page = pageConfigDefault()`,
  `safe_checks = false`, `shuffle = false`, `shuffle_seed = 0`.

#### Allocation contract

- `gpaAlloc` returns uninitialized memory and `null` on failure. `gpaAllocZeroed` is the only
  zeroing entry. `gpaFree` does not zero memory.
- Zero size: `gpaAlloc(g, 0, a)` and `gpaAllocZeroed(g, 0, a)` return `null`.
- Alignment: `align` must be a power of two in `[8, 4096]` (`PAGE_SIZE`); `align == 0`,
  non-power-of-two, `align < 8`, or `align > 4096` returns `null`. Pass 8 for natural
  alignment. Routing: `align == 8` uses normal size-based routing; `align > 8` routes to the
  medium tier (or large when `size > medium_max`) because a page-aligned run start satisfies
  every allowed `align`. A small request with `align > 8` therefore occupies a full page run;
  that waste is documented, not hidden. Stricter-than-page alignment is a deferred
  `allocAligned`.
- Overflow: every `size + header`/rounding computation uses a `u64` intermediate
  (`bytes64` guard pattern, `examples/z98/z9git/main.zig:47-50`); any result above
  `0xFFFFFFFF` returns `null`.
- `gpaFree` ownership: all tiers do a structural ownership lookup first (region/chunk/mapping
  range walk). An unowned pointer returns `false` in all modes and no metadata is touched.
  For an owned pointer the fast path frees and returns `true` with no further validation; a
  double free of an owned pointer in the fast path is a caller bug and can corrupt the free
  lists, exactly as with C `free()`. With `safe_checks = true`, header magic detects
  double-free/invalid and returns `false` without corrupting.
- `gpaResize(g, ptr, new_size, align)`: `new_size == 0` returns `null` and leaves the old
  block valid and unchanged (call `gpaFree` to release). On allocation failure the old
  pointer remains valid and unchanged. `align` follows the same validation; if the current
  block does not satisfy `align`, `gpaResize` allocates a new aligned block, copies
  `min(old, new)` bytes, and frees the old. An unowned `ptr` returns `null`.
- `gpaStats` always tracks `live_allocs` (cheap counter, independent of `safe_checks`);
  byte counters report **requested** live bytes per tier: small requested size is packed in
  the block header (bits 17..28), medium uses `used_bytes`, large uses the mapping header
  size. `chunks`/`regions` report current owners.
- `gpaDeinit` releases all regions/chunks/mappings.

#### Small tier: TLSF

- 64 KiB region, 4096-aligned; region header at offset 0; TLSF block area follows.
- TLSF metadata in the region header: `fl_bitmap: u32`, `sl_bitmap: [32]u32`,
  `free_heads: [192]?*Block`. The region tail is ~63 KiB, so the class map must cover the
  whole 64 KiB region, not just sub-4-KiB requests: first levels 4..15 are used
  (12 x 16 = 192 heads, sizes 16..65535). The `[512]` table is rejected (8-byte optional
  pointers cost 4.2 KiB per 64 KiB region); `[192]` fits the existing 2 KiB header reserve.
- Classic TLSF block: 4-byte header, 4-byte footer, free-list links in payload; minimum
  block 16 bytes; 8-byte alignment. Header layout: bit 0 `free`; bits 1..16 block size in
  bytes (16 bits, max 65535); bits 17..28 requested live bytes (12 bits, max 4095);
  bits 29..31 reserved. The footer is a **pure boundary tag**: bit 0 `free`; bits 1..16
  block size; upper bits zero. Requested bytes are allocator metadata in the header, never
  in the footer.
- Size mapping uses a bounded 32-iteration scan (no `@clz`): first-level floor log2,
  second-level next four bits. `sizeClass` covers 16..65535; it never clamps a 63 KiB
  region tail into a sub-4-KiB class.
- Alloc selects the best-fit class through `fl_bitmap`/`sl_bitmap` (bounded 32-bit word
  masks, no linear 192-head scan), then walks that class's free list for a block large
  enough. If the first class has no fitting block, advance via the bitmaps. Split when the
  remainder is at least the minimum block. Free coalesces with physical neighbors and
  inserts at the class head (or a shuffled position, see Determinism).
- Region identification for `gpaFree` is a **range walk over the region list** (the owning
  region is the one whose `[base, base+64 KiB)` contains the pointer). The block header
  carries no region pointer; the 4-byte header + 4-byte footer layout is fixed.

#### Medium tier: page runs

- 2 MiB default chunk, reserved with `pageReserve`; a small committed chunk header and
  page-metadata array live at the start; data pages are 4 KiB.
- Page metadata records state, run start, and run length. Free-run storage classes cover
  1, 2, 4, 8, 16, ... pages through `chunk_bytes / PAGE_SIZE`; allocation requests are
  capped at `medium_max / PAGE_SIZE`. Larger free runs are split to serve requests.
- Allocation takes the smallest fitting run, splitting larger free runs. Free coalesces
  adjacent free runs in the same chunk.
- Pages are committed on allocation. When `safe_checks` is true, a fully free run is
  decommitted; without safe checks it stays committed for reuse. If decommit fails, the run
  must **not** be returned to the free lists: mark it unavailable (or release the chunk when
  the whole chunk is free) and let allocation continue with other runs/chunks.
- `gpaFree` finds the owning chunk/page by address range; `gpaResize` keeps the run when the
  new size fits, otherwise allocates/copies/frees.

#### Large tier

- Sizes above `medium_max` reserve `size + header`, rounded to 64 KiB; commit the range; return
  page-aligned data.
- A large header before the data records size, class, and magic. Ownership is a range lookup
  over the live large-mapping list; `gpaFree` releases the whole mapping; resize reuses it
  when the new size fits.
- `align > 8` large requests still return page-aligned data (a page satisfies every allowed
  `align`).

#### Safe checks

When `safe_checks = true`:

- small blocks carry a 4-byte **magic suffix** immediately before the footer (safe mode
  only): live `0xDEADBEEF`, freed `0xFEEDFACE`. The safe block adds 4 bytes (block bytes
  `requested + 12` instead of `+ 8`); minimum block is 24 instead of 16. Pointer math stays
  `b = ptr - 4` in both modes. Before trusting the magic, safe mode validates
  `size % 8 == 0`, `size >= min_block`, and `b + size <= region_end`.
- medium uses page-metadata state; large uses its mapping-header magic;
- `0xDD` fill on free covers the requested payload only (inline byte loops; `std_mem` is
  unchanged), never the magic, links, or footer;
- double-free detected (`gpaFree` returns `false`);
- `live_allocs` tracked in `GpaStats` (always tracked; safe checks add validation, not the
  counter);
- empty medium runs decommitted, empty small regions released/decommitted.

The checks are not a substitute for `-fsafe`; `-fsafe` alone does not enable them. There is
no dereference-UAF runtime check in the library.

### Layer 3: `std.pool`

Caller-provided fixed buffer; no GPA dependency.

```zig
pub const Pool = struct { /* buffer, block size, block count, free list, used */ };
pub fn poolInit(buf: []u8, block_size: usize, align: usize) ?Pool;
pub fn poolAlloc(p: *Pool) ?[*]u8;
pub fn poolFree(p: *Pool, ptr: [*]u8) bool;
pub fn poolReset(p: *Pool) void;
pub fn poolLen(p: *Pool) usize;
```

`poolInit` contracts: `block_size == 0` returns `null`; `align` must be a power of two in
`[8, 4096]`, otherwise `null`. Block size is rounded up to alignment and must be at least one
pointer wide; a buffer smaller than one rounded block returns `null`.
Allocation is O(1) from the free list; exhaustion returns `null`; `reset` returns every block
to the free list. `poolFree` validates range/alignment structurally and returns `false` for
foreign or misaligned pointers (pool validation is always on).

## Compiler-agnostic boundary

The compiler only needs to copy `sf/src/include/std_page_prelude.h` into the output directory
when `std.page` is reachable, exactly like `net_prelude.h`, `std_os_prelude.h`, and
`std_time_prelude.h`. The prelude contains only OS prototypes/constants; there is no page
runtime in C, no new ABI, and no `zig_runtime.c` change. An alternate backend can replace the
prelude/externs without reimplementing a C allocator.

Pinned prelude rules:

- `std_page.zig` carries `@cInclude("<std_page_prelude.h>")`; `c89_emit.zig` scans reachable
  modules for that string to gate emission (`scriptStdPageEmitted`, same pattern as
  `scriptStdOsEmitted`/`scriptStdTimeEmitted`). Reachability is the D3 value-ref closure
  (`sf/src/main.zig:1711-1733`): stdio-only programs omit the prelude; a program that
  value-references `std.page`/`std.gpa` gets it.
- Feature-test macros `#ifndef _POSIX_C_SOURCE / #define _POSIX_C_SOURCE 199309L` and
  `_DEFAULT_SOURCE` come **before** `<sys/mman.h>`/`<unistd.h>` (pattern:
  `sf/src/include/std_time_prelude.h:17-27`). Under `-std=c89`, `__STRICT_ANSI__` otherwise
  hides the POSIX prototypes and `c89_emit.zig:2247` emits no fallback externs for
  `@cInclude` modules.
- The prelude must **not** define `_FILE_OFFSET_BITS`; the `mmap` extern uses `off: i32`
  targeting 32-bit `off_t`. LFS toolchains that force `_FILE_OFFSET_BITS=64` need `mmap64`;
  that is out of scope and must fail loudly, not silently.
- `std_page.zig`/`std_gpa.zig` must not import `std_os`/`std_time`, keeping the closure's
  `@cInclude` set to `{std_page_prelude.h}` so the macros are first-in-TU.
- A page-reachable program is added to `scripts/compiler/gate_warn_clean.sh` scope so the
  prelude path is compiled warning-clean under `-std=c89 -pedantic -Wall -Werror`.
- `scripts/win32_cross/check_win9x_imports.sh` needs **no change**: `VirtualAlloc`/
  `VirtualFree` are already whitelisted (`:26`).

## Portability matrix

| Surface | Linux 2.2/2.4+ | Modern Linux | Win9x / Win32 |
|---|---|---|---|
| Reserve | `mmap(PROT_NONE, MAP_PRIVATE\|MAP_ANON)` | same | `VirtualAlloc(MEM_RESERVE)` |
| Commit | `mprotect(RW)` | same | `VirtualAlloc(MEM_COMMIT)` |
| Decommit | `munmap` + `mmap(MAP_FIXED, PROT_NONE)` | same; optional `madvise(MADV_DONTNEED)` | `VirtualFree(MEM_DECOMMIT)` |
| Release | `munmap(ptr, roundUp(bytes, RESERVE_GRANULARITY))` | same | `VirtualFree(ptr, 0, MEM_RELEASE)` — size **must** be 0 |
| Failure sentinel | `MAP_FAILED = (void*)-1` → convert to `null` | same | NULL return |
| Granularity | 4 KiB pages; reserve rounded to 64 KiB | same | 4 KiB pages; 64 KiB reserve alignment |
| Header | `<sys/mman.h>`, `<unistd.h>` | same | `<windows.h>` |

Linux 2.2/2.4 uses the same core APIs; the `MAP_ANON` constant is `0x20` on Linux and is kept
as a Z98-side constant. `madvise` is not assumed; it is an optional callback. Other POSIX
systems may have different constants; this plan targets Linux, with Win9x/Win32 as the second
target.

## Determinism and resource behavior

- Default GPA allocation order is deterministic for the same call sequence and config.
- `shuffle: bool` (not an enum) plus `shuffle_seed: u32`: when `shuffle = true`, free-list
  insertion order is permuted deterministically by a 32-bit LCG
  (`state = state * 1103515245 + 12345`, mod 2^32). Scope: TLSF class free lists and medium
  run free lists (large mappings have no free list). When `shuffle = false` insertion is at
  the class/run head (unshuffled baseline). `shuffle` is not a security feature and is off by
  default. `.encrypted` is not implemented in 3.1.
- The GPA is single-threaded. Per-thread heaps and Win9x `TlsAlloc`/`TlsGetValue` are design
  notes for a later phase; no thread API is added.
- Address space is 32-bit; large objects and chunks are bounded by the profile/address space,
  not by a hidden 64-bit assumption. All size arithmetic guards u32 overflow (u64
  intermediates).

## Security and safety

- The GPA does not provide secrecy. Freed memory is not zeroed. `gpaAllocZeroed` is explicit.
- Header magic and `0xDD` fill detect some allocator misuse; they do not make use-after-free
  safe.
- `shuffle`/`.encrypted` are not security boundaries; `.encrypted` is deferred.
- The analyzer is limited to same-block GPA ownership; alias and interprocedural cases are
  documented limitations, not claimed coverage.
- Win9x real-hardware behavior remains unverified; only cross-build/Wine evidence is allowed.

## Analyzer contract

- Recognized call shapes: bare calls (`gpaAlloc(g, n, a)`) and module-qualified member calls
  (`gpa.gpaAlloc(&g, n, a)`), matched on the callee's final identifier name. The existing
  `isAllocCall`/`isFreeCall` matchers (`sf/src/analyzer.zig:222-256`) only accept bare
  `ident_expr` callees and must be extended.
- `ERR_2006_USE_AFTER_FREE` is added as an **explicit-value enum tail member**
  (`= 3079`; 3078 is the last used value). It is never inserted beside `ERR_2005_DOUBLE_FREE`
  — that member is bare auto-increment with real value 3035, and a mid-enum insertion shifts
  every later code (including the explicit 3045) into duplicate-tag `ERR_3055`.
- Same-block only: free followed by dereference/index/field use of the same identifier; a
  bare pointer copy is not a use. Leak warning `WARN_6005_MEMORY_LEAK` for an allocation not
  freed in the same straight-line block.
- No interprocedural, alias, or branch-merge claims. Diagnostic registration is required in
  `docs/sf/manuals/en/vol4-21-diagnostics.html`,
  `docs/sf/manuals/dist/en/vol4-21-diagnostics.html`, and
  `sf/docs/tech_docs/06_static_analyzers.md`.

## Test strategy

- New std fixtures under `repro/mi_matrix/stdlib_*_xmod`, pinned in
  `scripts/stdlib/expected_dirs.txt` (each task pins its own dirs when it creates them; Task 8
  verifies the final nine-dir set), run through `verify_stdlib.sh` under `-ffast` and
  through `scripts/stdlib/run_gpa_safe.sh` (a clone of `run_crypto_safe.sh`, default-mode
  `-fsafe`) — `scripts/stdlib/run_fixtures.sh` hardcodes `-ffast` and has no mode knob, so a
  dedicated safe runner is mandatory before the first `-fsafe` claim.
- `stdlib_page_xmod`: reserve/commit/decommit/recommit/release, `auto` and `protect`,
  `MAP_FAILED`/null contracts, zero-size contracts, misaligned commit rejection.
- `stdlib_page_modern_xmod`: a real `madvise` extern wrapped in a Z98 shim callback;
  `modern` mode and `auto` with the callback set; the address stays stable and the
  recommitted range reads as fresh/zeroed (old bytes are not expected to survive
  `MADV_DONTNEED`/Win32 decommit). Linux-only; excluded from Win9x cross-build.
- `stdlib_gpa_small_xmod`: TLSF sizes, coalescing, 8-byte alignment, resize, align rejection
  (`0`, `3`, `7`, `8192` -> `null`), the temporary Task 2 `size == 4096` -> `null` boundary
  (replaced by a medium-success/page-aligned assertion when Task 3 lands), bitmap class
  selection across multiple classes, upper-class (region-tail) allocation, odd requested-size
  coalescing (free a neighbor while an odd block is live), and requested-byte stats.
- `stdlib_gpa_medium_xmod`: page-run split/coalesce, mixed free order, 1000-op stress,
  `align > 8` small-size routing (16/4096 alignment honored via the medium tier).
- `stdlib_gpa_large_xmod`: direct mappings, page alignment, zeroed allocation,
  `align > 4096` -> `null`, `gpaStats` field assertions after known workloads.
- `stdlib_gpa_resize_xmod`: grow/shrink small/medium/large, content survival, align-change
  resize, and a deterministic resize-failure recipe: shrink/guard target
  `new_size = 0xFFFFFFF0` hits the u64 overflow guard -> `null`, old pointer valid.
- `stdlib_gpa_safe_xmod`: double-free `false`, live count, safe decommit, `0xDD` fill; the
  small-tier magic suffix (live/freed), safe-mode coalescing/split/resize, a corrupt-magic
  free returning `false`, and the fast-mode no-check throwaway case; the
  fast-path tolerant double-free check runs **last** (or on a throwaway `Gpa`) because it
  corrupts the free list.
- `stdlib_gpa_shuffle_xmod`: same `shuffle_seed` reproduces identical reuse order; `shuffle
  = false` matches the unshuffled baseline; no security claim.
- `stdlib_pool_xmod`: fixed pool exhaustion/reuse/reset, foreign/misaligned free rejection.
- Analyzer fixtures: `gpa_double_free.zig`, `gpa_use_after_free.zig`, `gpa_leak.zig`, and an
  alias negative case.
- `check_emit_support.sh`: `std_page_prelude.h` present iff `std.page` is value-reachable;
  emitted bytes equal the canonical header.
- Win9x: `cross_build_run.sh` + `check_win9x_imports.sh 9x` for `stdlib_page_xmod`,
  `stdlib_gpa_small_xmod`, and `stdlib_pool_xmod`; Wine run only if available.
- Seed: two-hop closure from `release/seed/zig1-seed.tgz`; v142 rotation plus the v143 post-fix rotation; lib count 56.

## Battery anchors (fold-era accounting)

The `sf/src/std.zig` barrel re-export of `page`/`gpa`/`pool` moves two of five anchors, by the
same mechanism as the `std_fold` barrel addition (`a3abb204`, `docs/sf/QUICK_REF.md:752-760`).
Operator ruling 2026-11-06: proceed and re-baseline under the fold-era procedure.

| Anchor | Moves? | Handling |
|---|---|---|
| 8 dump-md5 pins (4 programs x 2 modes, `gate_lower_depth.sh` case 5) | YES — all 8 | Verified-delta, then re-record once in `scripts/compiler/gate_lower_depth.sh` + `docs/sf/QUICK_REF.md` (old table demoted to Historical) |
| Markers (`--markers` stream, 3397 lines / 39012 bytes) | YES | Re-record with cause attribution (ruling-A format) |
| Goldens 5/5 (runtime stdout md5s) | NO | Re-prove byte-identical; any change = STOP |
| frozen-1124 classification md5 `518eca1a…` | NO | 0 movers required; any mover = STOP |
| Live corpus class md5 `a2dd8b02…` (1256 dirs) | YES, additive only | Must grow exactly by the 9 new fixture dirs (1256 -> 1265); any other mover = STOP |
| Seed fixed point | See note | The std payload alone never moves it; the compiler-source changes in Tasks 1/7 (prelude emission, diagnostics, analyzer) legitimately move it. Record the new value with that attribution. If a std-only delta moves it: STOP. |

Verified-delta procedure (fold-era, operator ruling 2026-10-28, extended 2026-11-06):

1. Compiler-only delta must be empty: dump the 4 pin programs with the pre-3.1 seed compiler
   and with the new compiler against the **same** (pre-3.1) `lib/` tree; the dumps must be
   byte-identical. Non-empty: STOP (an unauthorized compiler emission change).
2. Std-only delta: same new `zig1` binary with the pre-3.1 `lib/` vs the new `lib/`; the diff
   must be exactly type-identifier intern ripple and, where modules are emitted, the new
   `std_page`/`std_gpa`/`std_pool` C plus module-list entries. Any other logic delta: STOP.
3. Goldens re-proven byte-identical; frozen-1124 unchanged; live growth exactly the new
   fixture dirs.
4. Re-record the 8 pins **once** (hand-recorded; no script regenerates pin values) and the
   markers with cause attribution; run `gate_lower_depth.sh` green afterward.

## Risks

1. **TLSF boundary bugs** — incorrect size mapping, footer corruption, or coalescing can
   silently corrupt memory. Mitigate with small/medium stress fixtures and safe checks.
2. **Medium run metadata** — split/coalesce errors or stale page metadata cause double
   allocation. Mitigate with mixed-order free and stress tests.
3. **POSIX remap failure** — `MAP_FIXED` can fail; decommit cannot promise re-commit. The API
   returns `false`; callers must treat the range as unavailable.
4. **Win9x API behavior** — modern docs do not prove 9x; cross-build/Wine only. No real
   hardware claim.
5. **Analyzer false confidence** — same-block only; alias/interprocedural cases are missed.
   Document and test the negative case.
6. **Seed drift** — new std modules and compiler prelude emission change the seed; rotate and
   verify two-hop closure; attribute the fixed-point movement to the compiler-source change.
7. **Battery-anchor drift** — pins/markers may move only with the authorized barrel
   attribution; goldens/frozen may not move at all. Any unexplained mover is a STOP, never a
   silent re-record.

## Rulings

- Compiler memory migration is out of 3.1; it remains 3.5d.
- No C page runtime; header-only prelude with feature-test macros first-in-TU.
- `std.gpa`, not `std.heap`.
- Concrete byte API plus typed helpers; no vtable/`create(T)`.
- TLSF small tier with region range-walk identification; separate medium page runs; 64 KB
  default medium cap.
- `free_heads: [192]?*Block` (FL 4..15 x 16 SL), so the region tail has a real class; the
  `[512]` table was rejected (8 B/entry optional pointers make a 4.2 KiB header per 64 KiB
  region). Class selection is bitmap-driven; the linear head scan is not the approved
  algorithm.
- Small-block metadata is packed in the 4-byte header (free/size/requested); the footer is a
  pure `free|size` boundary tag. This is the root fix for the allocated-footer corruption
  class; requested bytes never alias the boundary tag.
- Safe mode uses a 4-byte magic suffix before the footer (fast mode has none); safe blocks
  cost 4 extra bytes and min block 24, but pointer math and the footer tag are unchanged.
- Default profile 64 MB; 32/128/256/512/modern are explicit.
- Explicit `safe_checks`; `-fsafe` does not auto-enable.
- `gpaFree` returns `false` for unowned pointers in all modes (structural lookup); double-free
  detection is `safe_checks`-only; the fast path tolerates double free (caller bug, last-op
  fixture rule).
- `align` must be a power of two in `[8, 4096]`; stricter alignment is deferred.
- `gpaResize(ptr, 0, a)` returns `null` and leaves the old block valid.
- `gpaStats.live_allocs` is always tracked.
- `shuffle: bool` + LCG seed; the `.none/.shuffle` enum prose was dropped to match the API.
- `ERR_2006_USE_AFTER_FREE = 3079` explicit at the diagnostics enum tail.
- `std.pool` is caller-buffer backed; pool validation is always on.
- Analyzer limited to same-block GPA ownership, bare and qualified call shapes.
- Fold-era battery accounting: barrel change proceeds; 8 pins + markers re-baselined once
  with verified-delta; goldens/frozen immutable; live growth exactly +9 fixture dirs; seed
  fixed-point movement attributed to compiler-source changes only.
- `docs/reference/Language_Spec_Z98.md` is updated in 3.1 (blueprint §5: §2, §5, §7).
- TLS design-only; `.encrypted` deferred.
- No performance/cycle-target claims.

## Deferred / future

- `.encrypted` metadata and a threat model.
- Per-thread heaps/TLS (`TlsAlloc`/`TlsGetValue`) and cross-thread free.
- Allocator vtable and `create(T)`-style typed helpers at the language level.
- `allocAligned` beyond 4096-byte alignment.
- Compiler migration to GPA (3.5d).
- Real Win9x hardware/paging-file testing.
- Full interprocedural/alias UAF analyzer.
- `mmap64`/`_FILE_OFFSET_BITS=64` LFS support.
