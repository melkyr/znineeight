# Bootstrap Compiler Built-ins Reference

This document describes the built-in functions (intrinsics) supported by the RetroZig bootstrap compiler. These functions start with the `@` symbol and are either evaluated at compile-time or mapped to specific C89 constructs.

## Compile-Time Evaluated Built-ins

These built-ins are evaluated during the Type Checking phase and are replaced in the Abstract Syntax Tree (AST) with constant integer literals.

### `@sizeOf(T)`
Returns the size of type `T` in bytes as a `usize` constant.
- **Syntax:** `@sizeOf(TypeName)`
- **Constraints:** `T` must be a complete type.
- **Target (32-bit):**
  - `i32`, `u32`, `f32`, `*T`, `usize`, `isize`: 4 bytes
  - `i64`, `u64`, `f64`: 8 bytes
  - `struct`: Sum of field sizes plus padding for alignment.

### `@alignOf(T)`
Returns the alignment requirement of type `T` in bytes as a `usize` constant.
- **Syntax:** `@alignOf(TypeName)`
- **Constraints:** `T` must be a complete type.
- **Target (32-bit):**
  - `i32`, `u32`, `f32`, `*T`, `usize`, `isize`: 4 bytes
  - `i64`, `u64`, `f64`: 8 bytes

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
- **Compile-time:** If `expr` is a constant literal and fits in `T`, it is folded into a constant. Overflow is a compile error.
- **Runtime:** If not constant, emits a call to a runtime helper: `__bootstrap_<target>_from_<source>(expr)`. The helper performs range checking and panics on overflow.
- **Widenings:** If the cast is a safe widening (e.g., `u8` to `i32`), a simple C cast `(target_type)expr` is emitted without runtime checks.

### `@floatCast(T, expr)`
Performs an explicit floating-point cast.
- **Syntax:** `@floatCast(FloatType, float_expression)`
- **Constraints:** Both must be floating-point types.
- **Compile-time:** Constant folding for float literals.
- **Runtime:** Range checking for `f64` to `f32`. safe widening (e.g., `f32` to `f64`) uses a simple C cast.

### `@offsetOf(T, field_name)`
Returns the byte offset of a field within a struct.
- **Syntax:** `@offsetOf(StructType, "field")`
- **C89 Emission:** `offsetof(struct StructType, field)`

---

## Unsupported Built-ins
Most other Zig built-ins (e.g., `@import`, `@typeInfo`, `@as`) are currently **REJECTED** by the bootstrap compiler to maintain simplicity and C89 compatibility.
