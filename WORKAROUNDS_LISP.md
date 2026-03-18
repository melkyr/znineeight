# Findings and Workarounds for Lisp Interpreter (Baptism of Water)

This document summarizes the compiler bugs identified and the attempted workarounds during the implementation of the Lisp interpreter in Z98.

## 1. Cross-Module Recursive Type Resolution
**Status**: CRITICAL BLOCKER.
**Bug**: Importing a module with recursive structs (e.g., `Value` -> `ConsData` -> `Value`) triggers a `DynamicArray` assertion failure in the `TypeChecker`.
**Reproduction**: `examples/lisp_interpreter/repro_bug.zig`
**Attempted Workaround**: Consolidating all code into a single file `lisp.zig`. This bypasses the assertion but uncovers further language limitations.

## 2. Missing `@intToPtr` Builtin
**Status**: BUG.
**Error**: `repro_inttoptr.zig:2:24: error: syntax error ... hint: Expected a primary expression`
**Bug**: The builtin `@intToPtr` is not implemented in the bootstrap compiler, preventing the conversion of `usize` or `u32` back to pointers.
**Reproduction**: `repro_inttoptr.zig`
**Workaround**: Use `*void` for "opaque" pointers and `@ptrCast` instead of integer-based pointer storage.

## 3. Optional Pointer (`?*T`) Comparison with `null`
**Status**: BUG.
**Error**: `repro_optional_null.zig:3:13: error: type mismatch ... hint: invalid operands for comparison operator '!=': '?*i32' and 'null'`
**Bug**: Comparison of optional pointers with `null` using `==` or `!=` is not supported.
**Reproduction**: `repro_optional_null.zig`
**Workaround**: Use `@ptrToInt(@ptrCast(*void, opt_ptr)) != 0` to check for non-null status.

## 4. `while` Payload Capture Failure
**Status**: BUG.
**Error**: `repro_while_capture.zig:3:17: error: syntax error ... hint: Expected a primary expression`
**Bug**: The `while (optional) |capture|` syntax is not correctly parsed/handled, despite `if (optional) |capture|` working in some contexts.
**Reproduction**: `repro_while_capture.zig`
**Workaround**: Use an infinite `while (true)` loop with an internal `if (optional) |node|` and a `break` in the `else` branch.

## 5. Cross-Module Symbol Visibility (Regression)
**Status**: OBSERVED BUG.
**Symptoms**: Functions marked `pub` in imported modules are intermittently reported as missing when accessed.
**Investigation**: Simple cases work, but in the context of the Lisp interpreter's multi-file structure, symbols like `parser_mod.parse_expr` were reported missing from `main.zig`.
**Workaround**: Consolidate to a single file.

## 6. Strict Type Checking and `@ptrCast`
**Status**: LIMITATION.
**Observations**: The compiler is extremely strict about assignments between `*T` and `?*T`. Even with `@ptrCast`, many conversion paths are blocked or result in internal compiler errors/assertions if types are recursive.
**Workaround**: Aggressively use `*void` and manually manage types.

## Conclusion: Pausing Implementation
The "Baptism of Water" (Lisp Interpreter) implementation was paused as the number of required workarounds grew to a point that threatened the readability and stability of the interpreter. The focus has shifted to documenting these bugs to enable future compiler improvements.
