# Task 2 — zig0-era workaround / boxing re-evaluation (READ-ONLY) report

Plan: `docs/superpowers/plans/2026-10-06-zig1-live-set-reduction-plan.md` (Task 2)
Spec: `docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md` (§Workstream 2, §Evidence)
Census: `workaround-census.md` (every candidate + probe + verdict + byte delta + risk)
Baseline: `task-0-report.md`; Task 1: `task-1-report.md` + `allocation-census.md`.

Branch `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no seed rotation**, **no
dump-MD5 re-baseline**. All probes are throwaway files under `/tmp/probes/`; no `sf/src` file was
touched; the two `.zig1_*.tmp` spill files found in the repo root were removed (untracked, transient).
Measurement seed: `/tmp/liveset_seed/zig1_5_clean` md5 `2293f756a8250351740cf6acde194d17`.

Binding metric = peak **RSS**. Every row below was tested by compiling a tiny probe with the seed
(`timeout 120`), and — for every "now-removable" row — built via the emitted `-o` tree +
`build_target.sh` to prove the **emitted C89 is valid** (frontend acceptance is *not* sufficient:
W10 proves the emitter can accept a construct and still emit invalid C).

---

## Headline

- **Flagship `Token` 24 B → 16 B is STILL BLOCKED.** PACK-AGG landed *bitfield-only* packed
  aggregates: leaves must be `bool`/`uN`/`iN` with **width ≤ 31 bits**, or a nested packed
  struct/union. A **tagged-union field**, a **`u32` field**, and a **`packed union` member wider
  than 31 bits** are all rejected with `error[3000]`. The 16 B `Token` layout needs a `u32`
  (`span_start`) and an 8-byte union payload → not expressible. `F-TOKEN` cannot proceed.
- **Most §1.3 workarounds are now syntactically removable but are ~0-byte RSS levers.** Removing
  them is code hygiene + a self-emission fixed-point move, not an RSS win.
- **The only memory-relevant zig0-era scaffolding stays:** hand-written concrete hash maps (W1)
  and the hand-rolled `comptime_eval.zig` constant folder (W4) exist *because* generics/`comptime`
  are still rejected — so Task 3 must keep `F-HASHMAP` and `comptimeFoldTable`, not treat them as
  removable workarounds.
- **Top-3 removable by byte estimate:** W10 `keyword_table` `pub var`+`init()` → `const` ≈ **456 B**
  perm (but only once the array-of-slices const emission bug is fixed); B1 three hand-boxed
  ArrayList headers ≈ **48 B gross / ≈0 net**; W17 six spill scalars → `[6]u8` = **6 B**. All ≈0 RSS.

---

## Step 1–2 — enumeration + seed probes

23 candidates probed (`/tmp/probes/`, 30+ compile runs). Full detail in `workaround-census.md`
Tables A/B/C. Constructs actually exercised with the seed:

### Flagship (W14) — packed `Token`

`token.zig:131-139`:

```
// FIXME: Desired packed layout (16 bytes) rejected by zig0 for structs with union fields.
// Actual size: 24 bytes (TokenValue union forces 8-byte alignment).
// Restore packed struct once zig1 can self-host.
pub const Token = struct { kind: TokenKind, span_start: u32, span_len: u16, value: TokenValue };
```

Probes (`p_token_packed.zig`, `f2_packed_union_field.zig`, `f3_packed_u32.zig`,
`f4_packed_union_u64.zig`), all `rc=2`:

```
error[3000]: packed struct field width must be <= 31 bits (u32/i64 etc. packed fields are not supported yet)   # span_start: u32
error[3000]: packed struct fields must be bool or an integer type (uN/iN); this field type is not allowed in a packed struct   # value: TokenValue
error[3000]: packed union field width must be <= 31 bits (u32/i64 etc. are not supported yet)   # packed union { int_val: u64, ... }
```

Controls that **do** pass (`c1`–`c4`, rc 0) fix the exact boundary: `packed struct{u3,u5}`,
`enum(u3)` packed field, nested packed struct, `packed union{u4,u12}`. So PACK-AGG works as
advertised, but its model is **bitfields**, which structurally excludes the 16 B `Token` (a 32-bit
span and a 64-bit tagged payload).

**Byte reality even if it were adoptable:** the production lexer is **streaming**
(`parserInitStreaming`, `lexerNextToken`), so live `Token` objects are only the parser's `[3]Token`
lookahead + `eof_tok` + `last_tok` (+ a few stack temps) — well under 100 B total. `main_dump.zig`
(not in the 45-module closure) is the only path that materializes a token array. So the flagship
would be a **layout/correctness** fix, **≈0 RSS**.

### §1.3 workarounds — verified now-removable (accepted **and** valid C)

| ID | Probe | Evidence |
|----|-------|----------|
| W3 `@cInclude` instead of bare extern | `l3_cinclude.zig` | rc 0; emitted `#include "stdio.h"`; `-o` build rc 0 |
| W5 implicit `i32`↔`usize` | `l5_implicit_coerce.zig` / `l5b_usize_to_i32.zig` | rc 0; emits `u = i;` / `i = u;`; build rc 0 |
| W10 simple global aggregate `const` | `l9_global_const_agg.zig` | rc 0; build rc 0 |
| W11 slice bounds inline cast+math | `l10_slice_inline_cast.zig` | rc 0; build rc 0 (no remaining sites: `grep '\[@intCast…\.\.'` = 0) |
| W12 `continue` in `while : (expr)` | `l11_continue_while.zig` / `l11_rt.zig` | rc 0; CFG `continue→increment→loop`; runtime prints `0 1 3 4`, rc 0 |
| W13 string-literal → `[]const u8` | `l12_string_literal_slice.zig` | rc 0; emits `{ptr,len}` materialization; build rc 0 |
| W17 global array subscripted store | `w17_global_array_store.zig` | rc 0; emits `zG_g[zT_3] = v;`; build rc 0 |

