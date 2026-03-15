# Findings from the JSON Parser "Baptism of Fire"

This document records the issues, bugs, and limitations discovered while attempting to compile a modern Z98 JSON parser.

## 1. Type System & Semantic Analysis

### Recursive Type Completeness (Slices)
- **Status**: **LIMITATION**.
- **Observation**: Types containing slices of themselves (e.g., `Array: []JsonValue` inside `JsonValue`) result in "incomplete type" errors during layout calculation because slices require the element type to be complete for `@sizeOf` during some internal passes.
- **Workaround**: Use pointers for recursion (e.g., `value: *JsonValue` or `[]*JsonValue`).

### Strict Assignment Compatibility
- **Status**: **ENFORCED CONSTRAINT**.
- **Observation**: The compiler is very strict about identical types in assignments and struct initializers. `i32` literals do not always implicitly coerce to `usize` in these contexts.
- **Workaround**: Use explicit types or ensured literals (e.g., `const zero: usize = 0;`).

### If Expression Branch Consistency
- **Status**: **ENFORCED CONSTRAINT**.
- **Observation**: Branches of an `if` expression must have exactly the same type. No implicit widening between branches is performed by the bootstrap compiler.

## 2. Code Generation & ABI

### 32-bit vs 64-bit ABI Mismatch
- **Status**: **CORE LIMITATION**.
- **Observation**: The RetroZig bootstrap compiler is hardcoded with 32-bit target assumptions (4-byte pointers, 8-byte slices, 4-byte alignment). When generating C code for a 64-bit host, `@sizeOf` values and struct layouts mismatch the 64-bit C compiler's expectations.
- **Impact**: Severe memory corruption and incorrect behavior at runtime when compiled as 64-bit.
- **Recommendation**: Always compile the generated C code with `-m32` or on a native 32-bit platform.

## 3. Findings from Modern Version (Milestone 9 Verification)

### `union(enum)` Initialization Failure
- **Status**: **BUG IDENTIFIED**.
- **Observation**: Using the `.{ .Field = value }` syntax for `union(enum)` results in "anonymous struct initializer requires a declared struct or array type".
- **Root Cause**: The TypeChecker doesn't correctly recognize the inferred union type in assignments or return statements for tagged unions.

### `union(enum)` Member Access Failure
- **Status**: **LIMITATION IDENTIFIED**.
- **Observation**: Accessing a tag directly via `JsonValue.Tag` often fails with "Incompatible assignment" when assigned to a non-enum type, or fails to resolve if the base is a module member.

### Struct Methods Unsupported
- **Status**: **AS DESIGNED**.
- **Observation**: Struct methods `fn (self: *T) ...` are not supported.
- **Workaround**: Use top-level functions `fn name(self: *T) ...`.

### Switch Expression Type Inference
- **Status**: **BUG IDENTIFIED**.
- **Observation**: Switch expressions often fail to unify types between prongs, even when they should (e.g., all prongs returning the same union type).
- **Example**: `return switch (ch) { 'n' => JsonValue.Null, ... }` fails with "Switch prong type does not match previous prongs".

### Capture syntax limitations
- **Status**: **STABILITY ISSUE**.
- **Observation**: Switch captures (`|x|`) are supported for tagged unions but proved unstable when combined with complex bodies or nested expressions.

## 4. Reproduction Cases for Newly Identified Bugs

### Bug 1: Tagged Union Initialization Failure
The following Zig code fails to compile because the compiler does not correctly infer the union type for the anonymous initializer in a return statement.
```zig
const MyUnion = union(enum) {
    A: i32,
    B: bool,
};

fn getA() MyUnion {
    // ERROR: anonymous struct initializer requires a declared struct or array type
    return .{ .A = 42 };
}
```

### Bug 2: Switch Expression Type Inference Failure
Even when all prongs return the same type, the switch expression may fail to unify them.
```zig
const MyUnion = union(enum) {
    A: i32,
    B: bool,
};

fn testSwitch(u: MyUnion) MyUnion {
    return switch (u) {
        .A => |a| MyUnion{ .A = a },
        .B => |b| MyUnion{ .B = b },
    };
}
// ERROR: Switch prong type does not match previous prongs
```

### Bug 3: Meta-type Unwrapping in Member Access
Accessing a tag via a type alias or module-qualified name sometimes results in incorrect type resolution.
```zig
const json = @import("json.zig");
// ... inside some function ...
const tag = json.JsonValue.Null;
// May fail if json.JsonValue is not correctly unwrapped from TYPE_TYPE
```

## 5. Successful Features Verified
- **@import**: Works across multiple files.
- **Error Unions**: `FileError![]u8` works correctly with `try` and `catch`.
- **Extern C Interop**: `fopen`, `fread`, etc., are correctly called with `@ptrCast`.
- **Slices**: `.len` and `.ptr` properties work.
- **Many-item Pointers**: `[*]u8` works for C string interop.
- **AST Lifting**: Complex expressions were correctly lifted into temporary-variable-based statements.
- **Single Translation Unit (STU)**: The generated `main.c` correctly includes all module files for a unified compilation.
- **Peak Memory Usage**: Compilation of the JSON parser uses **~479 KB**, well within the 16MB limit.
