# Phase 3.1 General-Purpose Allocator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pure-Z98 page allocator, a single-threaded TLSF/page-run GPA, a fixed-block pool, and limited GPA-aware analyzer checks, without migrating the compiler allocator.

**Architecture:** `std.page` owns OS reserve/commit/decommit/release; `std.gpa` owns TLSF small blocks, page-run medium blocks, and direct large mappings; `std.pool` owns caller-backed fixed-block pools. The compiler only copies a header-only page prelude when `std.page` is reachable. No C allocator runtime and no compiler arena migration.

**Tech Stack:** Z98 compiled to C89, POSIX `mmap`/`mprotect`/`munmap`, Win32 `VirtualAlloc`/`VirtualFree`, existing std fixture and seed tooling.

**Spec:** `docs/superpowers/specs/2026-11-06-phase31-general-purpose-allocator-design.md`

## Global Constraints

- Pure Z98 in `sf/src/*.zig`; no `@cImport`, `asm`, intrinsics, C macros, or C helper runtime.
- No changes to `sf/src/allocator.zig`, `sf/src/main.zig`, `zig_runtime.c`, `zig_pal.c`, or compiler spilling.
- The only new compiler support is `sf/src/include/std_page_prelude.h`, a header-only prelude emitted conditionally when `std.page` is reachable. `std_page.zig` carries `@cInclude("<std_page_prelude.h>")`; `std_page.zig`/`std_gpa.zig` must not import `std_os`/`std_time` (keeps the `@cInclude` set first-in-TU).
- Prelude rules: `_POSIX_C_SOURCE 199309L` + `_DEFAULT_SOURCE` defined **before** `<sys/mman.h>`/`<unistd.h>` (pattern `sf/src/include/std_time_prelude.h:17-27`); the prelude must **not** define `_FILE_OFFSET_BITS` (`off: i32` targets 32-bit `off_t`; LFS `mmap64` is out of scope).
- 32-bit only: `usize = u32`; `PAGE_SIZE = 4096`; `RESERVE_GRANULARITY = 65536`. All `size + header`/rounding math uses `u64` intermediates (`bytes64` guard pattern, `examples/z98/z9git/main.zig:47-50`); any result above `0xFFFFFFFF` fails the call.
- Default GPA profile is **64 MB**: 64 KB medium cap, 2 MiB chunks. 32/128/256/512/modern are explicit profiles.
- Win9x target is no-CRT/kernel32-only; `VirtualAlloc`/`VirtualFree` are already whitelisted — `scripts/win32_cross/check_win9x_imports.sh` needs **no change**. Real 32 MB hardware is unavailable; Wine/cross-build is evidence only.
- POSIX target is Linux 2.2/2.4 through modern Linux. Core path uses `mmap`/`mprotect`/`munmap`; `madvise` is optional, never required. POSIX `mmap` failure is `MAP_FAILED` (`(void*)-1`), never NULL — convert via `@ptrToInt(raw) >= 0xFFFFF000 -> null` (z9git rule).
- No `std.heap` alias. Names are `std.page`, `std.gpa`, `std.pool`.
- No thread implementation. Per-thread/TLS design is documentation only.
- Randomness: `shuffle: bool` default `false`; when set, free-list insertion order is permuted deterministically by a 32-bit LCG (`state = state * 1103515245 + 12345`) seeded from `shuffle_seed`; `.encrypted` not implemented.
- `GpaConfig.safe_checks` is explicit and default `false`; `-fsafe` does not automatically enable GPA checks.
- `gpaAlloc` returns uninitialized memory; `gpaAllocZeroed` is explicit; `gpaFree` does not zero. No secret-zeroization claim.
- `scripts/stdlib/run_fixtures.sh` is `-ffast`-only (hardcoded); every `-fsafe` fixture claim runs through `scripts/stdlib/run_gpa_safe.sh` (clone of `run_crypto_safe.sh`). No script regenerates battery pin values; pins are hand-recorded once (see Task 8).
- Test compiler: `<seed-zig1>` is the fixed-path compiler at `<workspace>/zig1/zig1_5_clean`, built once in Task 1 after the Task 1 compiler changes and reused by all later tasks. Refresh its sibling `lib/` after each std-source edit by copying the changed `sf/src/std*.zig` files — no compiler rebuild. Rebuild into the same path only when compiler source changes: the Task 1 initial build and the Task 7 rebuild (diagnostics/analyzer). Task 8's v142 seed rotation still runs `build_from_seed.sh` normally.
- Battery anchors follow fold-era accounting (operator ruling 2026-11-06): the `sf/src/std.zig` barrel change proceeds; the 8 dump-md5 pins and markers are re-baselined **once** in Task 8; goldens and frozen-1124 must not move at all; live corpus grows exactly by the 9 new fixture dirs.
- No performance/cycle-target acceptance. Validate correctness, bounds, portability, and deterministic behavior only.
- Source edits use `edit`/`fastedit`; no bulk source transforms. Commits are explicit-path; no push.

## Target Profiles

| Profile | Medium cap | Chunk | Use |
|---|---:|---:|---|
| target32 | 64 KB | 1 MiB | minimum Win9x |
| target64 | 64 KB | 2 MiB | default Win98 |
| target128 | 128 KB | 4 MiB | WinME-class |
| target256 | 256 KB | 8 MiB | 256 MB |
| target512 | 256 KB | 16 MiB | 512 MB |
| modern | 1 MiB | 16 MiB | modern *nix |

## Review Focus

1. **Win9x reserve/commit/decommit/release**: wrong 64 KB alignment, partial commit, decommit failure, or release of a partially committed range. `pageRelease` must call `VirtualFree(ptr, 0, MEM_RELEASE)` — Win32 release size **must** be 0 and `bytes` is ignored there.
2. **POSIX failure sentinels**: `MAP_FAILED = (void*)-1` must become `null` (`@ptrToInt >= 0xFFFFF000`), never a wrapped "valid" optional; `mmap(MAP_FIXED)`/`mprotect` failure leaves the range unusable; address stability across decommit/commit; 2.2/2.4 constant drift.
3. **TLSF boundaries**: minimum block, 4-byte header/footer, size-class mapping, split remainder, coalescing, stale free-list links; class selection must use `fl_bitmap`/`sl_bitmap` (O(1) word masks), the class map must cover 16..65535 (FL 4..15) including the ~63 KiB region tail, and region identification is a **range walk over the region list** — the block header carries no region pointer.
4. **Medium page runs**: split/coalesce correctness, page metadata ownership, double allocation, decommit of a live run, stale pointers after resize.
5. **Analyzer honesty**: alias/interprocedural UAF and leak cases are not covered; false positives on pointer copies must not appear; idiomatic qualified calls (`gpa.gpaAlloc(...)`) must be recognized.
6. **Battery anchors**: pins/markers may move only with the authorized barrel attribution; goldens/frozen-1124 may not move at all; live growth is exactly 9 fixture dirs; any unexplained mover is a STOP, never a silent re-record.
7. **Prelude/seed scope**: page prelude present only when `std.page` is reachable; stdio-only programs omit it; seed lib count moves from 52 to 56, not further.

---

## Task 1: Page Prelude, PAL, and `std.page`

