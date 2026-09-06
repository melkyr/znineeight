# Arbitrary-Width Integer Types (uN/iN) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `u1..u64` / `i1..i63` first-class Z98 integer types with full wrap/sign arithmetic semantics (backend-agnostic width in the type layer; C89 emitter owns carrier/mask/sign-extend), turning R7 `int_arbitrary_width_xmod` and the new INTWIDTH fixtures GREEN and unblocking PACK.

**Architecture:** Add semantic `width_bits`/`is_signed` to `Type`; introduce `intWidthBits`/`intIsSigned` helpers and replace every semantic size-as-width compare and `size*8` derivation; register `uN`/`iN` names with clean bad-width diagnostics; the C89 emitter maps each width to the smallest power-of-2 carrier and emits mask/sign-extend wrap for full-width semantics.

**Tech Stack:** Z98 self-hosted compiler (`sf/src/*.zig`), reference `/tmp/fx_subfolder/zig1` (md5 `c8f1b3d0`, std lib at `/tmp/fx_subfolder/lib`), gcc `-m32 -std=c89`, fixture classifier per `.superpowers/sdd/task-LANGWINS-report.md` Step-4.

Design spec: `docs/superpowers/specs/2026-09-06-arbitrary-width-ints-design.md` (operator-approved).

## Global Constraints

