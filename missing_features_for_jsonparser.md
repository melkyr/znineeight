# Missing Features for JSON Parser

This document details the findings from the "baptism of fire" where the Z98 compiler was tested against a multi-module JSON parser implementation.

## Feature Status Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-module Imports | ✅ Works | `const mod = @import("file.zig");` works. Standalone `@import` at top-level is rejected. |
| Built-in Functions | ✅ Works | `@ptrCast`, `@intCast`, `@sizeOf`, etc., are correctly lexed and parsed. |
| Type Aliases | ✅ Fixed | `const T = *i32;` now correctly resolves in all contexts after a fix in `TypeChecker::visitTypeName`. |
| Error Unions (`!T`) | ✅ Works | Supported in function signatures and `try` expressions. |
| Optionals (`?T`) | ✅ Works | Supported with `null` and `orelse`. |
| Slices (`[]T`) | ✅ Works | Supported, but requires explicit `.ptr` access when decaying to raw pointers. |
| Labeled Loops | ✅ Works | `label: while (...)` and `break :label` are supported. |
| Tagged Unions | ⚠️ Unstable | `union(enum)` is recognized but complex nested initializations often fail type checking. |
| Switch Captures | ⚠️ Unstable | `|payload|` syntax is supported but type inference within the capture is fragile. |
| Recursive Types | ❌ Limited | Self-referential types via slices (`[]JsonValue`) sometimes fail resolution. Explicit pointers are safer. |
| While Continue Expr | ❌ Missing | `while (cond) : (iter)` syntax is not supported by the parser. |
| Implicit Coercion | ❌ Missing | Strings and slices do not implicitly decay to `[*]const u8` (many-item pointers). |

## Detailed Discoveries and Workarounds

### 1. Parser: Mandatory Braces
**Issue**: The parser frequently requires braces for `if` and `while` statement bodies, even when they contain only a single statement.
**Workaround**: Always use `{ ... }` for control flow blocks.
```zig
// Failed
if (cond) return error.Bad;

// Worked
if (cond) { return error.Bad; }
```

### 3. Parser: Missing `while` Continue Expressions
**Issue**: The standard Zig `while (cond) : (iter) { ... }` syntax is not yet implemented.
**Workaround**: Move the iteration expression to the end of the loop body.
```zig
// Failed
while (i < len) : (i += 1) { ... }

// Worked
while (i < len) {
    ...
    i += 1;
}
```

### 4. Type Checker: Recursive Type Instability
**Issue**: Defining `JsonValue` as a struct containing a slice of itself (`[]JsonValue`) caused "incomplete type" errors because slices are currently represented as structs, and the placeholder resolution for nested structs is not yet fully robust.
**Workaround**: Use explicit pointers to break cycles.
```zig
// Unstable
pub const JsonValue = union(enum) {
    Array: []JsonValue,
};

// More Stable
pub const JsonData = union {
    Array: []JsonValue,
};
pub const JsonValue = struct {
    tag: Tag,
    data: *JsonData, // Pointer breaks the resolution cycle
};
```

### 5. Type Checker: Raw Pointer Decay
**Issue**: Passing a string literal `"foo"` or a slice `[]u8` to an `extern` function expecting `[*]const u8` fails with a type mismatch.
**Workaround**: Use `.ptr` and explicit `@ptrCast`.
```zig
// Failed
fopen("file.txt", "r");

// Worked
fopen(@ptrCast([*]const u8, "file.txt".ptr), @ptrCast([*]const u8, "r".ptr));
```

### 6. "Primary Expression" Parser Error
**Issue**: Deeply nested expressions involving `try`, `return`, and function calls occasionally confuse the Pratt parser, leading to an "Expected a primary expression" error.
**Status**: This is a known limitation of the current ad-hoc lifting strategy in the C89 backend.

## Recommendations for Future Improvements

1.  **Unified Lifting (Milestone 8)**: This is the single most important next step. Moving control-flow expressions (if, switch, try) into temporary variables in a dedicated AST pass will solve most of the "Primary Expression" and code generation stability issues.
2.  **Parser Synchronization**: Implement a "sync" mechanism (e.g., skip to next semicolon) on errors so multiple errors can be reported without aborting.
3.  **Placeholder Hardening**: Ensure that `TYPE_SLICE` and `TYPE_OPTIONAL` can safely contain `TYPE_PLACEHOLDER` during the recursive resolution pass.
4.  **Implicit Decay**: Implement implicit coercion from arrays/slices to many-item pointers (`[*]T`) to reduce the need for verbose `@ptrCast` and `.ptr` usage.
