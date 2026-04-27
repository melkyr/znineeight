# Z98 Bootstrap Caveats and Workarounds

This document tracks known limitations, bugs, and recommended workarounds for the Z98 Stage 0 (C++) bootstrap compiler. These are behaviors that differ from modern Zig or represent temporary compromises made to simplify the bootstrap process.

## 1. Language Limitations

### 1.1 Global Constant Aggregates
**Issue**: Declaring a `pub const` array of structs or unions with complex nested initializers (e.g., strings, optional types, or tagged union variants) may fail to generate the necessary C89 definitions. The symbol will be referenced in the code but will result in "undefined identifier" errors during linking.
**Workaround**: Use `pub var` for the global variable and initialize it at runtime within a dedicated `init()` function called at the start of `main`.

### 1.1.1 Tagged Union Global Initializers
**Issue**: C89 does not support designated initializers (`.tag = ...`), and union initializers can only set the *first* member. Portably initializing a global tagged union to a non-first variant is impossible in strict C89.
**Workaround**: Use `pub var` and initialize the tagged union at runtime (e.g., in `main` or an `initGlobals()` function).

### 1.2 Strict Type Equality
**Issue**: The Z98 bootstrap compiler follows C89's strict assignment rules. Unlike modern Zig, there is no implicit narrowing for integer literals (e.g., `var x: u8 = 255;` works, but `var x: u8 = my_i32;` fails even if the value is known to fit).
**Workaround**: Use `@intCast(TargetType, expr)` or `@floatCast` for all numeric assignments that are not direct literal initializers.

### 1.3 Switch Expression Exhaustiveness
**Issue**: Every `switch` expression **must** include an `else =>` prong, even if the compiler could theoretically prove that all enum variants or integer ranges are covered.
**Workaround**: Always add an `else` prong to your switch expressions.

### 1.4 Optional Pointer Captures
**Issue**: The bootstrap compiler does not yet support pointer captures in `if` or `while` statements (e.g., `if (optional_val) |*p|`).
**Workaround**: Use a value capture and then take the address manually, or use an explicit boolean flag and index the original structure.

### 1.5 Slices in Branches
**Issue**: When using an `if` or `switch` as an expression that returns a slice, ensure all branches explicitly produce a slice type.
**Workaround**: The compiler implements "Distributed Coercion" to help, but in complex cases, you may need to wrap the branch result in a synthetic slice or use a temporary variable.

## 2. Code Generation (C89) Caveats

### 2.1 Pointers to Fixed-Size Arrays
**Bug**: The `C89Emitter` incorrectly passes pointers to fixed-size arrays (e.g., `*[800]Cell`) as pointers to the first element (`Cell*`) instead of array pointers (`Cell(*)[800]`).
**Workaround**: Use slices (`[]Cell`) for function arguments instead of pointers to arrays. Slices are the preferred way to pass array data in Z98.

### 2.2 Optional Struct Field Order
**Bug**: In some coercion contexts, the `C89Emitter` may generate `Optional` struct initializers with fields in the wrong order (e.g., `{1, &ptr}` instead of `{&ptr, 1}`).
**Status**: Fixed for `extern "c"` calls. The TypeChecker now automatically coerces arguments to raw pointers at the C boundary. For non-extern contexts, unwrapping before assignment is still recommended if ordering issues persist.

### 2.3 MSVC 6.0 String Limits
**Constraint**: MSVC 6.0 limits string literals to 2048 characters.
**Status**: The `C89Emitter` automatically splits long strings into concatenated chunks (`"..." "..."`) to bypass this limit. No manual workaround is typically required.

## 3. Platform and Runtime

### 3.1 `plat_fd_set` Alignment
**Issue**: The size and alignment of `fd_set` varies by platform. WinSock specifically requires 4-byte alignment for the `fd_set` structure.
**Workaround**: Z98 uses an opaque buffer for `plat_fd_set`. To ensure correct alignment, define it using an array of `u32` (e.g., `data: [128]u32`). This maintains the 512-byte size while forcing 4-byte alignment.

### 3.2 PAL Linkage
**Issue**: The PAL is C++ but the generated code is C.
**Requirement**: All PAL functions intended for use in Zig must be wrapped in `extern "C"` in `src/include/platform.hpp`.

### 3.3 TCO and Arena Exhaustion
**Issue**: While Tail-Call Optimization is supported in the compiler, the `ArenaAllocator` is not automatically reset during TCO loops.
**Workaround**: In long-running recursive loops (like a Lisp REPL), ensure that temporary allocations are minimized or that the loop eventually returns to a caller that can reset the transient arena.
