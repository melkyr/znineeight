# Findings from the JSON Parser "Baptism of Fire"

This document records the issues, bugs, and limitations discovered while attempting to compile a modern Z98 JSON parser.

## 1. Syntax & Parser Constraints

### Braceless Switch Prongs Semicolon Requirement
- **Status**: **RESOLVED** (Phase 6 Fix).
- **Observation**: Switch prong bodies are now parsed using `parseExpression()`. This eliminates the semicolon requirement before the comma. Zig-style comma rules are enforced: mandatory for non-block prongs unless it is the final prong.

### Braceless `if`/`while` bodies
- **Status**: Supported, but normalized to blocks in the lifter.

### Switch Capture Limitations
- **Status**: Supported for tagged unions.
- **Observation**: Capture requires a tag name case item (e.g., `.String => |s|`).

## 2. Type System & Semantic Analysis

### Recursive Type Completeness (Value Cycles)
- **Status**: **LIMITATION IDENTIFIED**.
- **Observation**: Types containing slices of themselves (e.g., `Array: []JsonValue` inside `JsonValue`) result in "incomplete type" errors during layout calculation because the compiler attempts to calculate the size of the slice which depends on the element type.
- **Workaround**: Use pointers for recursion (e.g., `value: *JsonValue`). Slices of a type can be used once the type is complete, but not during its own definition.

### Comptime Type Parameters and @sizeOf
- **Status**: **LIMITATION IDENTIFIED**.
- **Observation**: Functions using `comptime T: type` (e.g., `alloc(arena, T, count)`) fail when calling `@sizeOf(T)` if `T` is treated as an incomplete type parameter. The bootstrap compiler's generic support is limited.
- **Workaround**: Use byte-oriented allocators and `@ptrCast` at the call site, or specialized functions.

### Anonymous Initializer Contextual Inference
- **Status**: **IMPROVED** (Phase 9c).
- **Observation**: Returning `.Null` or `.{ .Boolean = true }` directly in switch prongs or function returns sometimes fails type matching if the expected type isn't propagated correctly through all layers (especially through `try` or complex expressions).
- **Workaround**: Explicitly type the initializer (e.g., `JsonValue.Null`) or use a temporary variable with an explicit type.

### Strict Assignment Compatibility
- **Status**: Enforced.
- **Observation**: The compiler is very strict about identical types in assignments and struct initializers. `i32` literals do not always implicitly coerce to `usize` in these contexts.
- **Workaround**: Use explicit `@intCast(usize, ...)` or ensure literals are compatible.

## 3. Code Generation Bugs & Gaps

### Expression-as-Statement Emission
- **Status**: **RESOLVED** (Post-Baptism Fix).
- **Observation**: Previously, expression nodes (like `return try ...` or simple binary ops) used directly as statements in contexts like `switch` prongs were incorrectly handled, leading to "Unimplemented statement type" comments in the C output.
- **Fix**: Updated `C89Emitter::emitStatement` to treat standard expression nodes as valid expression-statements, ensuring they are emitted followed by a semicolon.

### `break`/`continue` Ambiguity in `switch`
- **Status**: **BUG IDENTIFIED**.
- **Observation**: Using `break` inside a `switch` that is itself inside a `while` loop emits a C `break`. In C, this only breaks the `switch`, whereas in Zig it should break the `while`. This leads to infinite loops.
- **Workaround**: Use `return` or labeled breaks if available, or ensure the compiler always uses `goto` for breaks targeting loops.

### Tagged Union Forward Declaration Bug
- **Status**: **RESOLVED**.
- **Observation**: Forward declarations for tagged unions are now correctly emitted using the `struct` keyword in C headers and sources.

### `unreachable` Statement Missing Emission
- **Status**: **RESOLVED**.
- **Observation**: `unreachable` statements now correctly emit a `__bootstrap_panic` call.

### 32-bit vs 64-bit ABI Mismatch
- **Status**: **CORE LIMITATION**.
- **Observation**: The RetroZig bootstrap compiler is hardcoded with 32-bit target assumptions (4-byte pointers, 8-byte slices, 4-byte alignment). When generating C code for a 64-bit host, `@sizeOf` values and struct layouts mismatch the 64-bit C compiler's expectations.
- **Impact**: Severe memory corruption (segmentation faults) when accessing fields of structs/unions via pointers in 64-bit binaries.
- **Recommendation**: Always compile the generated C code with `-m32` or on a native 32-bit platform.

## 4. Successful Features Verified
- **Multi-file Modular Programs**: `@import` works across multiple files and correctly links the STU.
- **Modern Control Flow**: `switch` with ranges and tagged union captures are fully functional.
- **Error Handling**: `try` and `catch` correctly propagate and handle errors.
- **Braceless Syntax**: `if`, `while`, and `defer` can be used without braces for single statements.
- **C Interop**: Pointer casts and extern function calls are working as intended.
