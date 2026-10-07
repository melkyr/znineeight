# Task 2 — zig0-era workaround / boxing census

Plan: `docs/superpowers/plans/2026-10-06-zig1-live-set-reduction-plan.md` (Task 2)
Spec: `docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md` (§Workstream 2)
Seed: `/tmp/liveset_seed/zig1_5_clean` md5 `2293f756a8250351740cf6acde194d17` (Task 0 closure hop1==hop2).
All probes are throwaway files under `/tmp/probes/`; **no `sf/src` file was touched**. CWD = repo root,
seed command recorded per row as `seed --dump-c89 <probe>` (`timeout 120`).

A candidate is **enumerated** as: (a) an `AGENTS.md` §1.3 Z98 limitation workaround; (b) a
`zig0`/`bootstrap`-named comment in the `sf/src` closure; (c) a pointer-boxing site (`*T` struct
field where an inline `T` might replace the indirection).

Verdicts: **still-blocked** (direct construct rejected or mis-emits) / **now-removable**
(accepted *and* emits valid C) / **removable-with-caveat** (accepted but semantics/text/emission risk).

Byte delta is the expected **touched-RSS** delta of the removal (arena carve that is touched), not
churn/carve. All removals also move the self-emission fixed point (emitted text changes) unless noted.

---

## Table A — `AGENTS.md` §1.3 Z98-limitation workarounds

| ID | Construct / workaround | Closure site(s) | Probe (in `/tmp/probes/`) | Seed verdict | Byte delta (RSS) | Risk |
|----|------------------------|-----------------|---------------------------|--------------|------------------|------|
| W1 | No generics (`anytype`, `@Type`); hand-written concrete hash maps | `util/hash.zig:23,131,222` (`U32ToU32Map`/`U64ToU32Map`/`U32ToU64Map`); enforcement `analyzer.zig:430,508`; `type_resolver.zig:2273` | `l1_anytype.zig`, `l13_type_builtin.zig` | **still-blocked** — `error[16]: anytype not supported in Z98`; `fn f(comptime T: type)` → parse error `error[2000]` | 0 | n/a (not removable) |
| W2 | No `@cImport` | none in closure | `l4_cimport.zig` | **still-blocked** — `error[3000]: unsupported builtin function` | 0 | n/a |
| W3 | No `@cInclude` in zig0 mode → bare `extern fn` | `extern_c.zig:1-3` | `l3_cinclude.zig` | **now-removable** — rc 0; emits `#include "stdio.h"`; `-o` + `build_target.sh` builds rc 0. (std modules `std_file/std_net/std_os/std_stdin/std_time` already use `@cInclude`.) | ~0 | Med: changes the compiler's own emitted C; header portability; nil RSS |
| W4 | No `comptime` beyond basic folding | none in closure (compiler hand-rolls folding in `comptime_eval.zig`) | `l2_comptime.zig` | **still-blocked** — `comptime { … }` → `error[2000]` parse error | 0 | n/a (this is *why* `comptime_eval.zig`/`comptimeFoldTable` exist — keep) |
| W5 | Strict `i32` ↔ `usize`; always `@intCast` | pervasive (thousands of `@intCast`) | `l5_implicit_coerce.zig`, `l5b_usize_to_i32.zig` | **now-removable (syntactic)** — both directions rc 0; emits `u = i;` / `i = u;` implicit C89 conversion; `-o` build rc 0 | 0 | Med: sign-change semantics; ~thousands-site text diff moves fixed point |
| W6 | No pointer captures (`if (opt) \|*p\|`) | no workaround sites found in closure | `l6_ptr_capture.zig` | **still-blocked** — `error[2000]` parse error at `\|*p\|` | 0 | n/a |
| W7 | `switch` requires `else` | pervasive (enforced) | `l7_switch_no_else.zig` | **still-blocked by design** — `error[3068]: switch must have an 'else' prong` | 0 | n/a (deliberate Z98 rule, not a zig0 wart) |
| W8 | No method syntax (`x.f()`) | none in closure | `l8_method_syntax.zig`, `l8b_method_only.zig` | **still-blocked** — `fn` inside `struct` → `error[2000]` | 0 | n/a |
| W9 | `std.debug.print` requires tuple `.{}` | not in the compiler closure (zero-std import graph) | not probed | not-probed (std API; `std.debug` base unresolved in isolated probe) | 0 | n/a for `sf/src` |
| W10 | Global aggregate constants via `pub var` + `init()` | `token.zig:146-194` (`keyword_table`, `initKeywordTable`) | `l9_global_const_agg.zig`, `l15_const_agg_table.zig` | **removable-with-caveat** — simple `const g: S = S{…}` rc 0 **and builds**; but the `keyword_table` shape (array of structs with `[]const u8` + string literals) is accepted frontend (rc 0) yet emits **invalid C** (`variable or field '_0' declared void`, `'zT_1' undeclared`, `assignment to expression with array type`) → **effectively still-blocked for that shape** | ~456 B perm **only if** the array-of-slices shape is fixed; simple struct const 0 | High for keyword_table shape: emission bug; fixed-point move |
| W11 | Slice bounds inline `@intCast` + math → precompute to locals | no remaining inline sites found (`grep '\[@intCast…\.\.'` = 0) | `l10_slice_inline_cast.zig` | **now-removable** — rc 0; `-o` + build rc 0 | 0 (no sites) | none |
| W12 | `continue` in `while : (expr)` with fn-return condition → `if-else {}` no-op chain | `semantic_analyzer.zig:4523` (`if (bt == TYPE_NORETURN) {}`), `:4542` (`else if (bt == unified) {}`) | `l11_continue_while.zig`, `l11_rt.zig` | **now-removable** — rc 0; emitted CFG `z_bb_5(continue) → z_bb_4(increment) → z_bb_1`; runtime probe prints `0 1 3 4` (rc 0) — correct | 0 | Low: 2 small sites; fixed-point move |
| W13 | String-literal → `[]const u8` workaround (`var s: []const u8 = "…"`) | **3090** occurrences in closure | `l12_string_literal_slice.zig` | **now-removable** — `f("hi")` to `[]const u8` param rc 0; emits correct `{ptr,len}` materialization; `-o` build rc 0 | ~0 (local slice temps are stack, 8 B each; no arena/RSS) | High diff: 3090-site emitted-text change + fixed-point move |
| W14 | **Flagship:** `Token` 24 B → 16 B packed (FIXME "restore packed struct once zig1 can self-host") | `token.zig:131-139` | `p_token_packed.zig`, `f2_packed_union_field.zig`, `f3_packed_u32.zig`, `f4_packed_union_u64.zig` | **STILL-BLOCKED** — packed struct with a tagged-union field → `error[3000]: packed struct fields must be bool or an integer type (uN/iN); this field type is not allowed`; `span_start: u32` in a packed struct → `error[3000]: packed struct field width must be <= 31 bits (u32/i64 etc. packed fields are not supported yet)`; `packed union` with `u64`/`f64` member → `error[3000] width <= 31 bits` | 8 B/`Token`; live `Token` count is a handful (parser `la:[3]` + `eof_tok` + `last_tok`, streaming lexer) → **≤~80 B**, i.e. ≈0 RSS | n/a (cannot adopt) |
| W17 | Module-level global array subscripted stores dropped → 6 scalar `var`s | `spill_store.zig:36-48` (`g_s_ast…g_s_extra`) | `w17_global_array_store.zig` | **now-removable** — `g[i] = v;` on a module-level `[6]u8` rc 0; emits `zG_g[zT_3] = v;`; `-o` build rc 0 | 6 B (6×u8, no size change); ~0 RSS | Low–Med: global-name/emitted-text move |

