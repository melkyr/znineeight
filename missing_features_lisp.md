# Missing Features and Bugs Found During Lisp Interpreter Implementation (Baptism of Water)

This document tracks language features, compiler bugs, and architectural constraints discovered while building the Lisp interpreter in Z98.

## Critical Compiler Blocker: Cross-Module Recursive Type Resolution

### 1. The DynamicArray Assertion Failure
**Error**: `retrozig: src/include/memory.hpp:570: T& DynamicArray<T>::operator[](size_t) [with T = Type*; size_t = long unsigned int]: Assertion 'index < len' failed.`

**Trigger Instructions**:
To reproduce the bug, compile the provided minimal reproduction in the `examples/lisp_interpreter/` directory:
```bash
./retrozig examples/lisp_interpreter/repro_bug.zig -o repro_bug.c
```
The failure occurs because `repro_bug.zig` imports `value.zig`, which defines a recursive struct (`Value` -> `ConsData` -> `Value`).

### 2. Theoretical Root Cause: `resolvePlaceholder` and `refreshLayout`
The investigation suggests a race or ordering issue in how the compiler resolves `TYPE_PLACEHOLDER` types that have dependents across module boundaries.

**The Theory**:
1.  When a recursive type is first encountered, a `TYPE_PLACEHOLDER` is created.
2.  Types that depend on this placeholder (like a pointer to it or a struct containing it) are added to the placeholder's `dependents` list (a `DynamicArray<Type*>*`).
3.  In `TypeChecker::resolvePlaceholder` (around line 2277 of `type_checker.cpp`):
    ```cpp
    /* Mutate placeholder in place */
    if (resolved && resolved != placeholder) {
        DynamicArray<Type*>* dependents = placeholder->as.placeholder.dependents;
        // ... mutation of placeholder to the resolved type ...
        if (dependents) {
            for (size_t i = 0; i < dependents->length(); ++i) {
                refreshLayout((*dependents)[i]);
            }
        }
    }
    ```
4.  **The Failure**: When modules are imported, types might be sharded or re-instantiated. If `dependents->length()` returns a non-zero value but the underlying array access `(*dependents)[i]` fails its internal bounds check, it implies that the `DynamicArray` itself is in an inconsistent state, possibly due to:
    -   Memory corruption or use-after-free of the `dependents` list during module boundary crossing.
    -   A mismatch between the `len` field and the actual capacity/allocation of the array when accessed from the importing module.
    -   Circular dependencies where `refreshLayout` triggers another `resolvePlaceholder` that mutates the same list.

### 3. Attempted Workarounds
-   **Downgraded Syntax**: Moving from `union(enum)` to manual `struct` + `union` did not fix the issue, as the underlying recursive pointer resolution still triggers the same logic.
-   **Field Reordering**: Moving recursive members to the end of the struct did not resolve the assertion.

## Unsupported Language Features (Advanced Syntax)

### 1. Tagged Union Switch Capture Failure
Using `switch` captures with `union(enum)` types can trigger similar assertion failures in the `TypeChecker`, likely because the capture variable creation involves resolving the union type's layout.

### 2. Standard Library Availability
Pulling in the `std` module (e.g., `@import("std")`) remains unreliable. The interpreter uses a `util.zig` module and `extern` C runtime functions for I/O and string operations to minimize compiler surface area.

## Implementation Details of the Lisp Interpreter

### 1. Dual-Arena System
To handle Lisp's dynamic nature while targeting 1998-era constraints:
-   **`perm_arena`**: Stores symbols, function definitions, and the global environment.
-   **`temp_arena`**: Stores transient evaluation results, reset after each REPL cycle.
-   **`util.deep_copy`**: A recursive function to migrate values from temporary to permanent storage (essential for `define`).

### 2. Downgraded Value Representation
Due to the compiler bugs, the `Value` type is implemented as:
```zig
pub const Value = struct {
    tag: ValueTag,
    data: ValueData,
};
pub const ValueData = union {
    Int: i64,
    Cons: struct { car: *Value, cdr: *Value },
    // ...
};
```
This avoids the `union(enum)` logic but still provides a tagged structure.