### §1.3 workarounds — verified still-blocked

| ID | Probe | Error |
|----|-------|-------|
| W1 generics `anytype` | `l1_anytype.zig` | `error[16]: anytype not supported in Z98` |
| W1 `@Type`/`comptime T: type` | `l13_type_builtin.zig` | `error[2000]` parse |
| W2 `@cImport` | `l4_cimport.zig` | `error[3000]: unsupported builtin function` |
| W4 `comptime {}` | `l2_comptime.zig` | `error[2000]` parse |
| W6 pointer capture `\|*p\|` | `l6_ptr_capture.zig` | `error[2000]` parse |
| W7 switch without `else` | `l7_switch_no_else.zig` | `error[3068]: switch must have an 'else' prong` |
| W8 method syntax | `l8_method_syntax.zig`, `l8b_method_only.zig` | `error[2000]` parse |

W7 is now a **deliberate Z98 rule** (`error[3068]`), not a zig0 wart — it is not a removal
candidate. W1 and W4 are the load-bearing blockers behind the two biggest *legitimate* allocation
levers found by Task 1 (hash-map grow ~0.5–0.9 M; `comptimeFoldTableGrow` ~0.4–0.7 M).

### The trap — W10 global aggregate constants

The `keyword_table` shape hits a **latent emission bug**. `l15_const_agg_table.zig`
(`const table: [2]KE = .{ … }` with `name: []const u8` fields = `"const"`,`"var"`) is **accepted**
(`--dump-c89` rc 0) but the emitted C is invalid:

```
zig_special_types.h:37: error: variable or field '_0' declared void
l15_const_agg_table_*.c:12: error: 'zT_1' undeclared
l15_const_agg_table_*.c:14: error: assignment to expression with array type
```

So the AGENTS §1.3 "global aggregate constants" workaround is **not safely removable for the
keyword-table shape** — only for simple scalar-field structs (`l9`). A `pub var`+`init()` →
`const` fix for `token.zig` would need the emitter fixed first.

### Boxing sites

252 `*T` declarations in the closure are dominated by **shared context/registry/singleton
parameters** (not removable — aliasing/shared mutation). The only in-closure *hand-boxed* list
objects are **3 × 16 B** ArrayList headers (`lexer.zig:31`, `diagnostics.zig:455`,
`source_manager.zig:84`); most `*ArrayList` fields are **embedded** in owners (e.g.
`LirFunction.switch_cases`, `c89_emit.zig:2999`) and passed as `&field`. Inlining the 3 boxed
headers would reclaim ≲ the 4-byte pointer each → **≈0 RSS**. The spec already defers a general
boxing/layout sweep; this task confirms it holds no RSS lever.

---

## Step 3–4 — workaround/boxing table + outputs

The full per-item table is in **`workaround-census.md`** (Table A workarounds, Table B zig0-named
comments, Table C boxing). Byte-delta roll-up (touched-RSS only):

