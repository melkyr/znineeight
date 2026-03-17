# Findings from the JSON Parser "Baptism of Fire"

This document records the issues, bugs, and limitations discovered while attempting to compile and run both an "Advanced" (using modern Zig features) and "Downgraded" (using workarounds) Z98 JSON parser.

## 1. Advanced Version (Modern Zig Features)
**Status**: **FAILED TO COMPILE**

The advanced version attempted to use `union(enum)` and switch captures. Several blockers were identified:

### 1.1 Structural Limitations
- **Methods in Structs**: The compiler explicitly rejects methods inside struct declarations with a hint: "Methods are not supported in struct declarations in bootstrap compiler".
- **Recursive Type Cycle Detection**: Types containing slices of themselves (e.g., `Object: []struct { key: []const u8, value: JsonValue }`) trigger a "cycle detected" error.
    - **Resolution**: Use pointer indirection for recursive fields (e.g., `value: *JsonValue`).
- **Anonymous Structure Equality**: The compiler sometimes fails to unify identical anonymous structures, leading to errors like `Incompatible assignment: '[]struct {...}' to '[]struct {...}'`.

### 1.2 Syntax & Built-in Limitations
- **Member Access on String Literals**: Using `"string".ptr` is rejected with "member access '.' only allowed on structs, unions, enums or pointers to structs/unions". This is because string literals are treated as constant arrays or pointers-to-arrays, but the bootstrap compiler doesn't expose the `.ptr` and `.len` properties on them as if they were slices.
- **Switch Condition Types**: Switches on complex types or using captures are still fragile.
- **@sizeOf on Incomplete Types**: Applying `@sizeOf` to a type that is still being defined or is a `comptime` parameter often fails.

## 2. Upgraded Version (Modern Zig Features - Refined)
**Status**: **COMPILED AND RUN**

A middle ground between the advanced and downgraded versions was successful.

### 2.1 Successes
- **Tagged Unions (`union(enum)`)**: Fully supported and functional. The compiler correctly emits C structs with a tag and data union.
- **Switch Captures**: Switch captures (e.g., `.String => |s|`) are fully functional and generate correct C code.
- **Switch Expressions**: Switch expressions are correctly lifted into statements by the `ControlFlowLifter`.
- **Recursive Slices**: Slices of the type currently being defined (e.g., `Array: []JsonValue`) are now fully supported, provided they are not nested inside another anonymous aggregate that would trigger a value cycle.

### 2.2 Remaining Limitations
- **Anonymous Aggregate Cycle Detection**: Direct embedding of a type within itself via an anonymous struct (e.g., `Object: []struct { key: []const u8, value: JsonValue }`) is still rejected as a cycle.
    - **Workaround**: Use pointer indirection for the recursive field (`value: *JsonValue`).
- **Naked Tag Constraints**: Returning a tag directly (e.g., `return .Null`) is supported, but assigning it to an `undefined` variable might require an explicit union initializer in some contexts.

## 3. Core Technical Constraints

### 3.1 32-bit ABI
The bootstrap compiler assumes a **32-bit little-endian target** (4-byte pointers, 8-byte slices). Compiling generated C code on a 64-bit host without the `-m32` flag results in memory corruption due to offset shifts in structs and unions.

### 3.2 1998 Compatibility
- **C++98**: The compiler uses no modern C++ features.
- **MSVC 6.0**: Uses `__int64` and manual boolean definitions for compatibility.

## 4. Summary Table

| Feature | Status | Workaround / Note |
|---------|--------|-------------------|
| `union(enum)` | **SUPPORTED** | Works for standard tagged unions. |
| Switch Captures | **SUPPORTED** | Functional in C89 emission. |
| Methods | Unsupported | Use standalone functions. |
| Value Cycles | Unsupported | Use explicit pointers (`*T`) for recursion. |
| Recursive Slices| **SUPPORTED** | Size is constant (8 bytes), so cycles are avoided. |
| 64-bit Support | **NOT SUPPORTED** | The bootstrap compiler is strictly a 32-bit cross-compiler. |
