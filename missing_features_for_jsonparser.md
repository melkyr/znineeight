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
| While Continue Expr | ✅ Fixed | `while (cond) : (iter) { ... }` is now supported as of Task 9.8. |
| Implicit Coercion | ✅ Fixed | Strings and slices now implicitly coerce to `[]const u8` and `[*]const u8`. |
| Struct Methods | ❌ Not Supported | Methods inside structs are not supported in the bootstrap compiler. Use standalone functions. |
| Optional/Error captures | ❌ Unstable | `if (opt) |v|` or `while (opt) |v|` captures are unstable. Use manual null checks. |
| Enum Comparison | ⚠️ Restricted | Direct enum comparison `v.tag == .Tag` may fail. Use `@enumToInt(v.tag) == @enumToInt(Tag.Value)`. |
| Float Built-ins | ❌ Restricted | `@intToFloat` and `@floatCast` usage in complex expressions may trigger syntax errors or segfaults. |

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

### 2. Parser: Slicing Expression Limitations
**Issue**: Slicing expressions involving member access (e.g., `p.input[p.pos..]`) can trigger "Expected a primary expression" when used as function arguments or in initializers. This is due to precedence issues in the Pratt parser where the `..` operator does not correctly bind to the preceding member access or index expression.

**Failing Example**:
```zig
// Trigger: syntax error: Expected a primary expression
if (p.input.len - p.pos < 4 or
    !slice_eql(p.input[p.pos..][0..4], "null")) { ... }
```

**Workaround**: Assign the base or the slice to a temporary variable to clarify precedence.
```zig
const input = p.input;
const pos = p.pos;
const input_slice = input[pos..];
if (input.len - pos < 4 or !slice_eql(input_slice[0..4], "null")) { ... }
```

### 3. Parser: Missing `while` Continue Expressions
**Status**: FIXED in Task 9.8. `while (cond) : (iter) { ... }` is now supported.

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

### 5. Type Checker: Raw Pointer Decay (Resolved)
**Issue**: Passing a string literal `"foo"` or a slice `[]u8` to an `extern` function expecting `[*]const u8` previously failed with a type mismatch.
**Status**: Fixed. Slices and arrays now decay to many-item pointers, and string literals coerce to both slices and many-item pointers.

### 6. Codegen: Lifting vs Coercion Order (Resolved)
**Issue**: `emitAssignmentWithLifting` was attempting to wrap success values (e.g., `T` -> `!T`) before checking if the rvalue was a control-flow expression (like `if` or `switch`). This resulted in empty payloads in the generated C code because the control-flow emission (which handles the assignment) was bypassed.
**Status**: Fixed. Lifting logic now takes precedence over coercion wrapping.

### 7. Codegen: Invalid Assignment of Divergent Blocks
**Issue**: An `orelse return ...` in an assignment `var f = fopen(...) orelse return;` was translated to `f = { ... return ... };` which is invalid C89.
**Status**: Known limitation. Assignments from control flow that can diverge (return/break) must be handled carefully. The "Unified Lifting" pass in Milestone 8 is the intended fix.

### 8. Codegen: Slice Indexing
**Issue**: In some contexts, slice indexing `slice[i]` was emitted as `slice[i]` in C, which is invalid since `slice` is a struct. It should always be `slice.ptr[i]`.
**Status**: FIXED. `emitAccess` now correctly detects `TYPE_SLICE` and appends `.ptr`.

### 9. Header Generation: Missing Typedefs
**Issue**: Module headers (e.g., `file.h`) refer to types like `Slice_u8` or `ErrorUnion_Slice_u8` that are only defined in `main.h`. This makes modules hard to compile independently.

**Failing Example in `file.h`**:
```c
/* file.h */
ErrorUnion_Slice_u8 z_file_readFile(void*, Slice_u8); // Error: unknown type name 'ErrorUnion_Slice_u8'
```

**Status**: FIXED. Every header file is now self-contained by emitting all used special types (slices, error unions, optionals) within the header itself.

### 10. C89 Compatibility: Extern `*void`
**Issue**: `extern fn foo(p: *void)` was emitted as `extern void z_foo(void p)`, which is invalid C. This happens because the bootstrap compiler sometimes treats `*void` (pointer to zero-sized type) inconsistently in `extern` signatures.

**Failing Example**:
```zig
extern fn arena_alloc(arena: *void, size: usize) *void;
```
Generated C:
```c
extern void arena_alloc(void arena, unsigned int size); // Error: parameter has void type
```

### 11. C89 Compatibility: Standard Library Signature Mismatches
**Issue**: Our `extern` declarations for standard C functions use `unsigned char const*` for Zig strings, while standard C headers (like `<stdio.h>`) use `char const*`.

**Failing Example**:
```zig
extern fn fopen(filename: [*]const u8, mode: [*]const u8) ?File;
```
Generated C:
```c
extern Optional_Ptr_void fopen(unsigned char const* filename, unsigned char const* mode);
/* Conflicting types with /usr/include/stdio.h */
```

### 12. C89 Compatibility: `void` in Unions
**Issue**: Tagged unions are translated to a C `struct` with an internal `union`. If a Zig union arm has type `void` (e.g., `.Null => void`), it is emitted as `void Null;` inside the C union, which is invalid.

**Failing Example in `json.h`**:
```c
union z_json_JsonData {
    void Null; // Error: variable or field 'Null' declared void
    int BoolValue;
    ...
};
```

### 13. Compiler: Recursive Type Resolution Segfault
**Issue**: Highly complex recursive types or deeply nested structures can trigger a segmentation fault in the Stage 0 compiler during type checking or name mangling.
**Hypothesis**: Structural equality checks (`areTypesEqual`) and placeholder resolution trigger infinite recursion or use-after-free when circular dependencies involve slices or union fields. Valgrind reports uninitialized memory usage in `emitGlobalVarDecl` and `emitFnDecl` when cross-module symbol metadata is incomplete.

## Hypothesis and Recommendations

### Hypothesis on Compiler Stability
The Stage 0 compiler has reached its architectural limit for handling highly complex, mutually recursive, multi-module Zig code. The primary "wall" is the **Structural Equality** and **Placeholder Resolution** logic. When a type is used as an element of a slice, which is a field of a union, which is pointed to by a struct, the depth of resolution and the potential for circular dependencies in the interner/cache trigger unstable states.

### Recommendations for Next Phases
1.  **Unified Lifting (Milestone 8)**: Essential for stabilizing control-flow expressions in complex nesting.
2.  **Type Interner Overhaul**: The current structural equality check (`areTypesEqual`) needs to be more robust against incomplete types and placeholders.
3.  **Cross-Module Metadata Hardening**: Ensure all symbol metadata (mangled names, alignment, completeness) is guaranteed to be initialized before the codegen phase begins, possibly through a dedicated "Preparation Pass" after type checking.
4.  **Simplified Parser Demo**: For the JSON parser demo, continue using a "downgraded" style that favors explicit pointers and manual tag management until the Stage 1 compiler is available to provide better self-hosting stability.
