# Rogue MUD - Compiler Investigation Results

This document contains the findings of a deep-dive investigation into several bugs and quirks identified during the implementation of the `rogue_mud` project.

## Investigation Environment
- **Host System**: Linux (Ubuntu-based)
- **Target Architecture**: 32-bit (x86)
- **C Compiler**: `gcc -m32 -std=c89`
- **Compiler Flags used for Investigation**:
  - `Z98_ENABLE_DEBUG_LOGS` (macro)
  - `--verbose`
  - `--debug-lifter`
  - `--debug-codegen`

## Internal Instrumentation Changes
To properly track lifetime issues, the `LifetimeAnalyzer` was instrumented with `[LifetimeAnalysis]` log messages. During the investigation, it was discovered that `plat_printf_debug` (which uses `vsnprintf`) was less reliable for immediate output on Linux than direct `plat_print_debug` calls. The instrumentation was updated to use a sequence of `plat_print_debug` calls for maximum visibility.

## 1. "Aborted" Message in `dungeon_test.zig`

### Investigation Summary
The `zig0` compiler aborts during the code generation phase when compiling `examples/rogue_mud/test/dungeon_test.zig`. The investigation pinpointed the exact location and cause of this failure.

### Root Cause: Naked Tag Resolution in Binary Operations
The failure occurs in `examples/rogue_mud/lib/scenario.zig` within the `carveHCorridor` and `carveVCorridor` functions:

```zig
if (tiles[idx] == .Wall) tiles[idx] = .Floor;
```

In this context:
- `tiles[idx]` is an instance of `tile_mod.Tile`, which is a `union(enum)` (tagged union).
- `.Wall` is a **naked tag** (`NODE_MEMBER_ACCESS` with a `NULL` base).

#### Failure Mechanism
1.  **Type Checking**: When `TypeChecker::visitBinaryOp` processes the `==` operation, it visits both operands. It sees `.Wall` as an ambiguous tag.
2.  **Missing Coercion**: Currently, `visitBinaryOp` lacks logic to perform "contextual coercion". It does not check if one operand is a tagged union and use that information to resolve the other operand if it's a naked tag.
3.  **Emitter Crash**: Because the tag remains unresolved (its `base` is still `NULL`), it is passed through the pipeline. When `C89Emitter::emitAccess` encounters a `NODE_MEMBER_ACCESS` with `base == NULL`, it triggers a `plat_abort()`:
    ```cpp
    if (member->base == NULL) {
        error_handler_.report(ERR_INTERNAL_ERROR, node->loc, "Internal error: naked tag reached emitter");
        plat_abort();
    }
    ```

### Conceptual Proposal for Fix
1.  **Enhance `visitBinaryOp`**: Modify `TypeChecker::visitBinaryOp` to detect naked tags. If one operand is a `TYPE_TAGGED_UNION` and the other is an ambiguous tag, call `coerceNode` on the tag using the tagged union type as the target.
2.  **Aggregate Equality**: Note that even with resolution, Z98 currently rejects `==` on structs and unions. Tagged unions would need special handling in `TypeChecker` and `C89Emitter` to support equality (likely by comparing the tag first).

---

## 2. Lifetime Violation on Slice Returns

### Investigation Summary
Returning a slice derived from a many-item pointer or array in a struct field (e.g., `return self.ptr[0..self.len]`) is incorrectly flagged as a lifetime violation: "Returning pointer to local variable creates dangling pointer".

### Root Cause: Parameter Classification
The investigation revealed that `LifetimeAnalyzer` considers all symbols with the `SYMBOL_FLAG_LOCAL` flag as "dangerous" if they are returned by pointer or slice.

In Z98:
- **Local variables** on the stack have `SYMBOL_FLAG_LOCAL`.
- **Function parameters** also have `SYMBOL_FLAG_LOCAL` (because they are part of the local activation record), but they also have `SYMBOL_FLAG_PARAM`.

The `isSymbolLocalVariable` function in `src/bootstrap/lifetime_analyzer.cpp` currently only checks for `SYMBOL_FLAG_LOCAL`:

```cpp
bool LifetimeAnalyzer::isSymbolLocalVariable(const char* name) {
    Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
    if (!sym) return false;
    return (sym->flags & SYMBOL_FLAG_LOCAL) != 0; // ❌ Includes parameters
}
```

When `self.ptr[0..len]` is analyzed:
1.  Provenance is determined to be `self.ptr`.
2.  The base name is extracted as `self`.
3.  `isSymbolLocalVariable("self")` returns `TRUE` because `self` is a local parameter.
4.  The analyzer incorrectly assumes `self` (the pointer to the struct) is a stack-allocated variable that will disappear, whereas parameters are valid for the duration of the function call, and specifically for `self: *List`, the *pointer* is local but the *data it points to* is typically caller-owned or heap-allocated.

### Conceptual Proposal for Fix
The analyzer should distinguish between stack-allocated local variables and function parameters. Parameters should be considered safe to return pointers "from" (as they refer to memory owned by the caller), provided the provenance doesn't lead back to a truly local variable (like a local buffer).

**Proposed Pseudo-code:**
```cpp
bool LifetimeAnalyzer::isSymbolLocalVariable(const char* name) {
    Symbol* sym = unit_.getSymbolTable().findInAnyScope(name);
    if (!sym) return false;
    // Only flag as dangerous if it's local AND NOT a parameter
    return (sym->flags & SYMBOL_FLAG_LOCAL) && !(sym->flags & SYMBOL_FLAG_PARAM);
}
```

---

## 3. Modulo Operator Quirk

### Investigation Summary
The modulo operator `%` on large integers (especially `u64` values exceeding 2^32) can sometimes produce incorrect results in certain environments. The recommendation in Z98 is to cast to `u32` before performing modulo operations if possible.

### Investigation Findings
1.  **C89 Emission**: The investigation confirmed that Z98 does not currently perform constant folding for modulo operations (or most binary operations). Instead, it emits the operands and the operator directly to C:
    ```c
    res = a % b;
    ```
2.  **32-bit Compatibility**: In the investigation environment (`gcc -m32 -std=c89`), 64-bit modulo operations produced **correct** results even for values larger than 2^32.
3.  **Target Runtime Dependency**: Since Z98 relies on the underlying C compiler to handle the `%` operator for 64-bit integers (`long long` or `__int64`), the "incorrect results" quirk is highly likely to be a limitation or bug in the **target C compiler's runtime library** (e.g., the `_alldiv` or `_allrem` routines in legacy MSVC runtimes).

### Conceptual Proposal for Fix
Since this is a target-specific limitation, a compiler-side "fix" would involve:
1.  **Software Implementation**: Implementing a target-independent 64-bit division/modulo helper in the Z98 runtime (`zig_runtime.c`) and having the compiler emit calls to these helpers instead of using the C `%` operator for 64-bit types.
2.  **Linting**: Providing a warning when performing 64-bit modulo on known problematic targets, suggesting the `u32` cast workaround.

---