- **ZERO changes outside `sf/src`** except: new `repro/mi_matrix/*_xmod/` fixtures, `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, and the spec/plan docs. Never touch the four gate programs, `rogue_mud`, examples originals, goldens, `sf/build/`, `out_release/`.
- 4-MD5 gates are **expected to hold** (byte-neutral for non-uN programs): gol `302df36b`/lisp `3591bad9`/json `76056b97`/mud `846106ac`. If any moves, STOP-present (no silent re-baseline).
- Self-compile fixed point **will move** once `Type`/emission changes land → operator-ruled re-baseline at the battery task, never silent.
- RED-before-F: every new fixture is committed RED (verified on the current compiler) BEFORE its fix task.
- Backend-agnostic width: `width_bits`/`is_signed` are semantic; byte `size`/alignment/carrier are emission concerns. Do NOT bake `ceil(width/8)` into semantic decisions.
- Full wrap/sign semantics (operator decision). Existing power-of-2 types (`u8/i8/u16/i16/u32/i32/u64/i64`) must remain behavior-identical (width == size*8 for them; refactor must be semantics-preserving there).
- Z98 dialect in all new code: no anytype/@Type/method syntax; `@intCast` on width changes; `else` on non-exhaustive switches. D1 discipline: no bare cross-module comptime-const local-init decls; wrap in `@intCast(u32, ...)` where zig0 would drop them (and note any such site for review — the compiler's own source compiles under BOTH zig0 and zig1).
- Pre-existing dirty/untracked set never staged (2026-08-26 plan doc, `mnemoria/*`, `.zig1_*.tmp`, `build/`, `examples/z98/json_parser_upgraded/`).
- Reports accumulate in `.superpowers/sdd/task-INTWIDTH-report.md` (gitignored). Ledger `.superpowers/sdd/progress.md`. Memory `mnemoria --path .opencode/memory`, agent `intwidth-session`.
- Per-task report contract: status, files changed, RED/GREEN evidence (md5s), gate evidence, concerns. STOP-present on any divergence/blocker.

---

### Task 1 (I, record-only): Edit-point map + behavior-neutrality audit

**Files:**
- Record only: `.superpowers/sdd/task-INTWIDTH-report.md` header.

**Interfaces:**
- Produces: the exact per-site edit map the F tasks follow (each `size`-compare classified semantic vs emission), plus the power-of-2 behavior-neutrality proof sketch.

- [ ] **Step 1: Re-verify the census at current HEAD** (`git rev-parse --short HEAD` must be `c8a73bed`; reference md5 `c8f1b3d0`; confirm tree = pre-existing dirty/untracked set). Re-derive (fresh greps) the sites: `type_registry.zig` `Type` struct (~:60-71) + `registerPrimitive*` (~:272-285, :605-627); `type_resolver.zig` ident/name fall-through (~:695-735); `coercion.zig` int-widen compare (~:104); `semantic_analyzer.zig` int-peer width pick (~:686-689) + `@intCast`/annotation paths; `comptime_eval.zig` `size*8` uses (~:140) + `@sizeOf/@alignOf/@bitSizeOf` folds; `lower.zig` `@intCast` checked-cast table (~:1280-1294) + int-op lowering; `c89_emit.zig` carrier/width tables (`getCTypeName` :640-671, `intTypeByteWidth` :3679-3688, `globvarTypeScalarSize` :158-172, `intLitSuffixUns/Neg` :3621-3630, sat-lit :3823-3849, checked-cast helpers :4220-4293, `intConstTypeForValue` :3635). Record exact line numbers (they shift; re-verify during F).

- [ ] **Step 2: Classify every int compare.** For each `size`-compare in coercion/sema/int-peer: is it (a) a SEMANTIC width decision (must become `intWidthBits`), or (b) an EMISSION/layout decision (stays `size`)? For every `size*8`: is it deriving semantic width (→ `intWidthBits`) or computing a C-emission bit width? Produce a table: file:line → class (semantic/emission) → replacement. Any ambiguous site → STOP-present.

- [ ] **Step 3: Behavior-neutrality check.** Confirm that for the existing set `{u8,i8,u16,i16,u32,i32,u64,i64}` the replacement is identity: `width_bits == size*8` and the size-compares currently decide exactly what width-compares would decide at those widths. Note the one semantic trap: equal-byte-size but different-sign types (`u16` vs `i16`) — today they differ by signedness only, and `@intCast`/coercion already distinguishes them; record how signedness is represented today so `is_signed` is consistent.

- [ ] **Step 4: Report + ledger.** Map + classification + neutrality note. No commit, no edits.

---

### Task 2 (F, RED fixtures): Commit the INTWIDTH RED set

**Files:**
- Create: `repro/mi_matrix/intwidth_wrap_xmod/main.zig`
- Create: `repro/mi_matrix/intwidth_sign_extend_xmod/main.zig`
- Create: `repro/mi_matrix/intwidth_cast_xmod/main.zig`
- Create: `repro/mi_matrix/intwidth_introspect_xmod/main.zig`
- Create: `repro/mi_matrix/intwidth_full_xmod/main.zig`
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (v70→v71)

**Interfaces:**
- Produces: the committed RED guard set (each shows RED on the current compiler, non-GREEN contract). R7 `int_arbitrary_width_xmod` already exists (false-green today) — do NOT re-add it.

- [ ] **Step 1: Author each fixture** (Z98 dialect; `pub fn main() void`; stdout via `std.io.printInt`/`writeByte`; expected contracts from the spec §5/§6):

`intwidth_wrap_xmod/main.zig` — contract `0 0`:
```zig
const std = @import("std");

pub fn main() void {
    var a: u3 = @intCast(u3, 7);
    var b: u3 = @intCast(u3, 1);
    var w = a + b;
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte('\n');
    var x: u12 = @intCast(u12, 4095);
    var y: u12 = @intCast(u12, 1);
    var w2 = x + y;
    std.io.printInt(@intCast(i32, w2));
    std.io.writeByte('\n');
}
```

`intwidth_sign_extend_xmod/main.zig` — contract `true 1` (i7 -1 < 0; sign-extend through @intCast to i16):
```zig
const std = @import("std");

pub fn main() void {
    var n: i7 = @intCast(i7, -1);
    if (n < 0) std.io.writeStr("true\n") else std.io.writeStr("false\n");
    var wide: i16 = @intCast(i16, n);
    std.io.printInt(wide);
    std.io.writeByte('\n');
}
```

`intwidth_cast_xmod/main.zig` — contract `7 0 255` (truncate/mask @intCast(u3,255)→7; @intCast(u8,256)→0 via mask; widen u3→u8 keeps value):
```zig
const std = @import("std");

pub fn main() void {
    var t: u3 = @intCast(u3, 255);
    std.io.printInt(@intCast(i32, t));
    std.io.writeByte('\n');
    var c: u8 = @intCast(u8, 256);
    std.io.printInt(@intCast(i32, c));
    std.io.writeByte('\n');
    var u: u8 = @intCast(u8, 255);
    var w3: u8 = @intCast(u8, u);
    std.io.printInt(@intCast(i32, w3));
    std.io.writeByte('\n');
}
```

`intwidth_introspect_xmod/main.zig` — contract `3 1 2 4 8 1 7` (@bitSizeOf(u3)=3, @sizeOf(u3)=1, @sizeOf(u12)=2, @sizeOf(u20)=4, @sizeOf(u33)=8, @alignOf(u3)=1, @bitSizeOf(i7)=7 — values per spec §3.2/§5; each on its own line):
```zig
const std = @import("std");

pub fn main() void {
    std.io.printInt(@intCast(i32, @bitSizeOf(u3)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u3)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u12)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u20)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u33)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @alignOf(u3)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @bitSizeOf(i7)));
    std.io.writeByte('\n');
}
```

`intwidth_full_xmod/main.zig` — contract `0 -1` (u63 2^63-1 + 1 wraps to 0 on the 64-bit carrier; i63 -1 sign-extends through @intCast to i64):
```zig
const std = @import("std");

pub fn main() void {
    var a: u63 = @intCast(u63, 9223372036854775807);
    var b: u63 = @intCast(u63, 1);
    var s = a + b;
    std.io.printInt(@intCast(i64, s));
    std.io.writeByte('\n');
    var n: i63 = @intCast(i63, -1);
    std.io.printInt(@intCast(i64, n));
    std.io.writeByte('\n');
}
```

- [ ] **Step 2: Verify RED on the current compiler** (fresh dirs; classify per the authoritative recipe; the R7 `int_arbitrary_width_xmod` current class is the model — `u3` etc. hit void-fallback / `cannot declare variable of type void` or `unknown type`). Record the ACTUAL class per fixture (deterministic 3×; stderr md5s). Contracts are GREEN-time only (not forced now).

- [ ] **Step 3: EXPECTED_FAIL.md v70→v71** — add the 5 rows in the Langwins group (existing convention: row table + per-fixture RED-status bullets + Rule). Keep all prior sections verbatim. (R7 row already exists; leave it.)

- [ ] **Step 4: Commit.** Fixtures + EXPECTED_FAIL only (`git add -f` on the `.zig` fixture dirs; main.zig has no *.txt so no force needed unless .gitignore rules apply — check; the demo `.txt` precedent used `-f` but these are `.zig`, normal add is fine).

```bash
git add repro/mi_matrix/intwidth_wrap_xmod repro/mi_matrix/intwidth_sign_extend_xmod \
        repro/mi_matrix/intwidth_cast_xmod repro/mi_matrix/intwidth_introspect_xmod \
        repro/mi_matrix/intwidth_full_xmod repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "test: RED fixtures — arbitrary-width ints uN/iN (wrap/sign-extend/cast/introspect/full)"
```

- [ ] **Step 5: Report + ledger.**

---

### Task 3 (F): Type layer — width fields, uN/iN registration, helper refactor (byte-neutral)

**Files:**
- Modify: `sf/src/type_registry.zig`, `sf/src/type_resolver.zig`, `sf/src/coercion.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/comptime_eval.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig` (exact sites from Task 1 map)

**Interfaces:**
- Consumes: Task 1 edit map.
- Produces: width-aware type layer + uN/iN types that register/validate and carry `width_bits`/`is_signed`; semantic decisions switched to the helpers; **no behavior change for power-of-2 widths** (4-MD5 hold; self-compile still builds). Emission does NOT yet wrap uN ops (that is Task 4) — uN compile but wrap/mask semantics land next task.

- [ ] **Step 1: Add width fields to `Type`** (type_registry.zig ~:60-71). Add `width_bits: u8` and signedness. Prefer a single representation consistent with the existing int family; record the chosen layout (if it grows `Type` to 32B @align4 that is fine — fixed-point re-baseline is expected). Initialize width for ALL existing integer primitives (u8→8, i8→8 signed, u16→16, ..., u64→64, i64→64 signed; bool is NOT an int type — leave as-is).

- [ ] **Step 2: Add `intWidthBits`/`intIsSigned` helpers** (exported; used by every semantic consumer). Behavior for the power-of-2 family must equal today's `size*8` and signedness truth.

- [ ] **Step 3: Register `uN`/`iN` names.** In `type_resolver` name resolution (~:695-735): parse `u`/`i` + digits; validate (u 1..64, i 1..63); return the existing primitive if width already exists (`u8` etc.); else create/register a new integer Type with the right `width_bits`/`is_signed` and a C-carrier `size` (Task 1 map decides size assignment; spec §3.2). Invalid widths → clean `error[3000]` at the annotation site (reuse F-CLEANDIAG path so no void-fallback for valid uN/iN, and no "unknown type" for them).

- [ ] **Step 4: Replace semantic width decisions with the helpers.** Apply Task 1's classified map: coercion widen compare, sema int-peer pick, comptime `size*8` width derivation, `@intCast` width decisions → `intWidthBits`; keep emission/layout `size` uses. Signedness uses stay signedness.

- [ ] **Step 5: Byte-neutral regression.** Rebuild; 4-MD5 gate must be byte-identical (gol/lisp/json/mud). Self-compile must still complete (0 `error[`, 0 PANIC) with a moved fixed point (record md5; re-baseline is the battery task's job). Verify R7 + the 5 new fixtures still do NOT emit their GREEN contracts (uN semantics land in Task 4) — but valid `uN` type names must no longer hit `cannot declare variable of type void`; record actual classes.

- [ ] **Step 6: Commit.**

```bash
git add sf/src/type_registry.zig sf/src/type_resolver.zig sf/src/coercion.zig \
        sf/src/semantic_analyzer.zig sf/src/comptime_eval.zig sf/src/lower.zig sf/src/c89_emit.zig
git commit -m "feat: arbitrary-width int type layer — width_bits/is_signed + uN/iN registration (byte-neutral)"
```

- [ ] **Step 7: Report + ledger.** Note any site where signedness or a compare resisted clean classification (STOP-present only if a site is genuinely ambiguous).

---

### Task 4 (F): Emission + full wrap/sign semantics

**Files:**
- Modify: `sf/src/c89_emit.zig`, `sf/src/comptime_eval.zig`, `sf/src/lower.zig`, `sf/src/semantic_analyzer.zig` (carrier/mask/sign-extend; `@intCast` truncate/extend; literal materialization; `@bitSizeOf/@sizeOf/@alignOf` on uN; checked-cast table)

**Interfaces:**
- Consumes: Task 3 type layer.
- Produces: uN/iN fully usable with wrap/mask/sign-extend → the 5 fixtures + R7 turn GREEN with byte-exact contracts.

- [ ] **Step 1: C89 carrier map + mask/sign-extend emission.** In `c89_emit`: for integer types with `width_bits` not a full-carrier width (i.e. u3/u12/u20/u33..., and ALL iN/iN-like sub-64 where width < carrier bits): on STORE to a `uN` var, emit `& ((1<<width)-1)` mask (uN) or sign-extend (iN, from bit width-1); on arithmetic results assigned to `uN`/`iN`, apply the same wrap; on signed loads/compares, sign-extend first. Carrier = smallest power-of-2 ≥ width. Verify the emitted C compiles clean under `-std=c89` and produces the wrap contracts.
- [ ] **Step 2: `@intCast` truncate/extend generalization.** Widen: uN zero-extend / iN sign-extend; narrow: truncate + mask/sign-extend. Checked vs unchecked per existing semantics; the checked decision table generalizes from the fixed 8/16/32/64 set to width. Literal-to-uN materialization masks/sign-extends (spec §3.4).
- [ ] **Step 3: comptime `@bitSizeOf/@sizeOf/@alignOf` on uN** (spec §3.2/§5 values: bit=N; size=carrier bytes; align=carrier alignment) + width-aware const folds.
- [ ] **Step 4: Flip GREEN.** Run the 5 fixtures + R7: each prints its byte-exact contract, `RUNRC=0`, deterministic 3×; emitted C inspected for the mask/sign-extend forms (record one representative snippet per fixture class).
- [ ] **Step 5: 4-MD5 + regression.** gol/lisp/json/mud byte-identical; golden 9/9; matrix 21/21; corpus unchanged on non-uN dirs.
- [ ] **Step 6: Commit.**

```bash
git add sf/src/c89_emit.zig sf/src/comptime_eval.zig sf/src/lower.zig sf/src/semantic_analyzer.zig
git commit -m "feat: arbitrary-width int semantics — carrier mask/sign-extend, @intCast truncate/extend, introspection"
```

- [ ] **Step 7: Report + ledger.**

---

### Task 5 (F): Full battery + fixed-point re-baseline STOP-present + docs

**Files:**
- Record: report verdict; then (after operator approval) docs reconciliation.
- Modify (post-approval): `repro/mi_matrix/EXPECTED_FAIL.md` (v71→v72, 5 rows + R7 RESOLVED), `docs/sf/QUICK_REF.md` (newest-first bullet)

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: go/no-go evidence + operator-ruled re-baseline + docs.

- [ ] **Step 1: Full battery.** 4-MD5 (expect gol `302df36b`/lisp `3591bad9`/json `76056b97`/mud `846106ac` UNCHANGED); golden 9/9; matrix 21/21; corpus (fresh `-s0`) with the INTWIDTH fixture rows flipping to GREEN and zero delta elsewhere; all 6 fixtures + R7 run-gates byte-exact 3×.
- [ ] **Step 2: Self-compile fixed-point re-baseline proposal.** Two-hop round trip; record new md5 (was `10f0ca2b`); STOP-present the re-baseline (operator-ruled, never silent) alongside the battery verdict.
- [ ] **Step 3: STOP-present.** Battery table, fixture evidence, re-baseline proposal, tree hygiene. No further action until operator ruling.
- [ ] **Step 4 (post-approval): docs.** EXPECTED_FAIL v71→v72: mark the 5 INTWIDTH rows + R7 RESOLVED with fix commits (Tasks 3/4), RED history verbatim. QUICK_REF newest-first bullet (INTWIDTH feature + re-baseline + gate figures). Commit:
```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs: GATE — arbitrary-width ints GREEN + fixed-point re-baseline (INTWIDTH)"
```
- [ ] **Step 5: Report + ledger.**

---

## Plan Self-Review

1. **Spec coverage:** full semantics (T4), backend-agnostic width + explicit Type fields (T3), uN/iN name registration + bad-width diagnostics (T3), carrier/mask/sign-extend emission + @intCast + introspection (T4), RED-first guards (T2), battery + re-baseline + docs (T5). Spec §5/§6 contracts map to fixtures in T2 and GREEN in T4.
2. **Placeholder scan:** fixture code is complete; census numbers come from Task 1's verified re-derivation (line numbers necessarily re-verified during execution — stated). No invented values.
3. **Type/name consistency:** helpers `intWidthBits`/`intIsSigned`; fixtures `intwidth_{wrap,sign_extend,cast,introspect,full}_xmod`; commits carry `INTWIDTH`; report `task-INTWIDTH-report.md`; memory agent `intwidth-session`.
