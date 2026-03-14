# Findings from the JSON Parser "Baptism of Fire"

This document records the issues, bugs, and limitations discovered while attempting to compile a modern Z98 JSON parser.

## 1. Syntax & Parser Constraints

### Braceless Switch Prongs Semicolon Requirement
- **Status**: Required.
- **Observation**: When using the `=>` syntax in a switch without braces, a semicolon is required before the comma if the body is a statement (like `return`).
- **Example**:
  ```zig
  switch (ch) {
      'n' => return try parseNull(p);, // Semicolon required here
      else => return error.ExpectedValue;,
  }
  ```

### Braceless `if`/`while` bodies
- **Status**: Supported, but normalized to blocks in the lifter.

### Switch Capture Limitations
- **Status**: Supported for tagged unions, but the syntax is sensitive. Braces are recommended for complex bodies.

## 2. Type System & Semantic Analysis

### Recursive Type Completeness
- **Status**: Pointers required.
- **Observation**: Types containing slices of themselves (e.g., `Array: []JsonValue` inside `JsonValue`) often result in "incomplete type" errors during layout calculation.
- **Workaround**: Use pointers for recursion (e.g., `value: *JsonValue`).

### Strict Assignment Compatibility
- **Status**: Enforced.
- **Observation**: The compiler is very strict about identical types in assignments and struct initializers. `i32` literals do not always implicitly coerce to `usize` in these contexts.
- **Workaround**: Use explicit types or ensured literals (e.g., `const zero: usize = 0;`).

### If Expression Branch Consistency
- **Status**: Enforced.
- **Observation**: Branches of an `if` expression must have exactly the same type. No implicit widening between branches.

## 3. Code Generation Bugs & Gaps

### Tagged Union Forward Declaration Bug
- **Status**: **BUG IDENTIFIED**.
- **Observation**: Tagged unions are correctly identified as C `structs` in their definitions (Pass 1), but the `CBackend` incorrectly forward-declares them using the `union` keyword in the generated `.h` files (Pass 0).
- **Impact**: Causes `gcc` error: "defined as wrong kind of tag".
- **Workaround**: Manually implement tagged unions using a `struct` with an `enum` tag and a bare `union` for data.

### `unreachable` Statement Missing Emission
- **Status**: **GAP IDENTIFIED**.
- **Observation**: The `unreachable` expression is recognized by the parser but results in `/* Unimplemented statement type 4 */` in the generated C code when used as a statement.

### Header Dependency Cycle with Error Unions
- **Status**: **LIMITATION IDENTIFIED**.
- **Observation**: When a function returns a recursive struct by value in an error union (e.g., `fn foo() !RecursiveStruct`), the generated header emits the `ErrorUnion_RecursiveStruct` definition *before* the `struct RecursiveStruct` definition. In C89, a struct member must be a complete type, so this fails.
- **Workaround**: Return a pointer instead (e.g., `fn foo() !*RecursiveStruct`).

### 32-bit vs 64-bit ABI Mismatch
- **Status**: **CORE LIMITATION**.
- **Observation**: The RetroZig bootstrap compiler is hardcoded with 32-bit target assumptions (4-byte pointers, 8-byte slices, 4-byte alignment). When generating C code for a 64-bit host, `@sizeOf` values and struct layouts mismatch the 64-bit C compiler's expectations.
- **Impact**: Severe memory corruption and incorrect behavior at runtime when compiled as 64-bit.
- **Recommendation**: Always compile the generated C code with `-m32` or on a native 32-bit platform. If `-m32` is unavailable, the bootstrap compiler's `type_system.cpp` must be updated to 64-bit assumptions.

### Incomplete Type definition order
- **Status**: Investigating.
- **Observation**: Even with pointers, if a struct refers back to a union that is still being defined, order of emission in the header can cause issues if not forward-declared correctly.

## 4. Successful Features Verified
- **@import**: Works across multiple files.
- **Error Unions**: `FileError![]u8` works correctly with `try` and `catch`.
- **Extern C Interop**: `fopen`, `fread`, etc., are correctly called with `@ptrCast`.
- **Slices**: `.len` and `.ptr` properties work.
- **Many-item Pointers**: `[*]u8` works for C string interop.
- **AST Lifting**: Complex `catch` expressions in `main.zig` were correctly lifted into temporary-variable-based statements.
- **Single Translation Unit (STU)**: The generated `main.c` correctly includes all module files for a unified compilation.
