# Missing Features for JSON Parser

During the "baptism of fire" compilation of the JSON parser example, the following features were found to be missing or limited in the current RetroZig bootstrap compiler (Z98):

## 1. Tagged Unions (`union(enum)`)
- **Status**: Not supported in Z98.
- **Observation**: The parser fails with a syntax error when encountering `union(enum)`.
- **Workaround**: Manually implement tagged unions using a `struct` containing an `enum` tag and a bare `union` for the data.
- **Example of failure**:
  ```zig
  pub const JsonValue = union(enum) { ... }; // Syntax Error
  ```

## 2. Switch Payload Capture
- **Status**: Not supported in Z98.
- **Observation**: The parser expects a block `{}` for switch arms and does not recognize the `|payload|` capture syntax.
- **Workaround**: Use explicit member access after checking the tag in a manual tagged union.
- **Example of failure**:
  ```zig
  switch (val) {
      .Boolean => |b| { ... } // Syntax Error
  }
  ```

## 3. Braceless `if` and `while`
- **Status**: Not supported in Z98.
- **Observation**: The parser strictly requires `{}` for the bodies of `if`, `else`, `while`, etc.
- **Example of failure**:
  ```zig
  if (cond) return err; // Syntax Error: Expected '{'
  ```

## 4. Range-based `switch` arms
- **Status**: Uncertain/Limited.
- **Observation**: While `NODE_RANGE` exists, the JSON parser example was downgraded to avoid complex switch logic to ensure first-pass success.

## 5. String Literals as Slices in Comparisons
- **Status**: Limited.
- **Observation**: Expressions like `p.input[p.pos..][0..4] == "null"` are not reliably handled in the bootstrap phase.
- **Workaround**: Use manual byte-by-byte comparison or explicit C-interop helpers.

## 6. `@ptrCast` and `[*]T` usage
- **Status**: Sensitive.
- **Observation**: The compiler is strict about pointer types. Using `[*]T` (many-item pointer) and explicit `@ptrCast` is often necessary when interacting with C-like buffers or slices.

## 7. `defer` without blocks
- **Status**: Not supported.
- **Observation**: `defer _ = fclose(f);` failed; `defer { _ = fclose(f); }` is required.

## 8. `comptime` parameters
- **Status**: Syntactically recognized but limited in effect.
- **Observation**: Generic-like behavior (e.g., `fn alloc(..., comptime T: type, ...)` ) is not fully realized in the bootstrap compiler's type system for custom functions.
- **Workaround**: Use `usize` and manual `@ptrCast`.

## 9. Potential Struct/Union Layout Mismatches
- **Status**: Investigating.
- **Observation**: When returning structs containing unions by value, or when accessing them via pointers in the arena, the `tag` field or union data sometimes appears corrupted or misaligned in the generated C code.
- **Impact**: This led to segmentation faults or incorrect logic branches in the JSON printer.
- **Recommendation**: For bootstrap-critical code, keep aggregate types simple and avoid deep nesting of unions within structs if possible, or use explicit padding/alignment if the C compiler's behavior is known.