| Rank | Candidate | Verdict | Touched-RSS | Risk |
|-----:|-----------|---------|------------:|------|
| 1 | W10 `keyword_table` → `const` | removable-with-caveat (emission bug) | ~456 B perm | High for the array-of-slices shape |
| 2 | B1 3 hand-boxed list headers | removable-with-caveat (aliasing) | ≤48 B gross, ≈0 net | Low–Med |
| 3 | W17 spill scalars → `[6]u8` | now-removable | 6 B | Low–Med |
| — | W13 string-literal (3090 sites) | now-removable | 0 | High diff/fixed-point |
| — | W3 / W5 / W11 / W12 | now-removable | 0 | Med / Med / none / Low |
| — | **W14 packed `Token`** | **still-blocked** | 8 B/Token, ≤~80 B live | n/a |
| — | W1 / W2 / W4 / W6 / W7 / W8 | still-blocked | 0 | n/a |

**No workaround removal is a meaningful RSS lever.** The honest ranking is hygiene-only; the
flagship cannot be adopted. Task 3 should treat W10/W13 as text-churn candidates (they move the
self-emission fixed point), not as savings, and should explicitly keep the load-bearing
still-blocked workarounds (W1 hash maps, W4 `comptime_eval`) because their underlying language
features remain unavailable — which is exactly why Task 1's top allocation levers live there.

---

## Concerns

1. **Frontend acceptance ≠ valid emission (proven by W10).** Every "now-removable" verdict here was
   additionally built through the emitted `-o` tree; the W10 keyword-table shape shows the seed can
   accept a construct and emit C that gcc rejects. Any future fix must gate on the emitted C, not
   `--dump-c89` rc alone.
2. **The flagship is blocked by the *shape* of PACK-AGG, not an unlanded feature.** PACK-AGG is
   bitfield-based (≤31-bit leaves, no tagged unions). Re-floating `F-TOKEN` needs either (a) a
   packed-struct representation that admits wide/tagged members, or (b) a non-packed `Token` resize
   (e.g. reorder fields / split the union) — but (b) would change emitted C and is a *layout*
   change, which the spec excludes from this spike. It also returns ≈0 RSS (streaming lexer).
3. **Removal cost is dominated by textual churn, not bytes.** W13 alone is 3090 sites and W5 is
   thousands of `@intCast`s; both move the self-emission fixed point. They are not worth fixing for
   RSS and should only be pursued as deliberate refactors.
4. **W3 (`@cInclude`) is only about the compiler's own `extern_c.zig`.** The std modules already use
   `@cInclude`; the compiler's zero-std closure deliberately uses bare `extern fn`. Switching would
   change the compiler's own emitted C / portability for ~0 bytes.
5. **RSS estimates are first-order and ≈0 for all removals**; the binding judgement (Task 3) must
   not treat any of these as a lever. The only large live-set items remain Task 1's resident
   allocation candidates (hash maps / comptime fold / AST slots).
6. **Throwaway artifacts are in `/tmp/probes/` only** (30+ `.zig` probes, `.c`/`.err`, `out_*/`
   trees). Two untracked `.zig1_*.tmp` root spill files were deleted; the pre-existing untracked
   root strays listed in `task-0-report.md` were left untouched. Only the two Task-2 docs are
   staged with `git add -f`.

## Commands used (evidence)

```
# acceptance
timeout 120 /tmp/liveset_seed/zig1_5_clean --dump-c89 /tmp/probes/<p>.zig >/tmp/probes/<p>.c 2>/tmp/probes/<p>.err ; echo rc=$?
# acceptance + valid-emission + runtime (now-removable rows)
rm -rf /tmp/probes/out_<p> && mkdir -p /tmp/probes/out_<p>
timeout 120 /tmp/liveset_seed/zig1_5_clean -o /tmp/probes/out_<p> /tmp/probes/<p>.zig
( cd /tmp/probes/out_<p> && timeout 120 sh build_target.sh linux prog ) && [ -x prog ] && ./prog
# enumeration
grep -rniE "zig0|bootstrap|FIXME|workaround" sf/src/*.zig | grep -v /tests/
grep -rnE "^\s+[a-z_][a-zA-Z0-9_]*: \*[A-Za-z_]" sf/src/*.zig | grep -v /tests/ | wc -l   # 252
grep -rnE "var [a-zA-Z_][a-zA-Z0-9_]*: \[\]const u8 = \"" sf/src/*.zig | grep -v /tests/ | wc -l   # 3090
```
