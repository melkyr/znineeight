# Technical Debt: Static Analyzers

This document tracks technical debt, architectural limitations, and stability risks in the Z98 compiler's static analysis passes (`LifetimeAnalyzer`, `NullPointerAnalyzer`, `DoubleFreeAnalyzer`).

## 1. DoubleFreeAnalyzer

### 1.1 Recursion Stability [RESOLVED]
The analyzer uses recursive traversal for variable name extraction and allocation call detection.
- **Mitigation**: Implemented `MAX_RECURSION_DEPTH = 64` in `extractVariableName`, `isAllocationCall`, and `isChangingPointerValue`.

### 1.2 Fragmented Cast Tracking [RESOLVED]
The analyzer "loses track" of pointers when they are wrapped in certain expressions that preserve their numeric value but change their AST node type.
- **Mitigation**: Updated `extractVariableName` to "look through" `NODE_PAREN_EXPR`, `NODE_PTR_CAST`, and `NODE_INT_CAST`.

### 1.3 `errdefer` Inaccuracy [RESOLVED]
The analyzer now correctly tracks error paths.
- **Mitigation**: Implemented path-aware `errdefer` semantics. `errdefer` blocks only execute if the function returns an error type (`error` or `!T`). Managed via `ErrorPathGuard` RAII helper.

### 1.4 Aggregate Nesting Limits [RESOLVED]
- **Mitigation**: `extractVariableName` now recursively builds interned composite names for `NODE_MEMBER_ACCESS` and `NODE_ARRAY_ACCESS`. Improved to handle multi-level nesting and precise constant array indexing.

### 1.5 Diagnostic Context
Messages lacked context about ownership transfers.
- **Mitigation**: Added `transferred_from` and `transfer_loc` tracking. Diagnostics now report original owners and transfer sites for leaked/double-freed pointers.

## 2. LifetimeAnalyzer

### 2.1 Missing Capture Propagation [RESOLVED — updated: 2026-10-17 — D1/D2 surface + drift truth-up]
Pointer provenance is not yet tracked through optional or error union captures.
- **Example**: `if (opt_ptr) |ptr| { return ptr; }` where `opt_ptr` points to a local variable.
- **Status**: Resolved at T5. Captures (`if`/`while` payload captures, `for`
  captures, `switch`-prong captures, `catch |e|` captures) now bind through
  `bindCaptureState` (`sf/src/analyzer.zig`): lifetime mode inherits the
  provenance of the captured expression, so the example flags WARN_6010
  ("returning pointer to local via variable"). Null mode binds the capture
  `safe`; double-free mode inherits the origin's allocation state and marks the
  origin `transferred`. Fixture: `tests/analyzers/capture_lifetime.zig` (run by
  `test_analyzer_bin`'s `testFixture`); unit test
  `testCaptureLifetimePropagation`. Base classification (T5): pointer-like
  params (`*T`, `[*]T`, `[]T`, fn-ptr) seed `Provenance.external` — interiors
  (`&p.field`) follow the caller-owned pointee; bare `&p` still dangles.

### 2.2 Alias Tracking
The analyzer has minimal support for aliasing through pointer dereferences (`*ptr = &local`).
- **Status**: Limited by the single-pass nature of the bootstrap compiler.

## 3. NullPointerAnalyzer

### 3.1 Tag-Blind Member Access
Member access (e.g., `s.ptr`) is conservatively treated as `PS_MAYBE`. It does not yet understand that certain union tags might guarantee a pointer is non-null.
- **Status**: Requires tag-aware analysis of structs/unions.

## 4. Cross-cutting (T5 truth-up)

### 4.1 Comptime-Dead Arms [RESOLVED — updated: 2026-11-08 — Phase 3.5 D4a]
Per Zig semantics (T3 rule) a comptime-untaken arm does not exist for
analysis. `AnalyzerContext` now carries the shared `ComptimeFoldTable`
(`comptime_folds`), `phase_StaticAnalyzers` passes it, and
`analyzerFoldComptimeVal` consults it before falling back to the same
`comptimeEvalInit`/`comptimeEvalEvaluate` machinery sema and lowering use.
Capture-free `if` arms and `switch` prongs with a decisive selector walk only
the live arm; a dead prong emits nothing. An undecidable selector/label keeps
every prong live (conservative).
- **Status**: Resolved; fixtures `tests/analyzers/dead_arm.zig` and
  `tests/analyzers/dead_arm_switch.zig`.

### 4.2 NullPointer Return/Init Expressions [RESOLVED — updated: 2026-11-08 — Phase 3.5 D4b]
`analyzeExpr` now runs on `return`-statement expressions and on `var`
initializer / assignment RHS expressions, so a deref there (`return p.*`) is
checked. Non-optional pointer-like parameters (`*T`, `[*]T`, `[]T`, fn-ptr)
are seeded `safe` in the null state map; optional parameters stay unseeded
(`maybe`) until a guard or capture refines them, so they remain conservative
by design.
- **Status**: Resolved; fixtures `np_return_null.zig`, `np_init_null.zig`,
  `np_assign_null.zig`, `np_param_safe.zig`, and `np_single_deref.zig`.

### 4.3 Capture/Aliasing Limits (DoubleFree) [PARTIALLY RESOLVED — updated: 2026-11-08 — Phase 3.5 D4c]
Allocation state now propagates through identifier RHS copies for `var`
initializers and assignments, and captures inherit the origin's state, so
`var p = alloc(); var op = p; if (op) |q| { free(p); free(q); }` reports the
second free as `ERR_2005` (DF-1). Alias classes fork/merge with the state map,
and reassigning the canonical name re-roots the surviving aliases.
- **Remaining limit**: a same-block use-after-free through an alias copy is
  still not claimed (only the canonical name reports), and unknown calls do not
  transfer ownership. See §2.2.
- **Status**: Fixtures `df_alias_chain.zig`, `df_capture_alias_chain.zig`,
  `df_alias_reassign*.zig`, `df_unknown_call.zig`.
