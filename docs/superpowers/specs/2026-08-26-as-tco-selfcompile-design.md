# `@as` Miscompilation + TCO Self-Emission — Design

**Date:** 2026-08-26
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start

## Goal

Fix three self-emission fidelity gaps of the self-compiled `zig1_5`, verified against the `zig1` oracle (zig1 emission is authoritative-correct):

- **A — missing fn-ptr typedef:** the self-emitted C references `zT_…_FN_<…>` fn-ptr type names that are only header-guarded, never typedef'd (reference emits `_FP_<…>` names **with** `typedef void (*…)(…)` bodies). Result: gcc `unknown type name` → 6 programs fail to build under zig1_5 (4 corpus + 2 z98).
- **B — compiler SEGV:** zig1_5 crashes (rc=139, ASAN: READ SEGV in `typeRegistryIsAssignable`) while compiling `fn_ptr_struct_field`. Reference compiles it cleanly.
- **C — TCO back-edge missing:** the self-emitted compiler never emits the self-recursive tail-call `goto z_bb_0;` back-edge (reference does). Result: `tco_return_try` stack-overflows at 100000-deep error-union recursion (rc=139); `tco_defer` output diverges (100013 `D` prints vs reference 3).

All three are **self-compile fidelity gaps**, NOT regressions from the completed assoc-chain/pending_scope plan (`be0c681a`): the reference compiler rebuilt from the same `sf/src` HEAD handles every affected program correctly.

## Scope Decisions (operator-ruled)

- Full R/I/F rounds for A, B, C, matching the previous plan structure.
- Correctness bar = RUNTIME behavior vs the zig1 oracle (byte-identity vs zig0 not required; the 4 MD5 gates remain authoritative and must stay byte-identical).
- A and B share ONE root cause (`@as`); they get R-A, R-B fixtures and a single F-AS fix.
- C root cause is NOT yet pinned (findTailCall + TCO condition verified emitted correctly); it is investigated as plan task I-C, then fixed as F-C.
- Fixtures REUSE the existing corpus/z98 dirs (already minimal reproducers); R tasks capture RED baselines, no new fixture commits.
- `@as` fix = **add `@as` builtin handling** to the compiler's Zig source (faithful, mirrors the F-ASSOC `@intToEnum` precedent). Rewriting the 3 `@as` sites to `@intCast` was offered and REJECTED (leaves `@as` broken for any future/user use).

## Background (findings — investigation completed in-planning)

### `@as` is unhandled in zig1's own Zig source (root cause of A + B)

- The C++ bootstrap `zig0` folds `@as(T, x)` at type-check time into a cast node (int→int → `NODE_INT_CAST`; float→float → `NODE_FLOAT_CAST`; ptr→ptr → `NODE_PTR_CAST`; else coerce-and-replace) — `src/bootstrap/type_checker.cpp:8199-8248`. So the reference zig1 handles `@as` correctly.
- zig1's Zig source has NO `@as` path: `semanticAnalyzerIsTypeValueCast` (`semantic_analyzer.zig:214-222`) lists only `@ptrCast`/`@intToPtr`/`@intCast`/`@floatCast`/`@intToFloat`/`@intToEnum`; the builtin-call cast block (`lower.zig:3486-3552`) has branches only for `@intCast`/`@intToFloat`/`@ptrCast`/`@intToPtr`/`@intToEnum` and falls through to `return result;` (an uninitialized `nextTemp`).
- Exactly **3 `@as(u32, …)` sites** exist in the whole compiler source:
  - `c89_emit.zig:736` — `if ((ty.flags & @as(u32, 1)) != @as(u32, 0))` (the `_FP_`/`_FN_` selector in `getCTypeName`, and the same guard gates `emitFnPtrType` at `c89_emit.zig:1668`). **→ A**
  - `type_registry.zig:851-852` — `self.xt_items[@intCast(usize, src_f.params_start + @as(u32, fi))]` (index arithmetic in `typeRegistryIsAssignable`). **→ B**
- Self-emission evidence (verified, `/tmp/zig1_5/gen/` and per-program z5 emissions):
  - `getCTypeName` fn-ptr name: `zT_848 = 1; zT_850 = zT_847 & zT_849;` — `zT_849` never written → the `& 1` flag read is garbage → the `'P'`/`'N'` choice is NON-DETERMINISTIC across invocations. The flag itself IS set (`typeRegistryMarkFnPtrUsed` and its call site in `type_resolver.zig:916` are emitted correctly), so the typedef body IS emitted — but under whichever name one invocation happened to compute (e.g. `_FP_void`), while the var-decl references the name a different invocation computed (e.g. `_FN_void`). Same logical fn type, two C names → gcc `unknown type name` (observed: `ZIG_FNPTR_zT_08C0D7CE_FP_void` body present, `zT_9EF551F0_FN_void` referenced in the var decl).
  - `typeRegistryIsAssignable`: `zT_130 = zT_128 + zT_129;` — `zT_129` (the `@as(u32, fi)` result) never written → index into `xt_items` is garbage → SEGV.
  - Fixing `@as` makes the flag read deterministic → name always matches the typedef → both A and B resolved by F-AS alone.