### Controls (PACK-AGG constructs that **are** accepted — establish the feature boundary)

| Probe | Construct | Verdict |
|-------|-----------|---------|
| `c1_packed_basic.zig` | `packed struct { a: u3, b: u5 }` | rc 0 |
| `c2_packed_enum.zig` | `enum(u3)` field in a packed struct | rc 0 (PACK-AGG landed) |
| `c3_packed_nested.zig` | nested packed-struct field | rc 0 (PACK-AGG landed) |
| `c4_packed_union.zig` | `packed union { a: u4, b: u12 }` | rc 0 (PACK-AGG landed) |

**Boundary:** packed aggregates are **bitfield-only**: every leaf must be `bool`/`uN`/`iN` with
width ≤ 31 bits, or a nested packed struct/union. A **tagged union field**, a **`u32`** field, and a
**`packed union` member wider than 31 bits** are all rejected. The `Token` 16 B layout needs exactly
a `u32` (`span_start`) and an 8-byte union payload → **not reachable** with the landed feature.

---

## Table B — `zig0`/`bootstrap`-named comments in the closure

| Site | Text (abridged) | Class |
|------|-----------------|-------|
| `token.zig:131-133` | "Desired packed layout (16 bytes) rejected by zig0 for structs with union fields. … Restore packed struct once zig1 can self-host." | Workaround (W14) — **still-blocked** |
| `spill_store.zig:36-38` | "the Z98/zig0 emitter does not support subscripted stores into module-level global arrays (they are dropped), so the flag is 6 scalar module vars, not one array." | Workaround (W17) — **now-removable** |
| `semantic_analyzer.zig:4064-4065,4173` | "Mirrors zig0's `TypeChecker::isLValueConst`" | Reference/parity note, not a workaround |
| `async_analysis.zig:19` | "bootstrap root from a submodule makes the self-emitter register main.zig as a…" | Design note, not removable |
| `lir.zig:153` | "replaces the emitter's `__bootstrap_<dst>_from_<src>` helper selection" | Emitted-C compat note |
| `emit_support.zig:217,334-335,372-…,519-520,566-663` | Emitted C strings containing `__bootstrap_print*` / `__bootstrap_*_from_*` "backward compat aliases … REMOVED (F4)" and "zig0-oracle header" | These are bytes the compiler **emits** (compat header text), not Z98 limitation workarounds; not candidates |
| `extern_c.zig:2-3` | `pub extern fn __bootstrap_print(_int)` (bare externs) | Workaround (W3) — **now-removable** |

