# TCO Hardening — Implementation Plan

**Date:** 2026-08-03
**Branch:** `zig1_start`
**Design:** `docs/superpowers/specs/2026-08-03-tco-hardening-design.md`

Goal: close two latent correctness gaps from the final whole-branch review — single-consumer guard (Item 1) and defer-after-TCO ordering (Item 2).

## Required Reading

| Document | Role | Key Sections |
|----------|------|--------------|
| `docs/superpowers/specs/2026-08-03-tco-hardening-design.md` | Design oracle | All sections |
| `sf/src/lower.zig` | Lowerer — return_stmt TCO site + expandDefers | `return_stmt` :3614-3673, `expandDefers` :3922-3948, `lowerFn` :4280-4362, `findTailCall` :4114-4193, `zeroCallCFG` :4195-4263, `zeroChainInsts` :4195-4241 |
| `.superpowers/sdd/IM-tcoh1-report.md` | Item 1 research | Gap assessment, consumer field list |
| `.superpowers/sdd/IM-tcoh2-report.md` | Item 2 research | Defer lifecycle, per-iteration risk |

## Global Constraints

- **Source files:** `sf/src/lower.zig` only. Docs: `sf/docs/tech_docs/07_lir_lowering.md`, `docs/sf/QUICK_REF.md`. Repro examples: `examples/z98/tco_defer/`.
- **Z98 idioms required:** `@intCast`, if/else-if chains, no generics. `var msg: []const u8 = "text";` before PAL calls.
- **Build gate:** `bash sf/scripts/build_release.sh` → `=== [release] Done ===`, 0 errors.
- **Stdout md5s (4):** mud `9fde02d8a05e951de738e2df5d12b4f7`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `10d09c99f77c68e680f6ccce33eb81ed`, json `3492a935883ee91258feece576ba23d5`. All must match AMENDMENT-9/11 baselines.
- **Corpus gate:** `OK=165 FAIL=15 ICE=6 CRASH=0`. No regression.
- **No out-of-plan fixes.** STOP on ambiguity.

## F-S Implementation Tasks

### F-S1 — Defer-after-TCO ordering (Item 2)

**Files:** `sf/src/lower.zig`
**Pre-requisite:** IM-tcoh2 report

**Scope:** Move `expandDefers(self, 0, 0, 0)` from return_stmt line 3615 to AFTER the TCO decision. Self-TCO suppresses defer expansion (defers fire once at terminal exit). Cross/non-TCO preserves existing behavior.

**Steps:**
1. Remove the unconditional `expandDefers(self, @intCast(u32, 0), @intCast(u8, 0), @intCast(u8, 0))` at lower.zig:3615.
2. In the self-TCO branch (is_self==1): do NOT call expandDefers. The defer will fire later at the terminal return via `expandDefers(self, 0, 0, 1)` at lowerFn:4358.
3. In the cross-TCO branch (is_self==0, same-type guard): add `expandDefers(self, @intCast(u32, 0), @intCast(u8, 0), @intCast(u8, 0))` before `zeroCallCFG` call. Defers fire once before the tail_call.
4. In the no-TCO fallback (normal ret path): add `expandDefers(self, @intCast(u32, 0), @intCast(u8, 0), @intCast(u8, 0))` before the `ret` emission. Existing behavior preserved.

**Gate:** Build 0 errors. Stdout md5s preserved (no TCO example has defers in tail position). Create `examples/z98/tco_defer/main.zig` with self-recursive fn + `defer { cleanup(); }` → verify emitted C shows defer body ONCE at terminal return, not per-iteration.
**Commit:** `fix: F-S1 defer-after-TCO ordering (per-iteration fix)`

---

### F-S2 — Single-consumer guard (Item 1)

**Files:** `sf/src/lower.zig`
**Pre-requisite:** IM-tcoh1 report, F-S1