**Files:**
- Create: `sf/src/include/std_page_prelude.h`
- Create: `sf/src/std_page_pal.zig`
- Create: `sf/src/std_page.zig`
- Create: `scripts/stdlib/run_gpa_safe.sh`
- Create: `repro/mi_matrix/stdlib_page_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `repro/mi_matrix/stdlib_page_modern_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `sf/src/std.zig`
- Modify: `sf/src/emit_support.zig`
- Modify: `sf/src/c89_emit.zig`
- Modify: `scripts/seed/build_from_seed.sh`
- Modify: `scripts/stdlib/expected_dirs.txt`
- Modify: `scripts/check_emit_support.sh`
- Modify: `scripts/gen_emit_support.sh`
- Modify: `scripts/compiler/gate_win_compat.sh`
- Modify: `scripts/compiler/gate_warn_clean.sh`

**Interfaces:**
- Produces:
```zig
pub const PosixMode = enum { auto, remap, protect, modern };

pub const PageConfig = struct {
    posix_mode: PosixMode,
    madvise_fn: ?fn (*void, usize, i32) i32,
};

pub const PageAllocator = struct { cfg: PageConfig, mode: u8 };
pub const PageError = error{InvalidConfig};

pub fn pageInit(cfg: PageConfig) PageError!PageAllocator;
pub fn pageConfigDefault() PageConfig;
pub fn pageReserve(self: *PageAllocator, bytes: usize) ?[*]u8;
pub fn pageCommit(self: *PageAllocator, ptr: [*]u8, bytes: usize) bool;
pub fn pageDecommit(self: *PageAllocator, ptr: [*]u8, bytes: usize) bool;
pub fn pageRelease(self: *PageAllocator, ptr: [*]u8, bytes: usize) void;
pub const PAGE_SIZE: usize = 4096;
pub const RESERVE_GRANULARITY: usize = 65536;
```
`pageConfigDefault()` returns `{ posix_mode = .auto, madvise_fn = null }`. `PageAllocator.mode` is the resolved mode (`native`/`remap`/`protect`/`modern`), fixed at init.

- [ ] **Step 1: Write the failing page fixtures**

`repro/mi_matrix/stdlib_page_xmod/main.zig`:
- reserve two pages, assert non-null;
- commit, write `0xA5`, read it back;
- decommit, recommit, assert the address is unchanged;
- repeat once in `protect` mode;
- assert `pageReserve(0)` returns `null`, `pageCommit(ptr, 0)`/`pageDecommit(ptr, 0)` return `false`, a misaligned `pageCommit` returns `false`, a non-page-multiple `pageCommit(ptr, PAGE_SIZE + 1)` and `pageDecommit(ptr, PAGE_SIZE + 1)` return `false`, `pageRelease(ptr, 0)` is a no-op;
- release both ranges;
- print exactly `page ok\n`.

`repro/mi_matrix/stdlib_page_modern_xmod/main.zig` (Linux-only; excluded from Win9x cross-build):
- declare `extern "c" fn madvise(addr: *void, len: usize, advice: i32) i32;` in the fixture and wrap it in a Z98 function `fn shim(p: *void, n: usize, advice: i32) i32`;
- `shim` increments a fixture counter; assert the counter advanced after each decommit (proves the modern callback ran, not remap) and assert `r[0] == 0` / `r[PAGE_SIZE] == 0` after recommit before writing new sentinels;
- run reserve/commit/write/decommit/recommit in `modern` mode with `madvise_fn = shim`;
- repeat with `posix_mode = .auto` and the same callback (auto resolves to modern);
- assert the address is unchanged and the recommitted range reads as fresh/zeroed; old bytes are not expected to survive `MADV_DONTNEED`/Win32 decommit;
- `pageInit` with `.modern` and a null callback returns `error.InvalidConfig`;
- print exactly `page modern ok\n`.

Add both fixture dirs to `scripts/stdlib/expected_dirs.txt` in lexicographic position (incremental pin; Task 8 verifies the final set). Both fixtures fail at compile because `std.page` does not exist.

- [ ] **Step 2: Run it to verify RED**

Run: `bash scripts/stdlib/run_fixtures.sh <seed-zig1> repro/mi_matrix/stdlib_page_xmod`
Expected: FAIL with a missing `std.page` / missing module diagnostic.

- [ ] **Step 3: Probe the emitter shapes**

Compile tiny probes and record results in the task report:
1. Optional fn field + **call-through-unwrap** (the `modern` dispatch site):
```zig
fn cb(p: *void, n: usize, advice: i32) i32 { return 0; }
var f: ?fn (*void, usize, i32) i32 = cb;
if (f) |g| { _ = g(ptr, 8, 4); }
```
2. Array of optional pointers: `var a: [8]?*void` read/write through an index (the `[128]?*Block` free-head table shape).

If either probe is rejected: **STOP** and request a spec amendment through the operator. Do not silently swap in `*const fn (...)` + `madvise_enabled: bool` — that is a public-shape change, and the plan's own rule is that public shape changes route through the spec, not a task-local fallback.

- [ ] **Step 4: Add `std_page_prelude.h`**

```c
#ifndef STD_PAGE_PRELUDE_H
#define STD_PAGE_PRELUDE_H
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 199309L
#endif
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE 1
#endif
#include <sys/mman.h>
#include <unistd.h>
#endif
#endif
```
No helper functions; prototypes/constants only. Never define `_FILE_OFFSET_BITS`. The feature-test macros must precede the OS headers (pattern `sf/src/include/std_time_prelude.h:17-27`); `c89_emit.zig:2247` emits no fallback externs for `@cInclude` modules, so the prelude is the only prototype source.

- [ ] **Step 5: Add `std_page_pal.zig`**

POSIX:
```zig
extern "c" fn mmap(addr: ?*void, len: usize, prot: i32, flags: i32, fd: i32, off: i32) *void;
extern "c" fn mprotect(addr: *void, len: usize, prot: i32) i32;
extern "c" fn munmap(addr: *void, len: usize) i32;
```
Constants: `PROT_NONE=0`, `PROT_READ=1`, `PROT_WRITE=2`, `MAP_PRIVATE=2`, `MAP_FIXED=16`, `MAP_ANON=32` (Z98-side constants; correct Linux 2.2+ ABI). `off: i32` targets 32-bit `off_t`.

Win32:
```zig
extern "stdcall" fn VirtualAlloc(addr: *void, size: usize, typ: u32, protect: u32) *void;
extern "stdcall" fn VirtualFree(addr: *void, size: usize, typ: u32) i32;
```
Declared `*void` non-optional to match `<windows.h>`'s `LPVOID` prototype: the emitted stdcall call casts through the extern's function type, so optional-pointer wrappers are an ABI mismatch. NULL is converted in `std_page.zig` with `@ptrToInt(raw) == 0` (z9git shape, `examples/z98/z9git/main.zig:31-32`).
Constants: `MEM_COMMIT=0x1000`, `MEM_RESERVE=0x2000`, `MEM_DECOMMIT=0x4000`, `MEM_RELEASE=0x8000`, `PAGE_NOACCESS=1`, `PAGE_READWRITE=4`.

- [ ] **Step 6: Implement `std_page.zig`**

