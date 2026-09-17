> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Bootstrap Compiler Built-ins Reference

This document describes the built-in functions (intrinsics) supported by the Z98 bootstrap compiler. These functions start with the `@` symbol and are either evaluated at compile-time or mapped to specific C89 constructs.

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
  - **Runtime Helpers**: These functions (e.g., `__bootstrap_i32_from_i64`) are implemented as `static` functions in `zig_runtime.h`. They perform bounds checks at runtime and call `std_panic` (which traps) if the value is out of range. Under `-fsafe` (default) `@intCast` instead lowers to the checked `zig_cast_checked_s` / `zig_cast_checked_u` helpers; `-ffast` omits the check. The `__bootstrap_panic` wrapper has been removed.

### `@floatCast(T, expr)`
Performs an explicit floating-point cast with range checking.
- **Syntax:** `@floatCast(FloatType, float_expression)`
- **Constraints:** Both must be floating-point types (`f32`, `f64`).
- **Compile-time Evaluation:** Constant folding for constant float literals.
- **C89 Emission Strategy:**
  - **Safe widenings** (e.g., `f32` to `f64`): Emitted as a direct C-style cast: `(double)expr`.
  - **Potentially unsafe narrowing** (`f64` to `f32`): Emitted as a call to a runtime helper: `__bootstrap_f32_from_f64(expr)`.

### `@intToFloat(T, expr)`
Performs an explicit conversion from an integer to a floating-point type.
- **Syntax:** `@intToFloat(FloatType, integer_expression)`
- **Constraints:** `T` must be a floating-point type (`f32`, `f64`), and `expr` must be an integer type.
- **Compile-time Evaluation:** Constant folding for constant integer literals.
- **C89 Emission Strategy:** Emitted as a direct C-style cast: `(double)expr`.

### `@import(path)`
Loads and parses an external Zig module.
- **Syntax:** `@import("relative_path.zig")`
- **Result Type:** `type(module)`
- **Behavior:**
    - Resolves the path relative to the current module's directory.
    - Recursively loads and parses the target file if not already loaded.
    - Detects circular dependencies and reports them as fatal errors.
    - Symbols from the imported module are accessed using dot notation: `const std = @import("std"); std.debug.print(...);`.
- **C89 Emission:** This built-in is handled entirely by the compiler's front-end and import resolution phase. It does not generate any code at the call site. Instead, it influences header generation and symbol resolution.

### Cast Built-ins (Internal/Runtime)
The following built-ins are supported for low-level type conversions:
- **`@enumToInt(enum_expr)`**: Converts an enum value to its underlying integer type.
- **`@intToEnum(T, int_expr)`**: Converts an integer to an enum value of type `T`.
- **`@ptrToInt(ptr_expr)`**: Converts a pointer to its address as a `usize`.
- **`@intToPtr(T, int_expr)`**: Converts a `usize` address to a pointer of type `T`.

---

## Async / Coroutine Built-ins

These built-ins implement cooperative, stackless coroutines. A function is *suspending* when it contains `@asyncSuspend` or calls a suspending function; every suspending function is compiled to a step machine (`__Z98Step_<f>`) instead of its original body. The scheduler and per-task child-frame pool are provided by the `std.async` library. See `Language_Spec_Z98.md` §4.1 and `sf/docs/tech_docs/12_async_coroutines.md`.

### `@asyncFrameSize(fn)`
Compile-time-evaluated: returns the byte size of the root frame `fn` needs.
- **Syntax:** `@asyncFrameSize(suspending_fn)`
- **Constraints:** `fn` must resolve to a known suspending function, else `error[3046]`.
- **C89 Emission:** Emitted directly as the integer literal.

### `@asyncInit(ctx, buf, fn, args)`
Initializes a coroutine root frame in `buf` for the suspending function `fn` and returns it as `*void`.
- **Syntax:** `@asyncInit(ctx, buf, fn, @ptrCast(*const void, &args_record))`
- **Behavior:** zero-fills the frame, writes the `__Z98Step_<fn>` step word at frame offset 0, stores `ctx` and `state = 0`, resets the context header (`used = 0`, sticky `oom = 0`), and copies the `args` record **positionally** into `fn`'s parameters (the record's fields are the coroutine's parameters).
- **Constraints:** `args` must be a plain `*const void` (a `?*const void` is a non-scalar optional and emits invalid C89).
- **C89 Emission:** `-fsafe` traps when the frame size is compile-time known and `buf` is a concrete `[N]u8` array with `N < @asyncFrameSize(fn)`; `-ffast` omits the check.

### `@asyncSuspend(data)`
An explicit suspension point inside a suspending function.
- **Syntax:** `@asyncSuspend(data)`
- **Constraints:** Only valid inside a suspending function (`error[3018]` otherwise); rejected inside `defer`/`errdefer` (`error[3019]`).
- **C89 Emission:** The step saves its live frame fields, records the next state, and returns a non-`null` `?*void` sentinel. The `data` operand is type-checked but not propagated.

### `@asyncResume(frame, arg)`
Resumes the coroutine rooted at `frame`.
- **Syntax:** `@asyncResume(frame, arg)`
- **Result Type:** `?*void` — `null` when the coroutine has finished, non-`null` while it is still suspended.
- **C89 Emission:** Loads the step word at `frame + 0`, calls `__Z98Step_<f>(frame, arg)`, and returns its result. `-fsafe` traps if the step word is zero; `-ffast` is undefined behavior.

---

## Unsupported Built-ins
Most other Zig built-ins (e.g., `@typeInfo`, `@as`, `@typeName`) are currently **REJECTED** by the bootstrap compiler to maintain simplicity and C89 compatibility.
