# Challenges in Lisp Interpreter Recursion Fix

## Current Status
- **Memory Alignment**: Enforced 8-byte alignment in `sand_alloc` and used `u64` arrays for arena buffers. Verified that `@sizeOf(Value)` is 16 bytes on 32-bit.
- **Recursion Fix**: Implemented mutable slot strategy for `define`. Bindings are created *before* RHS evaluation.
- **Deep Copy**: Implemented deep copy of lambda parameters, bodies, and captured environments into permanent memory.
- **Blocker**: Basic expressions like `(+ 1 2)` are currently returning `Nil` instead of the expected result.

## Diagnosis of `Nil` Result
- Diagnostic prints show `PARSED TAG: Nil` for input `(+ 1 2)`.
- Tracing `alloc_cons` reveals it produces `Nil` tags even when explicitly passed non-Nil values.
- **Root Cause**: The bootstrap compiler has a bug in handling anonymous struct initializers within tagged unions (e.g., `Value{ .Cons = .{ .car = car, .cdr = cdr } }`). This results in the tag field being incorrectly set to `0` (`Nil`).

## Fix Strategy
1. **Named Structs**: Replace anonymous structs in `Value` union variants with named structs (e.g., `ConsData`).
2. **Explicit Assignment**: Use named struct initialization to ensure the C89 codegen emits correct assignments.
3. **Alignment**: Maintain 8-byte alignment in `sand_alloc` to ensure `f64` and `Value` size stability on 32-bit.
