# Bootstrap Compiler Built-ins Reference

This document describes the built-in functions (intrinsics) supported by the RetroZig bootstrap compiler. These functions start with the `@` symbol and are either evaluated at compile-time or mapped to specific C89 constructs.

## Compile-Time Evaluated Built-ins

These built-ins are evaluated during the Type Checking phase and are replaced in the Abstract Syntax Tree (AST) with constant integer literals.

### `@sizeOf(T)`
Returns the size of type `T` in bytes as a `usize` constant.
- **Syntax:** `@sizeOf(TypeName)`
- **Constraints:** `T` must be a complete type. Incomplete types trigger `ERR_SIZE_OF_INCOMPLETE_TYPE`.
- **Target (32-bit little-endian):**
  - `i8`, `u8`: 1 byte
  - `i16`, `u16`: 2 bytes
  - `i32`, `u32`, `f32`, `*T`, `usize`, `isize`, `bool`: 4 bytes
  - `i64`, `u64`, `f64`: 8 bytes
  - `struct`: Sum of field sizes plus padding for alignment.

### `@alignOf(T)`
Returns the alignment requirement of type `T` in bytes as a `usize` constant.
- **Syntax:** `@alignOf(TypeName)`
- **Constraints:** `T` must be a complete type. Incomplete types trigger `ERR_SIZE_OF_INCOMPLETE_TYPE`.
- **Target (32-bit little-endian):**
  - `i8`, `u8`: 1 byte
  - `i16`, `u16`: 2 bytes
  - `i32`, `u32`, `f32`, `*T`, `usize`, `isize`, `bool`: 4 bytes
  - `i64`, `u64`, `f64`: 8 bytes

### `@offsetOf(T, field_name)`
Returns the byte offset of a field within a struct or union as a `usize` constant.
- **Syntax:** `@offsetOf(AggregateType, "field")`
- **Constraints:**
  - `AggregateType` must be a struct or union.
  - `field_name` must be a string literal.
  - The type must be fully defined (not incomplete).
- **Compile-time evaluation:**
  - Always constant-folded to a `usize` integer literal.
  - For unions, always returns `0`.
  - For structs, returns the pre-calculated byte offset from the beginning of the struct.
- **C89 Emission:** Emitted directly as the integer literal (e.g., `4`).
- **Known Limitation:** `@offsetOf` on incomplete types (e.g., forward declarations) is not currently testable in the bootstrap compiler as it does not support forward-declared structs. The error handling logic is implemented for robustness.

## Code Generation Built-ins

These built-ins are validated during type checking but are emitted as specific C89 code patterns.

### `@ptrCast(T, expr)`
Performs an explicit pointer cast.
- **Syntax:** `@ptrCast(*TargetType, pointer_expression)`
- **Constraints:** Both the target type and the expression must be pointer types.
- **C89 Emission:** `(TargetType*)pointer_expression`

### `@intCast(T, expr)`
Performs an explicit integer cast with range checking.
- **Syntax:** `@intCast(IntegerType, integer_expression)`
- **Constraints:** Both must be integer types (including `bool`).
- **Compile-time Evaluation:**
  - If `expr` is a constant integer literal, the compiler checks if the value fits within the target type's range.
  - If it fits, the `@intCast` call is replaced by a new `NODE_INTEGER_LITERAL` in the AST.
  - If it overflows, a fatal compile-time error is reported.
- **C89 Emission Strategy:**
  - **Constant cases**: Emitted as raw literals.
  - **Safe widenings** (e.g., `u8` to `i32`): Emitted as a direct C-style cast: `(int)expr`.
  - **Potentially unsafe narrowing/conversion**: Emitted as a call to a runtime helper function: `__bootstrap_<target>_from_<source>(expr)`.
  - **Runtime Helpers**: These functions (e.g., `__bootstrap_i32_from_i64`) are implemented as `static` functions in `zig_runtime.h`. They perform bounds checks at runtime and call `__bootstrap_panic` if the value is out of range.

### `@floatCast(T, expr)`
Performs an explicit floating-point cast with range checking.
- **Syntax:** `@floatCast(FloatType, float_expression)`
- **Constraints:** Both must be floating-point types (`f32`, `f64`).
- **Compile-time Evaluation:** Constant folding for constant float literals.
- **C89 Emission Strategy:**
  - **Safe widenings** (e.g., `f32` to `f64`): Emitted as a direct C-style cast: `(double)expr`.
  - **Potentially unsafe narrowing** (`f64` to `f32`): Emitted as a call to a runtime helper: `__bootstrap_f32_from_f64(expr)`.

---

## Unsupported Built-ins
Most other Zig built-ins (e.g., `@import`, `@typeInfo`, `@as`) are currently **REJECTED** by the bootstrap compiler to maintain simplicity and C89 compatibility.
