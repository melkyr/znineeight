# Technical Debt: Static Analyzers

This document tracks technical debt, architectural limitations, and stability risks in the Z98 compiler's static analysis passes (`LifetimeAnalyzer`, `NullPointerAnalyzer`, `DoubleFreeAnalyzer`).

## 1. DoubleFreeAnalyzer

### 1.1 Recursion Stability
The analyzer uses recursive traversal for variable name extraction and allocation call detection. Currently, there are no depth guards, posing a stack overflow risk on deeply nested ASTs, particularly on MSVC 6.0 with limited stack space.
- **Affected Methods**: `extractVariableName`, `isAllocationCall`, `isChangingPointerValue`.
- **Mitigation**: Implement `MAX_RECURSION_DEPTH = 64`.

### 1.2 Fragmented Cast Tracking
The analyzer "loses track" of pointers when they are wrapped in certain expressions that preserve their numeric value but change their AST node type.
- **Issue**: `extractVariableName` returns `NULL` for `(p)`, `@ptrCast(*T, p)`, and `@ptrToInt(p)`.
- **Impact**: Incorrect leak reports or missed double-frees when casts are used.
- **Mitigation**: Update `extractVariableName` to "look through" `NODE_PAREN_EXPR`, `NODE_PTR_CAST`, and `NODE_INT_CAST`.

### 1.3 `errdefer` Inaccuracy
The analyzer currently executes all deferred actions (both `defer` and `errdefer`) at scope exit, regardless of whether the exit was triggered by an error.
- **Impact**: False positives in double-free detection if an `errdefer` frees memory that is also freed on the success path.
- **Requirement**: Track the "error state" of the current execution path to selectively execute `errdefer`.

### 1.4 Aggregate Nesting Limits
Composite name tracking (e.g., `s.ptr`) is currently limited to a single level.
- **Impact**: Fails to track allocations in nested structures like `outer.inner.ptr`.
- **Mitigation**: Extend `extractVariableName` to recursively build interned composite names.

## 2. LifetimeAnalyzer

### 2.1 Missing Capture Propagation
Pointer provenance is not yet tracked through optional or error union captures.
- **Example**: `if (opt_ptr) |ptr| { return ptr; }` where `opt_ptr` points to a local variable.
- **Status**: Deferred.

### 2.2 Alias Tracking
The analyzer has minimal support for aliasing through pointer dereferences (`*ptr = &local`).
- **Status**: Limited by the single-pass nature of the bootstrap compiler.

## 3. NullPointerAnalyzer

### 3.1 Tag-Blind Member Access
Member access (e.g., `s.ptr`) is conservatively treated as `PS_MAYBE`. It does not yet understand that certain union tags might guarantee a pointer is non-null.
- **Status**: Requires tag-aware analysis of structs/unions.
