# Task F4 — std.zig + std_io.zig + migrate all 21 examples + remove __bootstrap_* I/O wrappers — Report [2026-08-08]

Brief: `.superpowers/sdd/task-F4-brief.md`. Consumed: I-RT (bootstrap→builtin map), F1 (6 I/O
builtins), F2 (4 console builtins), F3 (std_arena). Compiler rebuilt once (c89_emit.zig console
repoint, below). Status: **DONE** (with documented deviations).

---

## 1. std.zig / std_io.zig API

**`sf/src/std.zig`** (root package, 2 lines): `pub const io = @import("std_io.zig");` +
`pub const arena = @import("std_arena.zig");`.

**`sf/src/std_io.zig`** (stdout/stderr I/O over the F1 builtins; no Writer struct — see D3):

| Function | Signature | Impl | Maps from |
|---|---|---|---|
| `writeByte` | `(c: u8) void` | `@putChar(c)` | `__bootstrap_print_char` |
| `write` | `(data: []const u8) void` | `@stdoutWrite(data.ptr, data.len)` | `__bootstrap_write` |
| `writeStr`/`print` | `(s: [*]const c_char) void` | walk to NUL, `@stdoutWrite` | `__bootstrap_print` |
| `printInt` | `(n: i32) void` | Zig itoa (neg + digits) into a buffer, `@stdoutWrite` | `__bootstrap_print_int` |
| `readByte` | `() u8` | `@getChar()` | `@getChar` (lisp/rogue getchar stays extern) |
| `sleepMs` | `(ms: u32) void` | `@sleepMs(ms)` | `__bootstrap_sleep_ms` |

Notes: `print` takes `[*]const c_char` (many-pointer) so it accepts string literals, `&buf[0]`,
and `@ptrCast`ed pointers (all the call-site forms the examples used). The brief's `Writer`
struct sketch was dropped — Z98 does not support `pub fn` inside a struct literal
(parse error[2000]); no example needed a Writer. The brief's sketch wrote `@stderrWrite` in
`write`; that is a typo for `@stdoutWrite` (m0564 added `@stdoutWrite` for stdout) — stdout
writes use `@stdoutWrite`.

**Import resolution (DEVIATION D1 — documented):** the brief prescribes `const std =
@import("std")`; the resolver (`module_registry.zig:144-161`) only does exact-path joins
(no `.zig` extension append, `moduleResolverAddSearchDir` never called) → bare `@import("std")`
fails `error[3048]`. F4 cannot change the compiler (out of scope). Followed the F3 std_arena
precedent: byte-identical copies of `std_io.zig` + `std_arena.zig` live in each example dir, and
a local `std.zig` (the root package + `pub const debug = @import("std_debug.zig")` where the dir
has one) is imported as `@import("std.zig")`. 19 dirs carry the copies (mud_server/rogue_mud
share mud_server's `std.zig` via the existing `../mud_server/std.zig` import; lzw + days_in_month
keep their local std.zig). A resolver search-path feature is the future enabler for bare
`@import("std")`.

**mud_server local `std.zig` = `io` + `debug` only (DEVIATION D2 — documented).** The canonical
root package re-exports `arena`; in the rogue_mud build that pulls `std_arena.zig` in as
module-instance 1, exposing a **pre-existing compiler emission bug**: the `_N` instance suffix is
applied to the struct typedef + locals (`zT_F22A6288_Arena_1`) but NOT to the function-signature
type refs (`zT_F22A6288_Arena` return) → `error: return type is an incomplete type` /
`conflicting types` in `std_arena_*.c`. mud_server + rogue_mud never use `std.arena`, so the
local mud_server `std.zig` omits the arena re-export. (json_parser builds std_arena at
instance 0 and is unaffected.)

---

## 2. Per-category migration summary

- **Single-file (12, commit `737e1966`):** hello, fibonacci, prime, mandelbrot, days_in_month,
  func_ptr_return, heapsort, quicksort, sort_strings, tco_factorial, tco_defer, tco_return_try.
  `std_debug.zig` wrappers (`print`/`printInt`) → `std.io.print/printInt`; direct-call mains
  (`func_ptr_return`, `quicksort`, `sort_strings`, `mandelbrot`, `tco_defer`) → `std.io.print*`.
  `sort_strings` call-site normalized `@ptrCast(*const c_char,…)` → `@ptrCast([*]const c_char,…)`.
  Created NOTES.md for the 3 tco_* (had none).
- **Multi-module (7, commit `f3077477`):** game_of_life (`__bootstrap_sleep_ms` →
  `std.io.sleepMs`, both `main.zig` + `main_lin.zig`), lzw (zero bootstrap refs — no change),
  lisp_interpreter/adv/curr (`__bootstrap_print*` → `std.io.print/printInt`), json_parser +
  workaround (`__bootstrap_print*`/`__bootstrap_write` → `std.io.print/printInt/write`; the F3
  `std_arena.zig`-alias import re-pointed to the canonical `@import("std.zig")` + `std.arena.
  create/alloc` in `arena.zig`/`file.zig`/`json.zig`).