---

## Table C — pointer-boxing sites (`*T` struct fields / hand-boxed headers)

Raw inventory: **252** `*T` declarations in the closure (`grep '^\s+name: \*T'`). The large majority
are **function parameters / context pointers** (registries, arenas, stores, interners) — shared
mutable singletons; an inline `T` would duplicate state or break the `&parent.field` aliasing that
the emitters rely on, so they are **not removable** without redesign. Per the spec, a *general*
boxing / array-vs-scalar layout sweep is explicitly **deferred / out-of-scope**.

The concrete **hand-boxed** objects (one arena allocation + `@ptrCast`, not an embedded header):

| ID | Boxed object | Site | Alloc size | Byte delta if inlined | Risk |
|----|--------------|------|-----------:|----------------------:|------|
| B1a | `U8ArrayList` header (`Lexer.string_buf`) | `lexer.zig:26,31-32` | 16 B | −16 B + inline header (net ≈ −4 B pointer + pad) | Low Med: aliasing/fixed-point |
| B1b | `DiagnosticArrayList` header (`DiagnosticCollector.diagnostics`) | `diagnostics.zig:434,455-456` | 16 B | ≈ same as above | Low Med |
| B1c | `SourceFileArrayList` header (`SourceManager.files`) | `source_manager.zig:76,84-85` | 16 B | ≈ same | Low Med |
| B2 | `GrowableSand` boxes (arena singletons: `SourceManager.fault`, `main` `type_db_arena`, 5 tier arenas + parser/src arenas) | `source_manager.zig:86-88`; `allocator.zig:272-276`; `import_resolver.zig:57-65`; `main.zig:200` | ≈ `SandSegment`+`Sand`+views | not removable (arena identity/`view` aliasing) | n/a |
| B3 | `*U32ArrayList` etc. headers are **embedded** in owners (e.g. `LirFunction.switch_cases`, passed as `&func.switch_cases`) | `lir.zig:508`; `c89_emit.zig:2999` | 0 (not boxed) | n/a | n/a |
| B4 | `test_runner.zig:64` (`TestResultArrayList`) | `test_runner.zig:64` | 16 B | out of closure (test-only) | n/a |

**Boxing byte total:** the only in-closure hand-boxed list headers are **3 × 16 B = 48 B**
(`lexer`, `diagnostics`, `source_manager`); inlining them returns ≲ the 4-byte pointer each, i.e.
**≈0 RSS**. No boxing site is a meaningful RSS lever.

---

## Probe index / commands (all `/tmp`, throwaway)

```
# accepted/validated rows use `-o` + the emitted build target:
mkdir -p /tmp/probes/out_<p>
timeout 120 /tmp/liveset_seed/zig1_5_clean -o /tmp/probes/out_<p> /tmp/probes/<p>.zig
( cd /tmp/probes/out_<p> && timeout 120 sh build_target.sh linux prog )   # build (and run) rc
# rejected rows: acceptance only
timeout 120 /tmp/liveset_seed/zig1_5_clean --dump-c89 /tmp/probes/<p>.zig >/dev/null
# runtime proof of the `continue` rewrite:
timeout 120 /tmp/probes/out_l11_rt/prog     # prints "0 1 3 4"
```

Full accepted-and-built set: `l3_cinclude`, `l5_implicit_coerce`, `l9_global_const_agg`,
`l10_slice_inline_cast`, `l11_continue_while` (+`l11_rt`), `l12_string_literal_slice`,
`w17_global_array_store` (all `-o`/build rc 0). **`l15_const_agg_table` accepted (rc 0) but `-o`
build rc 1** (emitted `zig_special_types.h` / `.c` invalid) — the keyword_table-shape caveat.

## Byte-delta roll-up (removals only)

| Rank | Item | Expected touched-RSS | Notes |
|-----:|------|---------------------:|-------|
| 1 | W10 `keyword_table` → `const` | ~456 B perm (blocked by emission bug) | only if array-of-slices const is fixed |
| 2 | B1 boxed list headers (3) | ≈0 (≤48 B gross) | aliasing caveat |
| 3 | W17 6 spill scalars → `[6]u8` | 6 B (~0) | hygiene |
| — | W3/W5/W11/W12/W13 | 0 | accepted, text-only changes; W13 = 3090 sites |
| — | W14 flagship packed `Token` | 8 B/Token, ≤~80 B live | **still-blocked** |
| — | W1/W2/W4/W6/W7/W8 | 0 | **still-blocked** |