- `auto`: Win9x native; POSIX `modern` if callback non-null, else `remap`.
- `remap`: `pageDecommit` does `munmap` then `mmap(MAP_FIXED|MAP_ANON|MAP_PRIVATE, PROT_NONE)`; `pageCommit` does `mprotect(PROT_READ|PROT_WRITE)`.
- `protect`: `mprotect(PROT_NONE)` / `mprotect(PROT_READ|PROT_WRITE)`.
- `modern`: `madvise_fn(ptr, bytes, 4)` for decommit; `mprotect` for commit; `pageInit` returns `error.InvalidConfig` when `.modern` has a null callback.
- Win32: reserve/commit/decommit/release through `VirtualAlloc`/`VirtualFree`; every `posix_mode` resolves to the native path. `pageRelease` calls `VirtualFree(ptr, 0, MEM_RELEASE)` — size **must** be 0 and `bytes` is ignored on Win32; POSIX calls `munmap(ptr, roundUp(bytes, RESERVE_GRANULARITY))`.
- Round reserve to `RESERVE_GRANULARITY`; `pageCommit`/`pageDecommit` require page-aligned pointers and page-multiple lengths (misaligned or non-multiple returns `false`, no silent rounding).
- Contracts: `pageReserve(0)` -> `null`; `pageCommit`/`pageDecommit` with `bytes == 0` -> `false`; `pageRelease(ptr, 0)` is a no-op; double `pageRelease` of one range is a caller bug (undefined), never done by the GPA.
- Failure sentinels: `mmap` is declared `*void` (non-optional); convert `MAP_FAILED` with `@ptrToInt(raw) >= 0xFFFFF000 -> null` (z9git rule, `examples/z98/z9git/main.zig:55-56`). `VirtualAlloc` is declared `*void` (non-optional); convert NULL with `@ptrToInt(raw) == 0 -> null`. Never dereference `MAP_FAILED` or a null mapping.

- [ ] **Step 7: Export and emit the prelude**

- Add `pub const page = @import("std_page.zig");` to `sf/src/std.zig` (barrel change; battery consequences are settled in Task 8, not here).
- `std_page.zig` carries `@cInclude("<std_page_prelude.h>")` — without it `scriptStdPageEmitted` never fires (`c89_emit.zig:9635-9656` scans reachable modules for the c-include string).
- Add `emitStdPagePreludeHSupport` to `sf/src/emit_support.zig`.
- Add `scriptStdPageEmitted` and conditional emission in `sf/src/c89_emit.zig`, using the same pattern as `std_os_prelude.h`/`std_time_prelude.h` (D3 value-ref closure: stdio-only programs omit the prelude).
- Add a `page` probe/`copy_one` to `scripts/gen_emit_support.sh`.
- Add a page dump directory and absent/present/byte-equality checks to `scripts/check_emit_support.sh`.
- Add `std_page_prelude.h` to the support allowlist in `scripts/compiler/gate_win_compat.sh:69-71`.
- Add `repro/mi_matrix/stdlib_page_xmod/main.zig` to `scripts/compiler/gate_warn_clean.sh` probe scope (currently hello/lisp/wide-enum only) so the prelude path compiles under `-std=c89 -pedantic -Wall -Werror`. Pin the page probe to the Linux target (`-osl`): host gcc cannot parse `<windows.h>`, and Windows warning coverage is the cross-build gates.
- Create `scripts/stdlib/run_gpa_safe.sh`: byte-clone of `scripts/stdlib/run_crypto_safe.sh` except the header line, tmp prefix, summary name, and default `DIRS`. It accepts explicit fixture dirs as arguments (same as `run_crypto_safe.sh`); each task passes its own fixtures. No flag = default `-fsafe`. Zero logic changes.
- Add `std_page.zig` and `std_page_pal.zig` to the `scripts/seed/build_from_seed.sh:146` lib copy list (test-compiler lib; the `:24` count comment waits for Task 8).

- [ ] **Step 8: GREEN and targeted gates**

Build the fixed test compiler once, then reuse it for every later task:
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <workspace>/zig1`
Use `<workspace>/zig1/zig1_5_clean` as `<seed-zig1>` below.

Run:
- `bash scripts/stdlib/run_fixtures.sh <seed-zig1> repro/mi_matrix/stdlib_page_xmod`
- `bash scripts/stdlib/run_gpa_safe.sh` (page fixtures under `-fsafe`);
- `bash scripts/check_emit_support.sh <seed-zig1>`;
- `bash scripts/compiler/gate_warn_clean.sh`;
- `bash scripts/win32_cross/cross_build_run.sh <zig1> repro/mi_matrix/stdlib_page_xmod/main.zig /tmp/t31_page /tmp/t31_page/prog.exe`;
- `bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_page/prog.exe nt` (CRT profile);
- `DUMP_TARGET=-osw bash scripts/win32_cross/cross_nocrt.sh <zig1> repro/mi_matrix/stdlib_page_xmod/main.zig /tmp/t31_page_nocrt /tmp/t31_page_nocrt/prog.exe`;
- `bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_page_nocrt/prog.exe 9x` (no-CRT profile; expect pass with **no** import-list change);
- run under Wine only if available; otherwise record SKIP.

Expected: page fixtures PASS in both modes; `std_page_prelude.h` present for page users, absent for `examples/z98/hello`; emitted bytes equal canonical.

- [ ] **Step 9: Commit**

```bash
git add sf/src/include/std_page_prelude.h sf/src/std_page_pal.zig sf/src/std_page.zig \
  sf/src/std.zig sf/src/emit_support.zig sf/src/c89_emit.zig \
  scripts/seed/build_from_seed.sh \
  scripts/stdlib/expected_dirs.txt \
  scripts/stdlib/run_gpa_safe.sh scripts/check_emit_support.sh scripts/gen_emit_support.sh \
  scripts/compiler/gate_win_compat.sh scripts/compiler/gate_warn_clean.sh \
  repro/mi_matrix/stdlib_page_xmod repro/mi_matrix/stdlib_page_modern_xmod
git commit -m "feat(std): add portable page allocator"
```

---

## Task 2: TLSF Small Tier and GPA Skeleton

**Files:**
- Create: `sf/src/std_gpa.zig`
- Create: `repro/mi_matrix/stdlib_gpa_small_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `sf/src/std.zig`
- Modify: `scripts/seed/build_from_seed.sh`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes Task 1 `PageAllocator`.
- Produces:
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