- **Net (2, commit `ad0c71e7`):** mud_server (`std_debug.zig` `__bootstrap_print` →
  `std.io.print`; `net_runtime.c` externs STAY until F6), rogue_mud (I/O only per brief: main.zig,
  ui.zig, lib/rng.zig, test/repro_main.zig → `std.io.print/printInt/write`; the `plat_*` console
  externs STAY for F5; `__bootstrap_print_bytes` helper removed — call sites use `std.io.write`
  directly).
- **Runtime cleanup (commit below):** 6 wrappers removed from `zig_runtime.c:67-72` +
  `zig_runtime.h:12-18`; the 19 `@intCast` cast helpers (both .c defs + .h statics) repointed
  `__bootstrap_panic(msg, file, line)` → `std_panic(msg)` (m0564). F2 console builtins'
  emitted `__bootstrap_write(...)` calls repointed → `std_print_len(...)` in c89_emit.zig
  (DEVIATION D3 — REQUIRED compiler change: the F2 console emission arms
  c89_emit.zig:2087/:3227/:3267/:3317 were the sole remaining consumer of `__bootstrap_write`;
  analogous to the m0564 panic repoint). `io_builtin_test` + `console_builtin_test` (the F1/F2
  feature guards) migrated to `std.io` with local std copies (F3 precedent).

---

## 3. Gate results — 21-example matrix (final, `sf/build/out_release/zig1`)

| # | Example | dump | gcc | link | run | Notes |
|---|---------|------|-----|------|-----|-------|
| 1 | hello | 0 | 0 | 0 | 0 | "Hello, world!" |
| 2 | fibonacci | 0 | 0 | 0 | 0 | 55 |
| 3 | prime | 0 | 0 | 0 | 0 | 2357 |
| 4 | mandelbrot | 0 | 0 | 0 | 0 | art |
| 5 | days_in_month | 0 | 0 | 0 | 0 | output byte-identical to pre-F4 (known format quirk) |
| 6 | func_ptr_return | 0 | 0 | 0 | 0 | "10 + 5 = 15\n10 - 5 = 5" |
| 7 | heapsort | 0 | 0 | 0 | 0 | 135671112131520 |
| 8 | quicksort | 0 | 0 | 0 | 0 | sorted asc/desc |
| 9 | sort_strings | 0 | 0 | 0 | 0 | sorted strings |
| 10 | tco_factorial | 0 | 0 | 0 | 0 | "fact(10) = 3628800\ndeep ok" (goto z_bb_0 present) |
| 11 | tco_defer | 0 | 0 | 0 | 0 | pre-existing quirk: printInt values print 0, D twice (unchanged); order shifted (buffering unification) |
| 12 | tco_return_try | 0 | 0 | 0 | 0 | "count(10) = 10\ncount(100000) = 100000" |
| 13 | game_of_life | 0 | 0 | 0 | 0 | glider 100 gen, output md5 `fcbf7e7c…` byte-identical; ~10s (real usleep) |
| 14 | lzw | 0 | 0 | 0 | 0 | no bootstrap refs, unchanged |
| 15 | lisp_interpreter | 0 | 1 | 1 | — | PRE-EXISTING `zT_N` builtins.zig lowerer defect (dumps 12 .c; gcc fails) |
| 16 | lisp_interpreter_adv | 0 | 0 | 0 | 0 | runs |
| 17 | lisp_interpreter_curr | 0 | 0 | 0 | 0 | output byte-identical to pre-F4 |
| 18 | json_parser | 0 | 0 | 0 | 0 | output md5 `d90e7828…` byte-identical (needs test.json in CWD) |
| 19 | json_parser_workaround | 0 | 0 | 0 | 0 | `{}` tag-print quirk unchanged |
| 20 | mud_server | 0 | 0 | 0 | 124 | "MUD server listening on port 4000" — byte-identical (timeout = boot, server) |
| 21 | rogue_mud | 0 | 0 | 1 | — | gcc-clean (22 modules); link fails on exactly the 5 documented `plat_*` console stubs (D4, std-lib-deferred; console = F5) |

**18/21 end-to-end working (same set as post-F3 — no example regressed).** Zero
`__bootstrap_*` in all 21 example `.zig` sources. TCO gates (`goto z_bb_0;`) hold for the 3
tco_* examples.

**Corpus gate (compile-only, `gcc -c`):** 239 dirs measured, **OK=232 / FAIL=3 / green-guards=4 /
ICE=0 / CRASH=0** — the 3 FAILs (`field_store_drop`, `test_stub_0`, `self_embed_optional_cycle`)
and 4 green-guards are exactly the documented set; no new corpus FAIL.

---

## 4. MD5 gates (4) — all RE-BASELINED with runtime proof (AMENDMENT B)

| Entry | Pre-F4 | New (F4) | Runtime proof |
|---|---|---|---|
| mud_server/main.zig | `6c0a83f1…` | `ecd4086925e81c872abd1c32e7ce929e` | "MUD server listening on port 4000" rc=124, identical |
| game_of_life/main.zig | `0d8f0092…` | `b246a2fecc0b5ff4402912c49970cdae` | glider md5 `fcbf7e7c…` identical |
| lisp_interpreter_curr/main.zig | `a12f2fce…` | `141994cc81ab4bbb89722b7d30af419d` | REPL output diff empty |
| json_parser/main.zig | `ff9b880c…` | `f50ce1e6800d9e1365c019e46ac61292` | output md5 `d90e7828…` identical |

