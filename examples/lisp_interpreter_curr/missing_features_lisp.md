# Detailed Findings from the Lisp Interpreter "Baptism of Water"

This document records the issues, bugs, and limitations discovered while attempting to compile and run the Z98 Lisp interpreter versions.

## 1. Summary of Results (Phase 2)

| Version | Status | Notes |
|---------|--------|-------|
| Downgraded (`lisp_interpreter`) | **SUCCESS** | Baseline stable in 32-bit mode. |
| Current (`lisp_interpreter_curr`) | **SUCCESS** | Idiomatic Z98 features (unions, switches) work with named payloads. |
| Advanced (`lisp_interpreter_adv`) | **SUCCESS (W/ WORKAROUND)** | Fails with anonymous struct payloads; works when moved to named structs. |

## 2. Current Findings & Quirks (Phase 2)

### C Code Bugs & Warnings

#### Issue: Blocker - Anonymous Structs in `union(enum)` Initializers
**Problem**: Initializing a tagged union variant that has an anonymous struct payload using the `.{ .Variant = .{ ... } }` syntax fails to generate the initialization code for the data members.
**Failing Code**:
```zig
pub const Value = union(enum) { Cons: struct { car: *Value, cdr: *Value }, ... };
v.* = Value{ .Cons = .{ .car = car, .cdr = cdr } };
```
**Generated C (Broken)**:
```c
{
    struct zS_5ed3ca_Value* init_lval_tmp = &(*v);
    /* MISSING: tag and data assignment */
}
```
**Workaround**: Use a named struct for the payload and explicit type initialization: `v.* = Value{ .Cons = ConsData{ .car = car, .cdr = cdr } };`.

#### Issue: Local `const` Aggregate Declarations
**Observation**: Declaring a local variable as `const` with a struct, union, or enum type causes the compiler to treat it as a type declaration and skip C code emission.
**Example**: `const v = Value{ .Int = 1 };` results in `v` being undeclared in the generated C.
**Workaround**: Use `var` for local aggregate instances even if they are intended to be constant.

#### Issue: Uninitialized `__tmp_catch` Variables
**Observation**: The generated C code for `catch` expressions often triggers `-Wmaybe-uninitialized` warnings in GCC.
**Analysis**: The lifter generates a temporary variable to hold the "yielded" value of the `catch` block, but does not strictly ensure initialization on all paths before use in the C output.

#### Issue: Implicit `memcpy` and Missing `<string.h>`
**Observation**: When capturing aggregate payloads in a `switch`, the compiler generates `memcpy` but does not include `<string.h>`.
**Status**: Confirmed. Results in warnings on GCC/Clang.

### Z98 Syntax & Codegen Quirks

#### Issue: Lisp Interpreter Recursion
**Observation**: Recursive Lisp functions defined via `(define fact (lambda (n) ...))` fail with `UnboundSymbol`.
**Reason**: This is an **interpreter design limitation**, not a compiler bug. Closures capture the environment at creation time, which does not yet contain the name being defined.

## 3. Portability & Compatibility Reports

### 32-bit Compatibility (`-m32`)
- **Status**: **SUCCESS**.
- **Observations**: Both the compiler (`zig0`) and generated code run correctly in 32-bit mode. Essential for the 1998 target.

### Windows Compatibility (Mingw-w64 + Wine)
- **Status**: **SUCCESS**.
- **Observations**:
    - Successfully cross-compiled `lisp_interpreter_curr` to a 32-bit Windows `.exe`.
    - Successfully ran expressions under `wine`.
    - **Note**: Requires increased stack size (`-Wl,--stack,16777216`) for deep recursion.

### Compiler Portability (Clang++)
- **Status**: **SUCCESS**.
- **Observations**: `zig0` (the bootstrap compiler) compiles successfully with `clang++`.

### Standard Library Portability (Musl-gcc)
- **Status**: **PARTIAL SUCCESS**.
- **Observations**: Building with `musl-gcc` (64-bit) resulted in a Segmentation Fault during symbol lookup, likely due to strictness in pointer/integer assumptions or memory layout differences.

## 4. Previously Reported/Solved Issues
- **Symbol Name Corruption (FIXED)**: Symbol names were previously stored as temporary slices; now copied to permanent memory.
- **Tagged Union Tag Assignment Precedence (FIXED)**: Previously generated `*t.tag` instead of `(*t).tag`.
- **Missing Definitions for Anonymous Structs (CONFIRMED)**: Documented as a Phase 2 blocker for the Advanced version.
- **Cross-Module Visibility (IMPROVED)**: Header inclusion order and forward declarations have been significantly hardened since Phase 1.