pub fn gpaConfigDefault() GpaConfig;
pub fn gpaConfigTarget32() GpaConfig;
pub fn gpaConfigTarget64() GpaConfig;
pub fn gpaConfigTarget128() GpaConfig;
pub fn gpaConfigTarget256() GpaConfig;
pub fn gpaConfigTarget512() GpaConfig;
pub fn gpaConfigTargetModern() GpaConfig;
pub fn gpaInit(cfg: GpaConfig) page_mod.PageError!Gpa;
pub fn gpaDeinit(g: *Gpa) void;
pub fn gpaAlloc(g: *Gpa, size: usize, align: usize) ?[*]u8;
pub fn gpaAllocZeroed(g: *Gpa, size: usize, align: usize) ?[*]u8;
pub fn gpaFree(g: *Gpa, ptr: [*]u8) bool;
pub fn gpaResize(g: *Gpa, ptr: [*]u8, new_size: usize, align: usize) ?[*]u8;
```

- [ ] **Step 1: Write the failing small fixture**

`stdlib_gpa_small_xmod`:
- initialize with `gpaConfigTarget64()`;
- allocate and write `1, 8, 16, 100, 1000, 4095` bytes;
- assert `gpaAlloc(g, 4096, 8)` returns `null` (medium boundary until Task 3; temporary, Task 3 replaces it with a medium-success/page-aligned assertion);
- exercise bitmap class selection across multiple classes (allocate a pattern at 16/100/1000/4000, free selected blocks, allocate again);
- force upper-class/region-tail allocation (allocate enough small blocks that the ~63 KiB tail is split; free mixed order and reallocate);
- check 8-byte alignment of every pointer;
- rejection cases: `align` of `0`, `3`, `7`, and `8192` all return `null`; `gpaAlloc(g, 0, 8)` and `gpaAllocZeroed(g, 0, 8)` return `null`;
- free in mixed order, reallocate, check reuse;
- `gpaFree` of a pointer outside every region returns `false`;
- resize a block upward, check the original bytes survived; `gpaResize(g, ptr, 0, 8)` returns `null` and leaves the old block valid;
- print deterministic pass/fail lines and end with `gpa small ok\n`.

Add `repro/mi_matrix/stdlib_gpa_small_xmod` to `scripts/stdlib/expected_dirs.txt` in lexicographic position (incremental pin).

- [ ] **Step 2: Run RED** (missing `std.gpa`).

- [ ] **Step 3: Implement TLSF small regions**

- 64 KiB region, 4096-aligned; region header at offset 0; block area follows.
- Metadata: `fl_bitmap: u32`, `sl_bitmap: [32]u32`, `free_heads: [192]?*Block` — the class map covers the whole 64 KiB region (FL 4..15 x 16 SL, sizes 16..65535), so the ~63 KiB region tail has a real class. The `[512]` table is rejected (8-byte optional pointers cost 4.2 KiB per 64 KiB region); `[192]` fits the 2 KiB header reserve. The Task 1 Step 3 array probe covers this shape.
- Block: 4-byte header, 4-byte footer, free-list links in payload; minimum 16 bytes; 8-byte alignment. Header u32: bit 0 `free`; bits 1..16 block size in bytes; bits 17..28 requested live bytes; bits 29..31 reserved. Footer u32: bit 0 `free`; bits 1..16 block size; upper bits zero — a **pure boundary tag**. The header carries **no region pointer**.
- Size mapping: first-level floor log2, second-level next four bits; bounded 32-iteration scan, no `@clz`. `sizeClass` covers 16..65535 and never clamps a 63 KiB tail into a sub-4-KiB class.
- Alloc: select the best-fit class through `fl_bitmap`/`sl_bitmap` (bounded 32-bit word masks, no linear 192-head scan), walk that class's free list for a block large enough, advance via the bitmaps if needed; split if remainder >= minimum block.
- Free: coalesce with physical neighbors, insert at class head (or a shuffled position when `shuffle` is set — Task 4 wires the LCG; this task inserts at head).
- Region identification: `gpaFree`/`gpaResize` identify the owning small region by **range walk over the region list** (`[base, base+64 KiB)` contains the pointer); no block-header identification.

- [ ] **Step 4: Implement GPA skeleton, contracts, and profiles**

- `gpaInit` resolves the page config and validates: `medium_max > 0`, `medium_max % PAGE_SIZE == 0`, `chunk_bytes % RESERVE_GRANULARITY == 0`, `chunk_bytes > medium_max`; violation returns `error.InvalidConfig`. No allocation at init.
- Alignment contract: `align` must be a power of two in `[8, 4096]`; `align == 0`, non-power-of-two, `< 8`, or `> 4096` -> `null`. Pass 8 for natural alignment. Until Task 3/4 land, `align > 8` and `size >= 4096` return `null` (routing lands with those tasks).
- Zero contract: `gpaAlloc(g, 0, a)` / `gpaAllocZeroed(g, 0, a)` -> `null`; `gpaResize(g, ptr, 0, a)` -> `null` and the old block stays valid; overflow-guarded sizing fails cleanly.
- `gpaAlloc` routes `size < 4096` to TLSF; `size >= 4096` returns `null` until Task 3.
- `gpaFree` ownership rule: a pointer outside every owned region/chunk/mapping returns `false` in all modes and touches no metadata. For an owned pointer the fast path frees and returns `true` with no further validation (a fast-path double free of an owned pointer is a caller bug, as with C `free()`); with `safe_checks` magic catches it (Task 5).
- `gpaResize` keeps the block if the new size fits the class, otherwise allocates/copies/frees; failure leaves the old pointer valid.
- `gpaDeinit` releases all small regions.
- Add profile constructors with the Global Constraints values; `gpaConfigDefault()` returns target64 with `page = pageConfigDefault()`, `safe_checks = false`, `shuffle = false`, `shuffle_seed = 0`. Explicit `medium_max`/`chunk_bytes` values are authoritative over `target` (constructors set both; manual overrides win).
- Add `std_gpa.zig` to the `scripts/seed/build_from_seed.sh:146` lib copy list.

- [ ] **Step 5: GREEN and commit**

Refresh the fixed test compiler's lib (no rebuild): `cp sf/src/std.zig sf/src/std_gpa.zig <workspace>/zig1/lib/`.
Run the fixture under `-ffast` (`run_fixtures.sh`) and `-fsafe` (`run_gpa_safe.sh`); run the existing `stdlib_arena_xmod` as regression.
Commit:
```bash
git add sf/src/std_gpa.zig sf/src/std.zig scripts/seed/build_from_seed.sh \
  scripts/stdlib/expected_dirs.txt repro/mi_matrix/stdlib_gpa_small_xmod
git commit -m "feat(std): add TLSF small allocator"
```

Expected: small fixture PASS; no corruption; alignment, rejection, and resize contracts correct.

---

## Task 3: Medium Page Free Lists

**Files:**
- Modify: `sf/src/std_gpa.zig`
- Create: `repro/mi_matrix/stdlib_gpa_medium_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `repro/mi_matrix/stdlib_gpa_small_xmod/main.zig`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Consumes Task 2 `Gpa`, `GpaConfig`, `gpaAlloc`/`gpaFree`.
- Produces medium allocation for `4096..medium_max`; `align > 8` routing to medium runs; `gpaAlloc`/`gpaFree`/`gpaResize` complete for medium sizes.

- [ ] **Step 1: Write the failing medium fixture**

- Allocate `4096`, `8192`, `16384`, and `65536` bytes.
- Alignment routing: a small size with `align = 16` and with `align = 4096` must return a suitably aligned pointer (routed through the medium tier).
- Write a distinct marker at the start and end of each allocation.
- Free in mixed order; reallocate and verify reuse/coalescing.
- Resize `4096 -> 8192`; verify the original bytes survived.
- Stress 1000 medium allocations/frees; assert no duplicate live pointers and no marker corruption. Free all 1000, then reallocate to force the whole-chunk free run to be split; assert markers.
- End with `gpa medium ok\n`.

Add `repro/mi_matrix/stdlib_gpa_medium_xmod` to `scripts/stdlib/expected_dirs.txt` in lexicographic position (incremental pin).

- [ ] **Step 2: Run RED.**

- [ ] **Step 3: Implement page-run medium tier**

- Reserve 2 MiB chunks with `pageReserve`; commit the chunk header and page metadata.
- Page metadata: state, run start, run length, per 4 KiB page.
- Run classes: free-run storage classes cover 1, 2, 4, 8, 16, ... pages through `chunk_bytes / PAGE_SIZE`; allocation requests are capped at `medium_max / PAGE_SIZE`; larger free runs are split to serve requests.
- Allocate the smallest fitting run; split larger free runs; free coalesces adjacent runs in the same chunk.
- Commit pages on allocation. When `safe_checks` is true, decommit a fully free run; otherwise keep it committed for reuse.
- `gpaFree` finds the owning chunk/page by address range; `gpaResize` keeps the run if the new size fits, else allocates/copies/frees.
- Enable `align > 8` routing: run starts are page-aligned, which satisfies every allowed `align`; a small request with `align > 8` occupies a full page run (documented waste).
- `gpaDeinit` releases all medium chunks.