---

## 5. zig_runtime.c/.h cleanup

- Removed the 6 example-facing wrappers (`__bootstrap_print`, `__bootstrap_print_int`,
  `__bootstrap_print_char`, `__bootstrap_panic`, `__bootstrap_write`, `__bootstrap_sleep_ms`) from
  `zig_runtime.c:67-72` + `zig_runtime.h:12-18`.
- **Panic repoint (m0564):** all 19 `__bootstrap_<DST>_from_<SRC>` cast helpers (the .c defs AND
  the .h static copies — the header statics are what emitted C actually uses) now call
  `std_panic("integer cast overflow in @intCast")` directly; `__bootstrap_panic` is gone.
  Verified: `@intCast(i32, 2147483648)` → `panic: integer cast overflow in @intCast` (rc=134).
- KEPT: the 19 cast helpers, `std_panic` + `std_print*` family (compiler `print_str`/`print_val`
  LIR targets), legacy `std_checked_cast_*`, `arena_alloc_default`/`zig_default_arena` decls.
- `std_io.zig` uses the F1 builtins → emitted C calls `putchar`/`fwrite(stdout)`/`getchar` (libc
  stdio). Mixed-buffering note (F1 concern 1) resolved: the examples' write path is now unified
  through libc stdio.

---

## 6. NOTES.md / docs updated `[updated: 2026-08-08]`

- **NOTES.md:** all 21 examples (MD5s refreshed; F4 migration notes; tco_* created; rogue_mud
  module count 20→22; mud_server arena-omission note).
- **repro/mi_matrix/EXPECTED_FAIL.md:** F4 note (21-example matrix unchanged at 18/21; corpus
  accounting; io/console builtin-test repro migration).
- **sf/docs/tech_docs/00, 07, 08:** headers + 07 §Bootstrap-to-Builtin Mapping rewritten for the
  F4 removal/repoint.
- **docs/sf/QUICK_REF.md:** MD5 table re-baselined (4 rows) + re-baseline note.

---

## 7. Commits

1. `737e1966` — feat: std.zig/std_io.zig + migrate 12 single-file examples off `__bootstrap_*`
2. `f3077477` — feat: migrate 7 multi-module examples to std.io (gol sleepMs, lisp/json print, arena->std.arena)
3. `ad0c71e7` — feat: migrate net examples to std.io (mud_server print, rogue_mud I/O; console/sockets stay F5/F6)
4. (runtime cleanup: zig_runtime.c/h, c89_emit.zig console repoint, io/console builtin-test repro
   migration, EXPECTED_FAIL, tech docs 00/07/08, QUICK_REF)

---

## 8. Concerns

1. **DEVIATION D1 (`@import("std")` vs `@import("std.zig")`):** bare `@import("std")` needs an
   import-resolver search-path feature (module_registry.zig `moduleResolverAddSearchDir` is
   never called); F4 used per-example local `std.zig` copies (F3 precedent). Future compiler task
   to add the search path, then drop the copies.
2. **DEVIATION D2 (mud_server std.zig omits `arena`):** pulling `std_arena.zig` into the rogue_mud
   build as module-instance 1 exposes a pre-existing emitter bug (`_N` instance suffix on the
   struct typedef but not the fn-signature type ref → `return type is an incomplete type`).
   Not triggered at instance 0 (json_parser). Should be tracked as a compiler defect (or avoided
   by the F3 multiple-arena refactor note).
3. **DEVIATION D3 (c89_emit.zig change REQUIRED):** the F2 console builtins emitted
   `__bootstrap_write(...)` calls (c89_emit.zig:2087/:3227/:3267/:3317) — the wrapper's sole
   remaining consumer. Repointed to `std_print_len(...)` (a STAY function). This is the m0564
   precedent (compiler-internal consumer repoint) applied to `write`.
4. **`emitZigRuntimeC` (c89_emit.zig:5172) is dead code** that still emits the old
   `__bootstrap_*` definitions — never called; left as reference-only (comment at :5399).
5. **`extern_c.zig`/`extern_c_z98.zig` still declare `__bootstrap_print`/`__bootstrap_print_int`**
   (I-RT "test externs stay") — `main_exp.zig`/`test_a.zig` call them but are not built by any
   script; they would fail to LINK if ever built. Out of scope.
6. **tco_defer output order shifted** under redirection (PAL raw write → libc stdio unification);
   values still print 0 (pre-existing TCO+defer lowerer quirk). days_in_month byte-identical.
7. **Corpus dir count 239** vs EXPECTED_FAIL's "230 manifest + 7 tracked = 237": the F1/F2
   `io_builtin_test` + `console_builtin_test` dirs (now migrated) are not in the manifest tally;
   both classify OK.
8. json_parser still carries the dead `zig_default_arena` extern (`main.zig:10`) — harmless (the
   emitted C shadows it with a local), out of scope.
