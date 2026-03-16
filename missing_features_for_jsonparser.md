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
- **Recommendation**: Always compile the generated C code with `-m32` or on a native 32-bit platform. If `-m32` is unavailable, manual "copy-field-by-field" workarounds in Zig are needed to avoid reliance on C's struct assignment/copying which may differ in layout.

### Incomplete Type definition order
- **Status**: **RESOLVED** (Task 9.13).
- **Observation**: Named aggregates are now emitted first in topological dependency order, ensuring definitions are complete before use in special types.

## 4. Successful Features Verified
- **@import**: Works across multiple files.
- **Tagged Unions (union(enum))**: Fully functional with switch captures.
- **Error Unions**: `FileError![]u8` works correctly with `try` and `catch`.
- **Extern C Interop**: `fopen`, `fread`, etc., are correctly called with `@ptrCast`.
- **Slices**: `.len` and `.ptr` properties work.
- **Many-item Pointers**: `[*]u8` works for C string interop.
- **AST Lifting**: Complex expression-valued control flow is correctly transformed into statements.
- **Single Translation Unit (STU)**: Unified compilation of modular programs verified.