- [ ] **Step 4: GREEN and commit**

Refresh the fixed test compiler's lib (no rebuild): `cp sf/src/std_gpa.zig <workspace>/zig1/lib/`.
Update `stdlib_gpa_small_xmod`: replace the temporary `gpaAlloc(g, 4096, 8) == null` assertion with a medium-success assertion (`!= null`) plus a page-alignment check; keep the output `gpa small ok`.
Run the medium fixture and the small regression under `-ffast` and `-fsafe`.
Commit:
```bash
git add sf/src/std_gpa.zig scripts/stdlib/expected_dirs.txt \
  repro/mi_matrix/stdlib_gpa_medium_xmod \
  repro/mi_matrix/stdlib_gpa_small_xmod/main.zig
git commit -m "feat(std): add page-run medium allocator"
```

Expected: mixed-size medium workload PASS; coalescing works; no stale run metadata; align>8 routing honored.

---

## Task 4: Large Objects, Profiles, Resize, Stats, Shuffle

**Files:**
- Modify: `sf/src/std_gpa.zig`
- Create: `repro/mi_matrix/stdlib_gpa_large_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `repro/mi_matrix/stdlib_gpa_resize_xmod/{main.zig,expected.txt,expected.rc}`
- Create: `repro/mi_matrix/stdlib_gpa_shuffle_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `repro/mi_matrix/stdlib_gpa_small_xmod/main.zig`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- Completes `gpaAlloc` for sizes above `medium_max`.
- Produces:
```zig
pub const GpaStats = struct {
    small_bytes: usize,
    medium_bytes: usize,
    large_bytes: usize,
    live_allocs: usize,
    chunks: usize,
    regions: usize,
};
pub fn gpaStats(g: *Gpa) GpaStats;
```

- [ ] **Step 1: Write the failing large/resize/shuffle fixtures**

`stdlib_gpa_large_xmod`:
- allocate `65537`, `1 MiB`, and a 4096-aligned large block;
- write/read start and end markers;
- free and reallocate;
- `gpaAllocZeroed` returns zero bytes;
- `align = 8192` returns `null` (stricter-than-page alignment is deferred);
- `gpaStats` assertions after known workloads: `small_bytes`/`medium_bytes`/`large_bytes` match the live sums, `live_allocs` matches live objects (tracked in **all** modes), `chunks`/`regions` match the owners;
- end with `gpa large ok\n`.

`stdlib_gpa_resize_xmod`:
- grow/shrink small, medium, and large blocks; verify contents survive;
- resize with a stricter `align` forces an aligned realloc path (contents copied; on failure the old pointer remains valid);
- deterministic failure recipe: `gpaResize(g, ptr, 0xFFFFFFF0, 8)` must return `null` through the u64 overflow guard (`size + header` exceeds `0xFFFFFFFF`) and leave the old pointer valid and unchanged;
- `gpaResize(g, ptr, 0, 8)` returns `null`, old block still valid;
- end with `gpa resize ok\n`.

`stdlib_gpa_shuffle_xmod`:
- same `shuffle_seed` in two fresh `Gpa`s reproduces the identical allocation/reuse sequence;
- `shuffle = false` matches the deterministic head-insertion baseline;
- no security claim in the output text;
- end with `gpa shuffle ok\n`.

Add the three `repro/mi_matrix/stdlib_gpa_{large,resize,shuffle}_xmod` dirs to `scripts/stdlib/expected_dirs.txt` in lexicographic position (incremental pin).

Small-tier regression in `repro/mi_matrix/stdlib_gpa_small_xmod/main.zig` (same dir): allocate odd requested sizes (1, 3, 5) adjacent to neighbors, free a neighbor while an odd block is live, then free the odd blocks and reallocate; assert no corruption and the requested-byte `small_bytes` value. This pins the packed-header/footer fix.

- [ ] **Step 2: Run RED.**

- [ ] **Step 3: Implement the large direct path**

- `pageReserve(size + header, rounded to 64 KiB)` with u64 overflow guard; `pageCommit`; header records size/class/magic.
- Return page-aligned data (satisfies every allowed `align <= 4096`).
- Ownership is a range walk over the live large-mapping list; `gpaFree` reads the header and `pageRelease`s the whole mapping.
- `gpaResize` reuses the mapping when the new size fits; otherwise allocates/copies/frees; align changes follow the spec rule (stricter align forces the aligned realloc path).
- `gpaStats` reports bytes and counts; `live_allocs` is **always** tracked (cheap counter), not only with safe checks. Byte counters are **requested** live bytes: `small_bytes` from the packed header bits 17..28, `medium_bytes` from `used_bytes`, `large_bytes` from the mapping header size. The footer remains a pure `free|size` boundary tag; requested bytes are never stored there.

- [ ] **Step 4: Implement profile selection and optional shuffle**

- `gpaConfigDefault()` = target64.
- Profile constructors use the Global Constraints table; explicit `medium_max`/`chunk_bytes` override `target`.
- `shuffle: bool` + `shuffle_seed: u32`: 32-bit LCG `state = state * 1103515245 + 12345`; scope is TLSF class free lists and medium run free-list insertion order. No `.encrypted` code and no security claim.

- [ ] **Step 5: GREEN and commit**

Refresh the fixed test compiler's lib (no rebuild): `cp sf/src/std_gpa.zig <workspace>/zig1/lib/`.
Run all GPA fixtures under `-ffast` and `-fsafe`.
Commit:
```bash
git add sf/src/std_gpa.zig scripts/stdlib/expected_dirs.txt \
  repro/mi_matrix/stdlib_gpa_large_xmod \
  repro/mi_matrix/stdlib_gpa_resize_xmod repro/mi_matrix/stdlib_gpa_shuffle_xmod \
  repro/mi_matrix/stdlib_gpa_small_xmod/main.zig
git commit -m "feat(std): add large allocations and GPA profiles"
```

Expected: large/resize/shuffle fixtures PASS; profiles select the documented caps; overflow guard fails cleanly.

---

## Task 5: Safe Checks and Decommit Behavior

