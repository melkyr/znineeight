# Compiler Gaps — 4-Item Design Spec

**Date:** 2026-08-06
**Status:** Draft
**Predecessor:** `2026-08-06-comptime-arithmetic-folding-design.md` (complete, READY TO MERGE at HEAD 4a7c6a17)

## Goal

Resolve four open items discovered during the comptime-arithmetic plan's lisp gate verification: (1) the `@intCast` range-check gap, (2) the compiler ICE on literals >= 2^32, (3) the varargs parser gap (full Z98 varargs support, not C89-delegated), and (4) the lisp interpreter's first-class-closures bug.

## Architecture

Four independent items, executed in one plan. Each compiler item follows the established I-task (investigation) → F-task (fix) cadence, except the two whose root causes are already proven, which go straight to F-tasks. The lisp closures fix is a lisp-SOURCE change (not a compiler change) and is scheduled last.

```
Item 1: @intCast range-check gap      I1 → F1 (+ repro)
Item 2: ICE on literal >=2^32         F2 only (+ repro, root cause known)
Item 3: Varargs full support          I2 + I3 + I4 → F3 + F4 + F5
Item 4: Lisp first-class closures     F6 (lisp source, last)
```

## Success Criteria

- All 4 compiler gaps resolved at root (not patched)
- Corpus: no new FAILs; the varargs repro flips FAIL→OK; the 2 new defensive repros are OK
- 4 MD5 gates byte-identical except where a change legitimately re-baselines (F-5 AMENDMENT B precedent — runtime is the gate)
- Build 0 gcc errors
- test_analyzer_bin PASS

---

# Item 1: @intCast Range-Check Gap

## Root Cause (proven)

zig1 lowers `@intCast(i32, i64_expr)` to raw `(int)val` in emitted C. The zig0 oracle emits `__bootstrap_i32_from_i64(val)` — an inline range-checked helper in `src/include/zig_runtime.h` that calls `__bootstrap_panic` on overflow. Discovered via lisp `(fact 13)`: prints garbage `1932053504` instead of panicking (zig0 oracle would PANIC with "integer cast overflow").

## Investigation (I1)

Trace `@intCast` end-to-end: parser → sema → lowerer → c89_emit. Determine where the type-narrowing cast happens today. Key questions:
- Is the missing range-check best added in the lowerer (emit a call to the bootstrap helper) or in c89_emit (inject the wrapper on cast emission)?
- Which src/dst type pairs does zig0 emit checked helpers for? (narrowing casts only, or all?)
- What is the bootstrap helper naming convention (`__bootstrap_DSTTYPE_from_SRCTYPE`), and which pairs does `zig_runtime.h` already define?
- Does the emitted `@intCast` ever need the unchecked form (e.g., comptime-folded consts already validated)?

Deliverable: `.superpowers/sdd/I-intcast-range-report.md` with exact file:line edits, blast radius (which baselines change), risk. STOP for operator ruling on the fix site.

## Fix (F1)

Derived from I1 findings. Expected: lowerer `@intCast` handler emits a `call_direct` (or c89_emit injects) the checked `__bootstrap_DST_from_SRC` wrapper for narrowing casts. Must handle the src type (i64 → i32, etc.) and preserve comptime-folded consts that are already validated.

## Repro

`repro/mi_matrix/intcast_range_check/main.zig` — a narrowing cast of a runtime i64 value that overflows the target i32 range. Pre-fix: prints garbage (no panic). Post-fix: runtime PANIC (`integer cast overflow in @intCast`) → nonzero exit. Classified OK (dump+gcc clean) with runtime-panic gate; document the panic in NOTES.md.

## Gate

Repro dumps rc=0, gcc-clean, links, and panics at runtime on overflow (not garbage). 4 MD5s — likely re-baselined for any baseline using narrowing @intCast; assess in I1.

---

# Item 2: ICE on Literal >= 2^32

## Root Cause (proven)

`lower.zig:1105` — a debug marker calls `palMarkerWriteInt(label, @intCast(u32, val))` where `val` is the u64 literal value. Any program containing a literal >= 2^32 (e.g. `pub const X: u64 = 5000000000;`) makes the marker's `@intCast(u32, ...)` panic → compiler SIGABRT (dump rc=134). The int_literal lowering pipeline itself is correct (F7 fixed the u64 folding bug); only the marker is broken.

## Fix (F2) — Option A: proper u64-safe marker

Add `palMarkerWriteIntU64` (or equivalent) to `pal.zig` — renders a label + full u64 value using itoa's existing 64-bit logic, with a 24-byte buffer (u64 max = 20 decimal digits). Replace the `@intCast(u32, val)` at `lower.zig:1105` with the u64-safe call. One marker per site; mirrors the existing `palMarkerWriteInt` pattern (pal.zig:99-106).

This fixes the ICE properly — large literals compile and emit correctly. Not a diagnostic band-aid.

## Repro

`repro/mi_matrix/ice_literal_overflow/main.zig` — `pub const X: u64 = 5000000000;` (and a second large literal to be thorough) + print of the value. Pre-fix: dump rc=134 SIGABRT. Post-fix: dump rc=0, gcc-clean, runs printing the correct value. Classified OK.