- Fix shape (F-AS), mirroring the F-ASSOC `@intToEnum` addition exactly:
  - `semantic_analyzer.zig`: add `as_name_id: u32` struct field (near `:53-59`), intern `"@as"` (near `:101`), assign `.as_name_id = as_id,` (near `:186`), and `if (name_id == self.as_name_id) return true;` in `semanticAnalyzerIsTypeValueCast` (`:214-222`).
  - `lower.zig`: add `as_name_id: u32` struct field (near `:369`), intern `"@as"` (near `:429`), assign (near `:511`), and `else if (node.child_0 == self.as_name_id)` branch (near `:3545-3550`) emitting `LirInst.int_cast` with `is_checked = @intCast(u8, 0)` (unchecked — `@as` is comptime-safe, exactly like the `@intToEnum` branch).
- All 3 compiler-source `@as` uses are int→int (`@as(u32, …)`); an unchecked `int_cast` is the correct, minimal, faithful lowering for them. General float/ptr dispatch is NOT needed (out of scope).
- The 4 MD5 gate programs use no `@as`, so the new branch never fires for them → gates stay byte-identical by construction.

### C — TCO self-recursion back-edge not emitted (root cause NOT yet pinned)

- Reference emits `goto z_bb_0;` for self-recursive tail calls (`fact`, `count`, `countDown`); zig1_5 emits a real recursive call.
- Verified emitted correctly in the self-emission: `findTailCall` (`lower.zig:5671`, LirInst tag ordinals call=14, call_direct=23, unwrap_error_payload=34, etc. all match `lir.zig`); the return_stmt TCO condition (`lower.zig:5087-5088`: `ci.is_self == 1 and ci.args_count == params.len`); the `?CallInfo` optional has_value unwrap; `@enumToInt` (correctly a no-op passthrough at `lower.zig:3286-3291`).
- Remaining suspects (I-C scope): `hasOtherConsumers` (`lower.zig:5776`) returning true and skipping the TCO branch; the `?CallInfo` optional return construction; `expandDefers` / `defer_bb_unchanged` (`lower.zig:5065-5070`); or a subtler dataflow difference in the emitted `findTailCall` hop loop.

## Architecture

- **Phase A+B (one fix):** R-A/R-B reproduce and capture RED baselines against existing fixtures; F-AS adds `@as` builtin handling (2 files, mechanical mirror of F-ASSOC); rebuild zig1 + zig1_5; verify A and B fixtures GREEN (gcc-clean, run matches ref; `fn_ptr_struct_field` no longer SEGVs) and gates stay byte-identical.
- **Phase C:** I-C pins the TCO mis-emission (read-only, leads provided); F-C applies the pinned fix; rebuild + verify C fixtures GREEN (`tco_return_try` rc=0, `tco_defer` output matches ref, `tco_factorial` unchanged).

## Components / Data Flow

- F-AS changes: `semantic_analyzer.zig` (`as_name_id` registration + `IsTypeValueCast`) + `lower.zig` (`as_name_id` registration + unchecked `int_cast` branch). No other file.
- Affected fixtures (A): `emission_void_call_xmod`, `emission_void_call_control_xmod`, `func_ptr_return_type`, `inferred_errorset_fnptr` (corpus) + `quicksort`, `func_ptr_return` (z98).
- Affected fixture (B): `fn_ptr_struct_field` (corpus).
- Affected fixtures (C): `tco_return_try`, `tco_defer`, `tco_factorial` (z98).

## Error Handling / Testing

- Fixtures runtime-driven: A = gcc-clean + run output matches reference binary; B = compiler no longer SEGVs (dump+gcc+link+run all rc=0); C = `tco_return_try` rc=0 + `tco_defer` output byte-equal to reference binary output.
- 4 MD5 byte-identity gates (must remain byte-identical): gol `eed963e0640a073ed4eebb292f136e05`, lisp `c3c5847798e4553b2e34950e085bb6c6` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- Matrix 21/21; corpus 329-dir + z98 21-dir runtime sweep vs reference; self-compile re-count (40 `.c`, 0 `error[`, 0 PANIC).
- Z98 dialect; `timeout 120` on all compiler/binary invocations (`timeout 900` for builds).

## Out of Scope

- General float/ptr `@as` dispatch (the 3 actual sites are int→int; YAGNI).
- Any additional self-emission fidelity gaps revealed beyond the pinned A/B/C loci (STOP-present).
- The `sf/src_sh/` self-containment implementation (deferred; own plan on disk).