**Files:**
- Modify: `sf/src/std_gpa.zig`
- Create: `repro/mi_matrix/stdlib_gpa_safe_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
- `GpaConfig.safe_checks = true` enables:
  - a 4-byte small-block magic suffix immediately before the footer: live `0xDEADBEEF`, freed `0xFEEDFACE`. Safe blocks use `requested + 12` block bytes and min block 24; fast mode uses `requested + 8`, min 16. Pointer math stays `b = ptr - 4` in both modes. Validate `size % 8 == 0`, `size >= min_block`, `b + size <= region_end` before trusting the magic.
  - `0xDD` fill on free (inline byte loops — `std_mem` keeps its current API, no `fillU8` addition); fill the requested payload only, never the magic/links/footer;
  - double-free detection (`gpaFree` returns `false`);
  - medium page-metadata state and large mapping-header magic;
  - decommit of empty medium runs and release/decommit of empty small regions.
- `safe_checks = false` keeps the fast path: no magic checks, and a double free of an owned pointer is tolerated (returns `true`, caller bug) — the structural outside-range `false` from Task 2 still applies.
- `live_allocs` tracking is **not** a safe-checks behavior (always on, Task 4).

- [ ] **Step 1: Write the failing safe fixture**

- initialize with target64 and `safe_checks=true`;
- allocate/free; double free returns `false`; a deliberately corrupted small magic also returns `false`;
- `live_allocs` matches the live objects;
- free a medium run and verify it can be reused; confirm `0xDD` fill bytes in the requested payload;
- free a small region's blocks and verify a later allocation still works; exercise safe-mode coalescing, split, and resize so the magic suffix tracks size changes;
- verify `-fsafe` alone does not enable checks: in a **throwaway `Gpa`** with `safe_checks=false`, confirm a second free is not rejected — this check runs **last** (or on the throwaway instance) because a tolerated fast-path double free corrupts that heap;
- end with `gpa safe ok\n`.

Add `repro/mi_matrix/stdlib_gpa_safe_xmod` to `scripts/stdlib/expected_dirs.txt` in lexicographic position (incremental pin).

- [ ] **Step 2: Run RED.**

- [ ] **Step 3: Implement safe checks**

- Small: 4-byte magic suffix before the footer (`magicAt = b + blockSize - 8`); allocate/split set live magic, free/merge set freed magic, region init sets freed; validate size/range before reading; fill the requested payload with `0xDD` on free via inline loops; double-free or bad magic returns `false`. Safe `blockBytes` adds 12 and min block is 24; fast adds 8/min 16; pointer math stays `b = ptr - 4`.
- Medium: page metadata state; double-free returns `false`; fill run data on free; decommit fully free runs.
- Large: header magic; fill data on free; release on free.
- Leak tracking is a live count only; no per-allocation pointer list.
- Do not make `-fsafe` mutate GPA config.

- [ ] **Step 4: GREEN and commit**

Refresh the fixed test compiler's lib (no rebuild): `cp sf/src/std_gpa.zig <workspace>/zig1/lib/`.
Run the safe fixture under `-ffast` and `-fsafe` (`run_gpa_safe.sh`); run all prior GPA fixtures.
Commit:
```bash
git add sf/src/std_gpa.zig scripts/stdlib/expected_dirs.txt \
  repro/mi_matrix/stdlib_gpa_safe_xmod
git commit -m "feat(std): add GPA safe checks"
```

Expected: double-free detected only with safe checks; live count correct; no live-run decommit.

---

## Task 6: `std.pool`

**Files:**
- Create: `sf/src/std_pool.zig`
- Create: `repro/mi_matrix/stdlib_pool_xmod/{main.zig,expected.txt,expected.rc}`
- Modify: `sf/src/std.zig`
- Modify: `scripts/seed/build_from_seed.sh`
- Modify: `scripts/stdlib/expected_dirs.txt`

**Interfaces:**
```zig
pub const Pool = struct { /* caller buffer, block size, block count, free list, used */ };
pub fn poolInit(buf: []u8, block_size: usize, align: usize) ?Pool;
pub fn poolAlloc(p: *Pool) ?[*]u8;
pub fn poolFree(p: *Pool, ptr: [*]u8) bool;
pub fn poolReset(p: *Pool) void;
pub fn poolLen(p: *Pool) usize;
```

- [ ] **Step 1: Write the failing pool fixture**

- 4 KiB buffer, 32-byte blocks, 8-byte alignment;
- allocate until `null`; free one; reallocate; reset; check count;
- contracts: `poolInit(buf, 0, 8)` -> `null`; `poolInit(buf, 32, 0)` and `poolInit(buf, 32, 3)` -> `null`; `poolInit` with a buffer smaller than one rounded block -> `null`;
- free a pointer outside the buffer, and a misaligned pointer; both return `false`;
- end with `pool ok\n`.

Add `repro/mi_matrix/stdlib_pool_xmod` to `scripts/stdlib/expected_dirs.txt` in lexicographic position (incremental pin).

- [ ] **Step 2: Run RED.**

- [ ] **Step 3: Implement the fixed-block pool**

- Carve blocks from the caller buffer; store free-list links in free blocks.
- `poolInit` contracts per Step 1: `block_size == 0` -> `null`; `align` must be a power of two in `[8, 4096]`; round `block_size` up to alignment; the rounded block must be at least one pointer wide; a buffer smaller than one rounded block -> `null`.
- `poolAlloc` is O(1) from the free head; `poolFree` validates range/alignment structurally and returns `false` otherwise (pool validation is always on).
- `poolReset` rebuilds the free list; `poolLen` returns live blocks.
- No GPA dependency; no dynamic growth.
- Add `std_pool.zig` to the `scripts/seed/build_from_seed.sh:146` lib copy list.

- [ ] **Step 4: GREEN and commit**

Refresh the fixed test compiler's lib (no rebuild): `cp sf/src/std.zig sf/src/std_pool.zig <workspace>/zig1/lib/`.
Run under `-ffast` and `-fsafe`.
Commit:
```bash
git add sf/src/std_pool.zig sf/src/std.zig scripts/seed/build_from_seed.sh \
  scripts/stdlib/expected_dirs.txt repro/mi_matrix/stdlib_pool_xmod
git commit -m "feat(std): add fixed-block pool"
```

Expected: pool exhaustion, reuse, reset, and invalid-free behavior PASS.

---

## Task 7: Limited GPA-Aware Analyzer

**Files:**
- Modify: `sf/src/diagnostics.zig`
- Modify: `sf/src/analyzer.zig`
- Modify: `sf/src/tests/test_analyzer_bin.zig`
- Modify: `tests/analyzers/NOTES.md`
- Modify: `docs/sf/manuals/en/vol4-21-diagnostics.html`
- Modify: `docs/sf/manuals/dist/en/vol4-21-diagnostics.html`
- Modify: `sf/docs/tech_docs/06_static_analyzers.md`
- Create: `tests/analyzers/gpa_double_free.zig`
- Create: `tests/analyzers/gpa_use_after_free.zig`
- Create: `tests/analyzers/gpa_leak.zig`
- Create: `tests/analyzers/gpa_alias_negative.zig`

**Interfaces:**
- `isAllocCall`/`isFreeCall` recognize `gpaAlloc`, `gpaAllocZeroed`, `gpaFree` in **both** call shapes: bare `ident_expr` (`gpaAlloc(g, n, a)`) and module-qualified member calls (`gpa.gpaAlloc(&g, n, a)`) matched on the callee's final identifier name. Today's matchers (`sf/src/analyzer.zig:222-256`) accept only bare callees and must be extended.
- `ERR_2006_USE_AFTER_FREE = 3079`, added as an **explicit-value member at the enum tail** of `ErrorCode` (`sf/src/diagnostics.zig`). Never insert a bare auto member near `ERR_2005_DOUBLE_FREE` — that member is bare auto-increment with real value 3035; a mid-enum insert shifts `ERR_9999` onto the explicit `3045` and the compiler rejects the duplicate (`ERR_3055`), and every later code drifts. 3078 is the last used value.
- Same-block only: free followed by dereference/index/field use of the same identifier; a bare pointer copy is not a use.
- Leak warning `WARN_6005_MEMORY_LEAK` for an allocation not freed in the same straight-line block.
- No interprocedural, alias, or branch-merge claims.

- [ ] **Step 1: Write the failing fixtures**

- `gpa_double_free.zig`: allocate, free twice -> `ERR_2005`.
- `gpa_use_after_free.zig`: allocate, free, index -> `ERR_2006` (error number 3079).
- `gpa_leak.zig`: allocate, no free -> `WARN_6005`.
- `gpa_alias_negative.zig`: copy the pointer, free the original, use the copy -> no UAF diagnostic; this pins the documented limitation.
- One fixture uses qualified calls (`gpa.gpaAlloc(...)`) to pin the member-call matching.

- [ ] **Step 2: Run RED** through the analyzer test harness; the fixtures must fail for the missing names/diagnostic.

- [ ] **Step 3: Implement names and state**

- Extend `isAllocCall`/`isFreeCall` for bare and qualified call shapes (final-identifier match; `gpaFree(g, ptr)` keeps the arg-1 pointer convention).
- Track freed identifiers in the existing double-free state map.
- Emit `ERR_2006` on the first dereference/index/field use; do not flag a bare pointer copy.
- Emit `WARN_6005` at block end for live allocations.
- Register `ERR_2006` in the diagnostic tables: `docs/sf/manuals/en/vol4-21-diagnostics.html`, `docs/sf/manuals/dist/en/vol4-21-diagnostics.html`, and `sf/docs/tech_docs/06_static_analyzers.md` (analyzer behavior).

- [ ] **Step 4: GREEN and commit**

This task changes compiler source (diagnostics/analyzer), so rebuild the fixed test compiler into the same path: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <workspace>/zig1` (its lib list already includes all four modules from Tasks 1/2/6).
Build and run the analyzer test binary per `tests/analyzers/NOTES.md`; update Notes with the new fixtures.
Commit:
```bash
git add sf/src/diagnostics.zig sf/src/analyzer.zig sf/src/tests/test_analyzer_bin.zig \
  tests/analyzers/NOTES.md tests/analyzers/gpa_*.zig \
  docs/sf/manuals/en/vol4-21-diagnostics.html \
  docs/sf/manuals/dist/en/vol4-21-diagnostics.html \
  sf/docs/tech_docs/06_static_analyzers.md
git commit -m "feat(analyzer): recognize GPA ownership and same-block UAF"
```

