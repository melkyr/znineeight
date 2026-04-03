# Detailed Findings from the Lisp Interpreter "Baptism of Water"

This document records the issues, bugs, and limitations discovered while attempting to compile and run the Z98 Lisp interpreter versions.

## 1. Summary of Results (Phase 2)

| Version | Status | Notes |
|---------|--------|-------|
| Downgraded (`lisp_interpreter`) | **SUCCESS** | Baseline stable in 32-bit mode. |
| Current (`lisp_interpreter_curr`) | **SUCCESS** | Idiomatic Z98 features (unions, switches) work. |
| Advanced (`lisp_interpreter_adv`) | **SUCCESS** | Anonymous struct payloads in unions are now verified working. |

## 2. Current Findings & Quirks (Phase 2)

### C Code Bugs & Warnings

#### Issue: String Literal Slice Mismatch
**Observation**: The compiler's implicit conversion of string literals (e.g., `"foo"`) to `[]const u8` (Slice_u8) in function calls triggers C compilation warnings. The generated code calls `__make_slice_u8` with a `char *` but the helper expects `unsigned char *`.
**Symptom**: `warning: pointer targets in passing argument 1 of ‘__make_slice_u8’ differ in signedness [-Wpointer-sign]`
**Reproduction**: `examples/lisp_interpreter_curr/repro_slice_mismatch.zig`
**Workaround**: Explicitly define a helper function `fn __make_slice_u8(ptr: [*]const u8, len: usize) []const u8 { return ptr[0..len]; }` and use it for all string literal arguments to ensure consistent types, or use `@ptrCast` (though this is more verbose).

#### Issue: Anonymous Structs in `union(enum)` Initializers (RE-EVALUATED)
**Previous Observation**: Initializing a tagged union variant with an anonymous struct payload `.{ .Variant = .{ ... } }` failed to generate data member assignments.
**Current Status**: **FIXED** in Milestone 11. Testing of `lisp_interpreter_adv` and updated `lisp_interpreter_curr` shows that this syntax now correctly generates C code for both the tag and the payload fields.
**Verified Code**:
```zig
pub const Value = union(enum) { Cons: struct { car: *Value, cdr: *Value }, ... };
v.* = Value{ .Cons = .{ .car = car, .cdr = cdr } };
```

#### Issue: Local `const` Aggregate Declarations
**Observation**: Declaring a local variable as `const` with a struct, union, or enum type causes the compiler to treat it as a type declaration and skip C code emission.
**Example**: `const v = Value{ .Int = 1 };` results in `v` being undeclared in the generated C.
**Status**: **CONFIRMED**. Still present in Milestone 11.
**Workaround**: Use `var` for local aggregate instances even if they are intended to be constant.

### Z98 Syntax & Codegen Quirks

#### Issue: Lisp Interpreter Recursion (Deep Investigation)
**Observation**: Recursive Lisp functions defined via `(define fact (lambda (n) ...))` fail to resolve the recursive call correctly.
**Symptoms**:
1.  Closures capture the environment at creation time.
2.  A "pre-binding" strategy was attempted in `eval.zig`:
    *   Bind name to `nil` in environment.
    *   Evaluate lambda (captures env with name -> `nil`).
    *   Update environment node value in-place to the new closure.
3.  **Result**: Recursive lookups often return `nil` or `NotCallable`.
4.  **Deep Analysis**: The issue appears to be related to how `deep_copy` and environment mutation interact. If the closure captures a specific `EnvNode` pointer, and the value within that node is updated by replacing the pointer (`node.value = new_val`), the closure might still be looking at an old state or a different copy of the environment depending on how many times it was "extended" or copied across arenas.
5.  **Codegen Quirk**: Updating a union field in-place via pointer (`node.value.* = new_val.*`) compiled but resulted in runtime `nil` values during REPL tests, suggesting potential issues with how unions are assigned in C89 when dereferencing pointers.
**Status**: **DOCUMENTED SYMPTOMS**.

#### Issue: Direct Tagged Union Member Access
**Observation**: Attempting to access a tagged union member directly (e.g., `v.Cons.car`) when the compiler "should" know the tag is active sometimes generates invalid C code or is rejected with confusing errors.
**Reproduction**: `examples/lisp_interpreter_curr/repro_union_member_access.zig`
**Note**: Z98 generally expects `switch` captures or `if` captures for safe union access.

#### Issue: Loop State & Capture Sensitivity
**Observation**: Complex logic inside `while` loops that involves `switch` captures on tagged unions can lead to unexpected runtime errors.
**Reproduction**: `examples/lisp_interpreter_curr/repro_capture_loop.zig`

## 3. Portability & Compatibility Reports

### 32-bit Compatibility (`-m32`)
- **Status**: **SUCCESS**.
- **Observations**: Essential for the 1998 target. Both compiler and generated code are stable in 32-bit.

### Windows Compatibility (Mingw-w64 + Wine)
- **Status**: **SUCCESS**.
- **Observations**: Cross-compilation to 32-bit Windows works. Deep recursion requires increased stack size (`-Wl,--stack,16777216`).

## 4. Previously Reported/Solved Issues
- **Symbol Name Corruption (FIXED)**: Symbol names are now copied to permanent memory.
- **Tagged Union Tag Assignment Precedence (FIXED)**: Fixed `*t.tag` vs `(*t).tag`.
- **Uninitialized `__tmp_catch` (FIXED)**: Lifter now ensures zero-initialization.
- **Implicit `memcpy` (FIXED)**: `<string.h>` is now included in prologue.
