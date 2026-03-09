# Missing Features and Issues for JSON Parser in Z98

This document tracks the issues encountered during the "Baptism of Fire" for the RetroZig compiler using a modular JSON parser example.

## Encountered Issues

### 1. Mandatory Braced Blocks
The bootstrap compiler requires all `if`, `while`, and `for` statements to use braced blocks `{ ... }`, even for single statements.
- **Example failing code:** `if (cond) return error.Fail;`
- **Workaround:** Use `if (cond) { return error.Fail; }`

### 2. No Struct Methods
Methods declared inside a `struct` block are not supported.
- **Example failing code:**
  ```zig
  const Parser = struct {
      fn peek(self: *Parser) u8 { ... }
  };
  ```
- **Workaround:** Use standalone functions that take a pointer to the struct as the first argument.

### 3. Strict Type Compatibility for Literals
The compiler does not implicitly coerce `i32` literals (like `0`) to `usize` in assignments or struct initializers.
- **Example failing code:** `.pos = 0` (where `pos` is `usize`)
- **Workaround:** Use unsigned literals: `.pos = 0u`

### 4. Recursive Type Layout
Encountered `error: type mismatch` with hint `field 'value' has incomplete type '(placeholder) JsonValue'` when a struct contains a slice of another struct that contains the first struct by value.
- **Example:**
  ```zig
  const JsonValue = struct {
      data: union {
          object: []struct { key: []const u8, value: JsonValue },
      },
  };
  ```
- **Status:** Investigating if this is a limitation of anonymous structs or recursive types in general.

### 5. Member Access on Literals
Accessing `.ptr` on a string literal directly is not supported.
- **Example failing code:** `"rb".ptr`
- **Workaround:** Assign the literal to a `[]const u8` variable first.

### 6. Compiler Segmentation Fault (Resolved via Refactoring)
The compiler initially segfaulted on complex ASTs. This was mitigated by avoiding nested anonymous structs and ensuring all types are named. It appears the lifter or type-checker might have issues with deeply nested anonymous structures.

### 7. C Interop: Optional Pointers vs. C ABI
The compiler maps `?*T` to a struct `{ T* value, int has_value }`. This is **not** ABI-compatible with C functions that expect or return nullable pointers (which are just `T*` where `NULL` is the none value).
- **Example failing code:** `extern fn fopen(...) ?*File;` generates `Optional_Ptr_void fopen(...)` in C, which conflicts with standard `FILE* fopen(...)`.
- **Workaround:** Use a bare pointer `*File` and check for null by casting to `usize` or similar, or provide a C wrapper.

### 8. Anonymous Union Emission Bug
The C89 emitter fails to emit the body of anonymous unions within structs in the generated header files.
- **Example failing code:**
  ```zig
  data: union { boolean: bool, ... }
  ```
  Generates:
  ```c
  union /* anonymous */ data;
  ```
  This is invalid C and causes "has no member named 'data'" errors because the members aren't defined.
- **Workaround:** Use a named union. For example, move the union to a top-level `const Data = union { ... };` and use that type within the struct.

### 9. Standard Library Conflicts
`zig_runtime.h` includes `<stdio.h>`, which pre-defines functions like `fopen`, `fread`, etc. Declaring them as `extern fn` in Zig with even slightly different signatures (e.g., using `u8` instead of `char`) causes C compilation errors.
- **Workaround:** Ensure Zig `extern` declarations perfectly match the C standard library if you intend to link against it.

## Pending Investigation
- [x] Support for `[]T` where `T` is the struct currently being defined. (Works if named).
- [x] Anonymous struct support within unions/slices. (Causes issues, avoid for now).
- [ ] Investigation into why the C89 emitter uses `->` for union members (e.g., `val.data->boolean`) when `data` is a union member of a struct (should be `val.data.boolean`). This suggests the emitter thinks `data` is a pointer.