Expected: fixtures pass (including qualified-call case); alias case emits no false UAF.

---

## Task 8: Integration, Battery Re-baseline, Seed, and Docs

**Files:**
- Modify: `scripts/seed/archive_seed.sh`
- Modify: `scripts/seed/build_from_seed.sh`
- Modify: `scripts/compiler/gate_lower_depth.sh`
- Modify: `scripts/stdlib/run_gpa_safe.sh`
- Modify: `docs/sf/QUICK_REF.md`
- Modify: `docs/reference/Language_Spec_Z98.md`
- Modify: `STD_README.MD`
- Modify: `release/seed/CHANGELOG.md`
- Modify: `README.md`
- Modify: `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip` (via seed tooling)

- [ ] **Step 1: Verify fixture pins and safe-runner defaults**

Verify all nine `repro/mi_matrix/stdlib_*_xmod` dirs (page, page_modern, gpa_small, gpa_medium, gpa_large, gpa_resize, gpa_safe, gpa_shuffle, pool) are already pinned in `scripts/stdlib/expected_dirs.txt` (each task added its own; do not re-add). Set `run_gpa_safe.sh` default `DIRS` to the same nine (bare invocation, as Task 9 uses). Run:
`bash scripts/stdlib/verify_stdlib.sh <seed-zig1>`
Expected: all fixtures + crosscheck PASS; no dropped/renamed fixture.

- [ ] **Step 2: Battery anchor re-baseline (fold-era procedure, one time)**

The `sf/src/std.zig` barrel exports (`page`/`gpa`/`pool`) move the 8 dump-md5 pins and the marker counts. The re-baseline happens **once**, here, after all barrel exports landed. Nothing before this step records pin values.

1. **Verified-delta**: dump the four pin programs (`mud_server`, `game_of_life`, `lisp_interpreter_curr`, `json_parser`) in both modes with the pre-3.1 compiler and the new one. The dump diff must contain only (a) new `std_page`/`std_gpa`/`std_pool` module C and module-list entries where emitted, and (b) type-identifier intern renames. Any other change (function-body logic, reordered emission, different constants) = **STOP**.
2. **Goldens**: re-prove the 5 runtime stdout md5s byte-identical. Any change = **STOP**.
3. **frozen-1124**: classification md5 `518eca1a…` must have 0 movers. Any mover = **STOP**.
4. **Live corpus**: grows exactly by the 9 new fixture dirs (1256 -> 1265); any other mover = **STOP**.
5. Re-record the 8 pins **once**, by hand (no script generates pin values), in `scripts/compiler/gate_lower_depth.sh:24-28,300-307` **and** `docs/sf/QUICK_REF.md:752-771` (new table; old table demoted to Historical).
6. Re-record the marker counts (`--markers` stream; previously 3397 lines / 39012 bytes) with cause attribution in the ruling-A format (`.superpowers/sdd/2026-10-27-phase25-cleanup-mutable-for-plan/progress.md:141`).
7. Run `bash scripts/compiler/gate_lower_depth.sh` green afterward.

- [ ] **Step 3: Seed packaging**

- Add `std_page.zig`, `std_page_pal.zig`, `std_gpa.zig`, `std_pool.zig` to the `archive_seed.sh` lib copy list (`:181`) **and** the hardcoded count strings: header comment (`:42-55`), generated `SEED_README.txt` heredoc "the 52 std .zig" (`:376-392`), "(52 std files," (`:392`), "lib/ with the 52" (`:490`). Defensively add `std_page_prelude.h` to the support-exclusion `rm` list (`:154`).
- Verify the four modules are already in the `build_from_seed.sh` produced-compiler lib copy list (`:146`) from Tasks 1/2/6, and update its "52 std .zig" comment (`:24`) to 56.
- Update "52" strings in `STD_README.MD:59`, `docs/sf/QUICK_REF.md:172`, `README.md:397,476`.
- Do not add `std_page_prelude.h` to the seed archive; the compiler emits it from `emit_support.zig`.
- Lib count becomes 56; manifest changes.

- [ ] **Step 4: Rotate seed v142**

- Build from `release/seed/zig1-seed.tgz` with `bash scripts/seed/build_from_seed.sh`.
- Run the two-hop closure (hop1 == hop2); record archive md5, zip md5, lib count, manifest md5, fixed point.
- Assert the produced compiler's lib: `<out>/lib/std_gpa.zig` exists and `ls <out>/lib/*.zig | wc -l` = 56; assert the archive `lib/` count is 56.
- Fixed point note: the std payload alone never moves the compiler fixed point, but the compiler-source changes in Tasks 1 and 7 (`emit_support.zig`, `c89_emit.zig`, `diagnostics.zig`, `analyzer.zig`) legitimately move it. Record the new value with that attribution. If a pure-std change moves it, **STOP**.
- Update `CHANGELOG.md`, `QUICK_REF.md`, `STD_README.MD`, and `README.md` to 56 std files and the Phase 3.1 API.
- Commit:
```bash
git add scripts/seed/archive_seed.sh \
  scripts/seed/build_from_seed.sh \
  scripts/stdlib/run_gpa_safe.sh \
  scripts/compiler/gate_lower_depth.sh docs/sf/QUICK_REF.md \
  docs/reference/Language_Spec_Z98.md \
  STD_README.MD release/seed/CHANGELOG.md README.md \
  release/seed/zig1-seed.tgz release/seed/zig1_seed_w9.zip
git commit -m "chore(seed): rotate v142 (phase 3.1 allocators)"
```

- [ ] **Step 5: Document the limits and update the language spec**