**Scope:** Add `hasOtherConsumers` guard before `zeroCallCFG`. Scans all blocks for any instruction referencing `call_result_temp` that is NOT a recognized chain consumer.

**Steps:**
1. Add private function `fn hasOtherConsumers(self: *LirLowerer, call_result: u32, ret_temp: u32) bool` after `zeroChainInsts`:
   - Scan ALL blocks/insts for any instruction whose input operands reference `call_result`.
   - Recognized chain consumers (SKIP these): `check_error` (`.value`), `unwrap_error_payload` (`.value`), `unwrap_error_code` (`.value`), `wrap_error_ok` (`.value`), `wrap_error_err` (`.value`), `call_direct` (the call itself — `.result`), `ret` (the `ret_temp` — suppressed). Also skip `.nop` (already zeroed).
   - For ALL OTHER variants, check every input field: `.value`, `.src`, `.operand`, `.ptr`, `.base`, `.cond`, `.lhs`, `.rhs`, `.index`, `.callee`, `.lhs`/`.rhs` for binary.
   - If any field equals `call_result` → return true.
   - If scan completes without finding any → return false.
2. In `return_stmt`, before each `zeroCallCFG` call (in both self and cross branches), call `hasOtherConsumers(self, ci.result, val)`:
   - If true → skip TCO entirely (do NOT call zeroCallCFG; fall through to the existing `if (block_terminated == 0)` normal ret path).
   - If false → proceed with zeroCallCFG + TCO emission as before.

**Gate:** Build 0 errors. Stdout md5s preserved (guard never fires — no false consumers in Z98 patterns). Existing tco examples still TCO'd (guard returns false → TCO fires). Corpus unchanged.
**Commit:** `fix: F-S2 single-consumer guard before call zeroing`

---

### F-S3 — Gate sweep + repros

**Files:** `examples/z98/tco_defer/main.zig` (new), verification only otherwise

**Scope:** Full gate verification. Create defer repro.

**Steps:**
1. Build: `bash sf/scripts/build_release.sh` → 0 errors, `[release] Done`.
2. Stdout md5s: verify all 4 match AMENDMENT-9/11 baselines.
3. Defer repro: `examples/z98/tco_defer/main.zig` — self-recursive fn with `defer { /* increment cleanup counter */ }` → verify emitted C shows defer body once at terminal return (before the final `return`), NOT between rebind and jump. gcc compile + link + run → defer fires exactly once.
4. Existing tco examples: tco_factorial and tco_return_try still compile + run deep recursion O(1) stack.
5. Lisp: `(+ 1 2)` → `> 3`.
6. Corpus: `OK=165 FAIL=15 ICE=6 CRASH=0`.
7. build_test.sh: 5/4 pre-existing baseline.

**Gate:** All gates pass.
**Commit:** `feat: F-S3 TCO hardening gate repros`

---

### F-S4 — Documentation

**Files:** `sf/docs/tech_docs/07_lir_lowering.md`, `docs/sf/QUICK_REF.md`

**Scope:** Document the two hardening fixes.

**Steps:**
1. `07_lir_lowering.md` TCO section: document the defer-after-TCO ordering (expandDefers moved) and the single-consumer guard.
2. `docs/sf/QUICK_REF.md`: add `tco_defer` example to recipes. Add a note about the consumer guard.

**Gate:** Doc-only; verify line refs against source.
**Commit:** `docs: F-S4 TCO hardening documentation update`

---

## Execution Notes

- **Sequential:** F-S1 → F-S2 → F-S3 → F-S4 (dependent — both touch lower.zig return_stmt).
- **Single commit per F-S stage.**
- **All gates pass before proceeding to next stage.**
- **Both fixes in lower.zig only.** No LIR/emitter changes.
- **Item 1 guard is pure defense — currently never fires. Item 2 is a real semantic fix.**
- **`expandDefers` at try_expr:2489 (err-path) UNTOUCHED. `expandDefers` at lowerFn:4358 (terminal exit) UNTOUCHED.**
