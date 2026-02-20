# Slices Implementation Reference

This document provides a comprehensive overview of the Slice support implementation in the RetroZig bootstrap compiler.

## 1. Type Representation

Slices are represented as structural types in the `TypeSystem`.

- **Type Kind**: `TYPE_SLICE`
- **Internal Structure**:
    ```cpp
    struct SliceDetails {
        Type* element_type;
        bool is_const;
    };
    ```
- **Memory Layout (32-bit Target)**:
    - **Size**: 8 bytes (4-byte pointer + 4-byte `size_t`)
    - **Alignment**: 4 bytes
- **C89 Mapping**: Slices are emitted as a C structure. For example, `[]i32` maps to:
    ```c
    typedef struct {
        int* ptr;
        size_t len;
    } Slice_i32;
    ```

## 2. Parsing Syntax

The parser handles slice types and slicing expressions using standard Zig syntax.

- **Type Expressions**: `[]T` and `[]const T`.
- **Slicing Expressions**: `base[start..end]`.
    - **Arrays and Slices**: Support omitted indices (e.g., `arr[..]`, `arr[5..]`, `arr[..10]`).
    - **Many-item Pointers**: Require both `start` and `end` to be explicitly provided.

## 3. Semantic Analysis (Type Checker)

The `TypeChecker` validates slice usage and prepares the AST for code generation.

### 3.1 Validation Rules
- **Sliceable Types**: Only arrays (`[N]T`), slices (`[]T`), and many-item pointers (`[*]T`) can be sliced.
- **Index Types**: `start` and `end` indices must be integer types or `usize`.
- **Const Propagation**: Slicing a constant object (e.g., a `const` array or a `[]const T` slice) always results in a constant slice (`[]const T`).
- **Bounds Checking**: For fixed-size arrays, if indices are compile-time constants, the compiler verifies that `0 <= start <= end <= N`.

### 3.2 Implicit Coercion
The compiler supports implicit coercion from a fixed-size array `[N]T` to a slice `[]T` (or `[]const T`) if the element types match.

### 3.3 Built-in Properties
Slices have a built-in `.len` property which returns a `usize`. Accessing this property is handled as a standard member access in the AST.

## 4. Codegen Preparation

During the type checking phase, the `ASTArraySliceNode` is populated with synthetic expressions to simplify C89 emission:

- **`base_ptr`**: An expression representing the raw pointer to the start of the slice.
    - Array: `&arr[start]`
    - Slice: `arr.ptr + start`
    - Pointer: `ptr + start`
- **`len`**: An expression representing the number of elements in the slice.
    - `end - start` (or derived from base length if omitted).

## 5. C89 Emission Strategy (Planned)

Phase 4 and 5 will implement the following emission rules:

- **Type Definitions**: The `CBackend` will generate a `typedef` for each unique slice type encountered in the compilation unit.
- **Helper Functions**: Static inline helper functions (e.g., `__make_slice_i32(ptr, len)`) will be generated to construct slice structures from pointer and length components.
- **Operations**:
    - **Indexing**: `slice[i]` -> `slice.ptr[i]`
    - **Length**: `slice.len` -> `slice.len`
    - **Slicing**: Emitted as a call to the corresponding `__make_slice` helper.
