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

### 4.1 Comptime-Dead Arms — Partial Fold Probe [updated: 2026-10-17 — D1/D2 surface + drift truth-up]
Per Zig semantics (T3 rule) a comptime-untaken arm does not exist for
analysis. The analyzers now fold a conservative bool-literal family
(`analyzerFoldComptimeBool`: literals, parens, `!`/`&&`/`||`) and walk only
the live arm of a capture-free `if`. The shared comptime-fold table is not
plumbed into `AnalyzerContext` (would touch `main.zig`/`comptime_eval.zig`,
outside T5's touch set), so evaluator-only folds (named consts, compounds,
`@isWindows()`) and `switch` prongs still walk both sides.
- **Status**: Partial; full parity needs the fold table plumbed into the
  analyzer context.

### 4.2 NullPointer Return/Init Expressions Not Walked [updated: 2026-10-17 — D1/D2 surface + drift truth-up]
`analyzeExpr` is invoked for conditions, expression statements, and
assignment RHS, but NOT for `return`-statement expressions or `var`
initializers — a deref there (`return p.*`) is unchecked. Parameters are not
seeded in the null state map, so `param.*` patterns conservatively warn
(measured: 44 false WARN_6002 on the compiler self-source).
- **Status**: Pre-existing; disclosed, not fixed at T5 (would shift warning
  volume on live code; separate task).

### 4.3 Capture Aliasing Limits (DoubleFree) [updated: 2026-10-17 — D1/D2 surface + drift truth-up]
A capture inherits the origin's state when the origin already has one
(`var op = sandAlloc(...); if (op) |q| { ... }`). Alias chains
(`var p = alloc(); var op = p; if (op) |q|`) keep `op` untracked (the
assign-propagation gap of §1.5's transfer model), so frees through `q` in
that shape stay "untracked" warnings; freeing via one name and then another
alias is not cross-checked.
- **Status**: Limited by name-keyed single-map tracking (cf. §2.2).