- `std.page` modes, the Win32 `pageRelease` size-0 asymmetry, and the optional `madvise` callback.
- GPA profiles and 64 MB default; the `align` contract (`[8, 4096]`, power of two).
- `safe_checks` is explicit; `-fsafe` does not auto-enable.
- `docs/reference/Language_Spec_Z98.md` per blueprint §5: §2 non-nested lifetimes point to `std.gpa`; §5 notes `safe_checks` is explicit; §7 "no malloc" wording re-scoped to arena-default + `std.gpa`/`std.pool`.
- TLS design-only; `.encrypted` deferred; no compiler migration.
- No security or cycle-target claims.
- Win9x evidence is cross-build/Wine only.
- The GPA-aware analyzer reports module-qualified arena allocations (`sand_mod.sand_alloc`) as leaks; lisp's four `warning[3038]` diagnostics are expected and desirable (arena blocks are intentionally never freed), stderr-only, with unchanged stdout goldens.

---

## Task 9: Final Gates

**Files:** none.

- [ ] **Step 1: Std gates (I2: the std battery ran in Task 8 and is not repeated)**

Task 8 already ran `verify_stdlib` (365/0 + crosscheck 10/10), `run_gpa_safe` (9/0), and `gate_lower_depth` after re-recording the pins. Do not re-run them. Run the gates Task 8 did not:

```bash
bash scripts/check_emit_support.sh <seed-zig1>
bash scripts/compiler/gate_warn_clean.sh
```
Build/run `sf/src/tests/test_analyzer_bin.zig` with the seed compiler per `tests/analyzers/NOTES.md`.

- [ ] **Step 2: Portability gates**

```bash
bash scripts/compiler/gate_win_compat.sh
bash scripts/win32_cross/cross_build_run.sh <zig1> repro/mi_matrix/stdlib_page_xmod/main.zig /tmp/t31_final /tmp/t31_final/prog.exe
bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_final/prog.exe nt
DUMP_TARGET=-osw bash scripts/win32_cross/cross_nocrt.sh <zig1> repro/mi_matrix/stdlib_page_xmod/main.zig /tmp/t31_final_nocrt /tmp/t31_final_nocrt/prog.exe
bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_final_nocrt/prog.exe 9x
bash scripts/win32_cross/cross_build_run.sh <zig1> repro/mi_matrix/stdlib_gpa_small_xmod/main.zig /tmp/t31_gpa /tmp/t31_gpa/prog.exe
bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_gpa/prog.exe nt
DUMP_TARGET=-osw bash scripts/win32_cross/cross_nocrt.sh <zig1> repro/mi_matrix/stdlib_gpa_small_xmod/main.zig /tmp/t31_gpa_nocrt /tmp/t31_gpa_nocrt/prog.exe
bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_gpa_nocrt/prog.exe 9x
bash scripts/win32_cross/cross_build_run.sh <zig1> repro/mi_matrix/stdlib_pool_xmod/main.zig /tmp/t31_pool /tmp/t31_pool/prog.exe
bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_pool/prog.exe nt
DUMP_TARGET=-osw bash scripts/win32_cross/cross_nocrt.sh <zig1> repro/mi_matrix/stdlib_pool_xmod/main.zig /tmp/t31_pool_nocrt /tmp/t31_pool_nocrt/prog.exe
bash scripts/win32_cross/check_win9x_imports.sh /tmp/t31_pool_nocrt/prog.exe 9x
```
`stdlib_page_modern_xmod` is Linux-only (needs `madvise`); exclude it from cross-build. Run under Wine only if available; otherwise record SKIP, not PASS. Pin Win32 expectations in the report: `pageRelease` = `VirtualFree(ptr, 0, MEM_RELEASE)`.

- [ ] **Step 3: Tree checks**

```bash
git diff --check
git diff --name-only | grep -E 'sf/src/(allocator|main)\.zig$' && exit 1 || true
```
Confirm no C page runtime, no `zig_runtime.c` change, no `_FILE_OFFSET_BITS` in the prelude, and no `.encrypted` code. Confirm `scripts/win32_cross/check_win9x_imports.sh` is unchanged.

- [ ] **Step 4: Final review**

Review the full branch against the spec. Fix only Critical/Important findings; record deferred minors. Do not start HTTP/2, compiler migration, TLS implementation, or `.encrypted`.

- [ ] **Step 5: Stop**

The plan is complete when the acceptance criteria below hold and the final review is clean.

---

## Post-fix v143 rotation (final-review fix wave)

- The final-review Important fix changes `sf/src/std_gpa.zig` (decommit-failure handling). Rotate seed **v143** after the fix: `archive_seed.sh` then `build_from_seed.sh`, two-hop closure, lib 56, produced-lib `std_gpa.zig` + compile check.
- Targeted verification only (operator ruling, localized post-fix): GPA fixtures under `-ffast`/`-fsafe`, `gate_lower_depth` (pins), and a marker-count check. Do not re-run the full goldens/frozen-1124/corpus battery. A second fold-era anchor move is authorized (2026-11-07): verify the canonical v142 baseline (archive compiler+lib), then re-record the 8 pins and markers once with cause attribution.
- Update current-seed docs to v143 (README/QUICK_REF/STD_README/CHANGELOG); preserve v142 history.

---

## Acceptance Criteria

- `stdlib_page_xmod` and `stdlib_page_modern_xmod` pass under `-ffast` (`run_fixtures.sh`) and `-fsafe` (`run_gpa_safe.sh`).
- Small, medium, large, resize, safe, shuffle, and pool fixtures pass in both modes.
- Contracts hold: zero-size and invalid-align calls return `null`/`false`; `gpaResize(ptr, 0, a)` leaves the old block valid; `0xFFFFFFF0` resize fails cleanly via the u64 overflow guard; `pageReserve(0)` -> `null`; Win32 `pageRelease` passes size 0.
- TLSF class selection is bitmap-driven (`fl_bitmap`/`sl_bitmap`, no linear head scan) and the class map covers 16..65535 (FL 4..15), including the region tail.
- `gpaFree` returns `false` only for unowned pointers (all modes) and for double free when `safe_checks=true`; `-fsafe` alone does not enable checks; the fast-path double-free tolerance test runs last or on a throwaway `Gpa`.
- GPA default profile is 64 MB; every profile selects the documented medium cap/chunk; explicit `medium_max`/`chunk_bytes` override `target`.
- `std_page_prelude.h` appears only when `std.page` is reachable; stdio-only dumps omit it; the prelude defines `_POSIX_C_SOURCE`/`_DEFAULT_SOURCE` first and never `_FILE_OFFSET_BITS`; `gate_warn_clean.sh` covers a page-reachable program.
- Battery anchors follow fold-era accounting: 8 pins + markers re-baselined once with verified-delta; goldens byte-identical; frozen-1124 0 movers; live corpus exactly +9 fixture dirs; `gate_lower_depth.sh` green after re-record.
- Win9x cross-build/import gate passes for page/gpa_small/pool (or is explicitly SKIP with reason) with **no** `check_win9x_imports.sh` whitelist change; no real-hardware claim.
- Analyzer fixtures pass (bare + qualified calls); `ERR_2006_USE_AFTER_FREE` is 3079 at the enum tail with all three doc tables updated; alias/interprocedural limitations are documented.
- Seed v143 closure succeeds (hop1 == hop2); lib count is 56; docs and `archive_seed.sh`/`build_from_seed.sh` count strings match the archive; a compiler produced by `build_from_seed.sh` ships 56 lib files including the four new modules, and a program importing `std.gpa` compiles with it; fixed-point movement is attributed to the Tasks 1/7 compiler-source changes only.
- `docs/reference/Language_Spec_Z98.md` §2/§5/§7 updated per blueprint §5.
- No compiler allocator migration; no C page runtime; no `.encrypted`; no TLS implementation.
