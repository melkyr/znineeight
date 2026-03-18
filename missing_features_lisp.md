# Missing Features and Bugs Found During Lisp Interpreter Implementation (Baptism of Water)

This document tracks language features, compiler bugs, and architectural constraints discovered while building the Lisp interpreter in Z98.

## Resolved Issues

### 0. Cross-Module Recursive Type Resolution (FIXED)
The critical `DynamicArray` assertion failure during recursive type resolution is now resolved. The compiler correctly handles complex recursive structures across module boundaries using a Work-Queue algorithm for dependent refreshing and a Snapshotting Pattern for stable iteration over type arrays.

### 1. Optional Pointer (`?*T`) Comparison with `null`
Comparison of optional pointers with `null` using `==` or `!=` is now fully supported.

### 2. Member Access on Optionals (`.value`, `.has_value`)
Directly accessing `.value` (the payload) and `.has_value` (the presence flag) on optional types is now supported as a read-only operation.

## Resolved Issues (Advanced Syntax)

### 1. Tagged Union Switch Capture
Using `switch` captures with `union(enum)` types is now fully supported. Payload types are resolved recursively during capture variable creation to prevent assertion failures.

### 2. while Payload Capture
Support for `while (optional) |capture|` syntax and semantics has been implemented across the parser, type checker, and C89 code generator.

## Unsupported Language Features (Advanced Syntax)

### 1. Standard Library Availability
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
