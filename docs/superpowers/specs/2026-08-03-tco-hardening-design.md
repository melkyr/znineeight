# TCO Hardening — Design Spec

**Date:** 2026-08-03
**Status:** Draft
**Branch:** `zig1_start`
**Feature:** Harden the TCO implementation against two latent correctness issues found during final whole-branch review.

## 1. Goal

Close two latent correctness gaps in the self-hosted TCO implementation:

1. **Tail-adjacency guard** — defensive check before zeroing the call CFG: verify no other instructions consume the call result temp (future-proofs against instrumentation/debug/optimization passes).
2. **Defer-after-TCO ordering** — move defer expansion AFTER the TCO decision: self-TCO suppresses per-iteration defer execution (defer fires once at terminal exit); cross/non-TCO preserves existing behavior.

## 2. Architecture

Both fixes are in `sf/src/lower.zig` only. No LIR changes, no emitter changes.

### Item 1 — Single-consumer guard

New private function `hasOtherConsumers(self, call_result_temp, ret_temp) bool`:

Scans ALL blocks in `self.func.blocks` for any instruction that references `call_result_temp` as an input operand AND is NOT one of the recognized chain consumers (check_error, unwrap_error_payload/code, wrap_error_ok/err, ret). The `ret_temp` argument is excluded specifically (the return instruction is the consumer we expect — it's about to be suppressed).

Input operand checks: `.value`, `.src`, `.operand`, `.ptr`, `.base`, `.cond`, `.lhs`, `.rhs`, `.index` — all fields that read a temp. If ANY such field equals `call_result_temp` and the instruction is NOT a recognized chain inst → return true (has other consumers → bail).

Called in `return_stmt` before any `zeroCallCFG` call. If true → skip TCO entirely, fall through to normal `call_direct+ret`.

### Item 2 — Defer-after-TCO ordering

Current code (`lower.zig:3615`):
```
expandDefers(self, 0, 0, 0);   // fires BEFORE TCO decision
```

Changed to: remove the unconditional `expandDefers` at line 3615. Instead:

| Branch | Defers? | Rationale |
|--------|---------|-----------|
| Self-TCO fires | **No** (skip expandDefers) | Defer fires once at terminal exit via `expandDefers(self, 0, 0, 1)` at `lowerFn:4358`. Per-iteration defer destroys TCO's value (O(n) cleanup for O(1) stack). |
| Cross TCO fires | **Yes** (expandDefers before tail_call) | tail_call is a one-time event; defer fires once before it. |
| No TCO (fallback ret) | **Yes** (expandDefers before ret) | Existing behavior preserved. |

The try-expr err-path `expandDefers` at `lower.zig:2489` is UNTOUCHED — it fires only on the error path (correct). The defer-at-function-end `expandDefers(self, 0, 0, 1)` at `lowerFn:4358` is UNTOUCHED — it fires at the terminal function exit (correct for both TCO and non-TCO paths).

## 3. Scope

### In Scope
- `hasOtherConsumers` guard in lower.zig (~20 lines)
- Move `expandDefers` to after TCO decision in lower.zig (~5 lines)
- Repro examples: defer+TCO (exercise per-iteration vs once-at-end semantics)
- Gate sweep: build, md5s, corpus

### Out of Scope
- Per-call defer semantics (Zig language design question — the current "once at terminal exit" is the conservative correct answer)
- Guard-probe repro for Item 1 (not triggerable today — gate via existing corpus)
- No LIR/emitter changes
- No Z98 spec changes

## 4. Success Criteria (Gates)

| # | Gate | How |
|---|------|-----|
| 1 | Build 0 errors | `bash sf/scripts/build_release.sh` → `[release] Done` |
| 2 | Stdout md5s preserved | mud `9fde02d8...`, gol `d0d3051d...`, lisp `10d09c99...`, json `3492a935...` — all match AMENDMENT-9/11 baselines |
| 3 | Defer repro | `defer { cleanup(); } return self(args);` → defer fires exactly once at terminal return (not per-iteration) |
| 4 | Cross-defer repro | `defer { cleanup(); } return otherFn(args);` → defer fires once before tail_call (existing behavior preserved) |
| 5 | Corpus | `OK=165 FAIL=15 ICE=6 CRASH=0` no regression |
| 6 | Guard doesn't false-fire | Existing corpus + tco_factorial/tco_return_try still TCO'd (mud/gol/lisp/json baselines match) |

## 5. File Impact

| File | Change |
|------|--------|
| `sf/src/lower.zig` | Item 1: add `hasOtherConsumers`. Item 2: move `expandDefers`. ~25 lines total. |
| `examples/z98/tco_defer/` | New repro: self-recursive fn with defer (gate 3) |