## Gate

Repro dumps rc=0, gcc-clean, runs correct value. 4 MD5s byte-identical (marker writes go to stderr; emitted C unchanged).

---

# Item 3: Varargs Full Support

## Scope

Full Z98 varargs — not C89-delegated. zig1 is a zig→multi-backend compiler; "the C compiler will handle it" (zig0's stance) is not acceptable. A Z98 function declared with `...` must be callable from Z98, and its body must be able to access the variadic arguments.

## Requirements

1. **Parser:** accept `...` as a trailing pseudo-parameter in fn declarations (extern AND Z98 fn). AST flag or marker on the fn_decl node.
2. **Sema:** validate `...` (trailing position only; fixed params typed normally).
3. **LIR:** new backend-neutral `va_start`/`va_arg`/`va_end` instructions (variadic access must not be C-specific).
4. **Builtins:** `@cVaStart(&va_list)`, `@cVaArg(&va_list, T)`, `@cVaEnd(&va_list)` for accessing variadic args from Z98.
5. **Lowerer:** map the builtins + the `...` body preamble to the new LIR va_* instructions; `extern fn` varargs calls lower normally (args passed through).
6. **c89_emit:** translate va_* LIR to C89 `va_list` + `va_start`/`va_arg`/`va_end` (`stdarg.h`). Emit `...` in C function declarations for varargs fns.

## Investigations

- **I2 (parser + oracle):** Use zig0 as a BLACK-BOX oracle only — feed it a varargs program, observe emitted C, do NOT read zig0 internals (its codegen is rotted/unmaintainable; it has a "lifter" and other legacy structures). Determine zig1 parser change sites for `...` acceptance.
- **I3 (sema + LIR):** Design the backend-neutral varargs representation. New LIR instructions + AST/type validation. Blast radius of adding LIR variants (mirror the TCO `tail_call` precedent: lir.zig union extension + switch arms in lower/c89_emit).
- **I4 (lowerer + c89_emit):** Map builtins to LIR, translate va_* LIR to C89. Verify against oracle C output for both `extern fn printf` callability and a Z98 varargs function body.

Each investigation delivers a report + A/B/C options + blast radius + risk. STOP for operator ruling at the end of each (or batched).

## Fixes

- **F3:** Parser `...` acceptance + AST flag.
- **F4:** Sema validation + LIR va_* instructions.
- **F5:** Builtins wiring + lowerer mapping + c89_emit translation.

## Repro

Existing `fn_varargs_unsupported/main.zig` (extern fn printf with `...`) flips FAIL→OK. Add a Z98 varargs function body repro (e.g. `fn sum(count: u32, ...) i32` iterating via @cVaArg) proving variadic access works end-to-end.

## Gate

Both repros dump rc=0, gcc-clean, link, run correctly (printf outputs formatted text; Z98 varargs fn computes correct sum). 4 MD5s — assess blast radius in I2-I4 (baselines using extern varargs fns would change).

---

# Item 4: Lisp First-Class Closures

## Root Cause (proven)

`examples/z98/lisp_interpreter_curr/eval.zig:124` reads `env.*` (the lambda's captured environment) instead of `curr_env.*` (the current dynamic environment). When a closure is created after a tail call that rebinds `env`, the captured environment is stale — caller parameters are lost. `((make-adder 5) 3)` returns `UnboundSymbol` instead of `8`. zig0 oracle behaves identically (it's a lisp-SOURCE bug, not a compiler bug).

## Fix (F6)

Change `env.*` to `curr_env.*` at `eval.zig:124`. Lisp source only — no compiler changes. The lisp MD5 gate WILL change (eval.zig is part of the multi-file `lisp_interpreter_curr` build; the single-stream `--dump-c89` gate hashes that entry). Re-baseline the lisp MD5 per F-5 AMENDMENT B precedent (runtime is the gate), and verify the 73-expression battery + first-class closures all pass at the new baseline.

## Verification

`((make-adder 5) 3)` prints `8` (was `UnboundSymbol`). `(define add5 (make-adder 5))` then `(add5 3)` also works. Regression check: the 73-expression battery arithmetic/define/recursion/conditionals/TCO/lists still pass.

## Timing

F6 is last, after all compiler items.

---

## Execution Order

```
I1 → F1 (+ intcast repro)
F2 (+ ICE repro)
I2 → I3 → I4 → F3 → F4 → F5 (varargs)
F6 (lisp closures, last)
Final whole-branch review + ledger closeout
```

## Gates (global)

- Build: zig0 → zig1 bootstrap in /tmp, 0 gcc errors (QUICK_REF recipe, NOT `sf/build/out_release/`)
- 4 MD5 gates: mud `4644ad13...`, gol `e2f4c625...`, lisp `dd56cd23...`, json `900cb401...` — byte-identical except operator-approved re-baselines
- Corpus: `206` repros, `OK=198/FAIL=4/gg=4` (raw 8) baseline; FAIL count must not increase; varargs repro FAIL→OK expected; 2 new repros OK
- test_analyzer_bin PASS
- fastedit/edit only. Read region before each edit. Bottom-to-top. NO scope creep.
- QUICK_REF.md reference mandatory for all gates.
