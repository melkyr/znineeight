# Baptism of Water: Lisp Interpreter - Missing Features and Compiler Challenges

This document details the challenges encountered while building the Z98 Lisp interpreter ("Baptism of Water") using the `retrozig` bootstrap compiler. It highlights the gaps between the current compiler implementation and the requirements of a multi-module project.

## Current Status (Updated 2025-01-24)

**Zig-to-C compilation succeeds!** The compiler correctly processes the multi-module Lisp interpreter source and generates C89 code. However, the generated C code still requires minor manual adjustments or compiler fixes to compile successfully into a 32-bit binary.

### Peak Memory Usage Analysis (Valgrind Massif)
During the compilation of the Lisp interpreter:
- **Peak Memory**: ~6.4 MB (well within the 16MB constraint).
- **Primary Contributors**:
    - **Emitter Buffers (~3.1 MB)**: The `C89Emitter` allocates a 128 KB `type_def_buffer_` for every generated file. With the number of modules in the Lisp interpreter, these accumulate.
    - **AST Transformation (~1 MB)**: `ControlFlowLifter` uses significant memory for its `DynamicArray<ASTNode*>` during complex expression lifting.
    - **Token Supply (~1 MB)**: Memory used for the token stream across all modules.
    - **Symbol Table (~1 MB)**: Overhead for global symbol tracking.

**Conclusion**: Memory usage is well within the 16MB target.

---

## 1. Type Consistency (Cross-Module Type Identity) - **RESOLVED**

### The Problem
Previously, identical types imported by different modules were treated as distinct.

### Current Status
**Resolved.** The `TypeChecker` now correctly identifies structurally equal nominal types across module boundaries.

---

## 2. Placeholder Resolution and Circular Dependencies - **RESOLVED**

### The Problem
Recursive types used to trigger assertion failures.

### Current Status
**Resolved.** The two-phase placeholder strategy in `TypeChecker` handles the Lisp interpreter's recursive structures (like `Value` and `EnvNode`).

---

## 3. C Code Generation: Optional Pointer Access - **RESOLVED**

### The Problem
Incorrect precedence for optional/error union member access via pointers.

### Current Status
**Resolved.** The `C89Emitter` now generates correctly parenthesized code: `(*env).has_value = 1;`.

---

## 4. C Code Generation: Missing Type Definitions - **STILL OPEN**

### The Problem
Generated types like `Slice_u8` and `Slice_Ptr_z_value_Value` are defined in `zig_special_types.h`, but this file is not automatically included in the generated `.c` or `.h` files.

### Symptoms
Compilation fails with "unknown type name 'Slice_u8'" and similar errors.

### Workaround
Manually including `zig_special_types.h` or using a compiler flag like `-include o_lisp/zig_special_types.h` is required.

### Bug Reproduction
`examples/lisp_interpreter/bugrepro/missing_slice_def.zig`

---

## 5. The `main` Function Return Type - **RESOLVED**

### Current Status
The `C89Emitter` correctly generates `int main(int argc, char* argv[])` for `pub fn main() void`.

---

## 6. Missing Runtime Helpers - **RESOLVED**

### Current Status
The required conversion helpers (e.g., `__bootstrap_u8_from_i32`) are now present in `src/include/zig_runtime.h`.

---

## 7. Include Order in `zig_runtime.h` - **OPEN**

### The Problem
`zig_runtime.h` includes `zig_special_types.h` at the top, but `zig_special_types.h` uses `usize` which is defined later in `zig_runtime.h`.

### Symptoms
Compilation fails with "unknown type name 'usize'" in `zig_special_types.h`.

### Required Fix
Move the inclusion of `zig_special_types.h` after the definition of `usize` and `isize` in `zig_runtime.h`.

### Bug Reproduction
`examples/lisp_interpreter/bugrepro/missing_slice_def.zig`

---

## 8. Single Translation Unit (STU) Compilation - **OPEN**

### The Problem
The compiler generates a `main.c` file that includes all other generated `.c` files. This is intended to allow for a single compilation command. However, because each individual `.c` file also includes the headers for its dependencies, this leads to "multiple definition" errors during the link phase if all `.c` files are passed to the compiler.

### Symptoms
`multiple definition of 'z_util_mem_eql'`, etc.

### Workaround
Compile using only the master `main.c` and the runtime:
`gcc -m32 -std=c89 -O2 -I. -o lisp_repl main.c ../src/runtime/zig_runtime.c`

---

## 9. False Positive "Unresolved call" Warnings - **OPEN**

### The Problem
The `CallResolutionValidator` (active in DEBUG builds) reports built-in functions (like `@intCast`, `@ptrCast`, `@sizeOf`) as unresolved calls because it doesn't recognize them as built-ins.

### Symptoms
`Unresolved call at ... in context '...'` lines in the compiler output, even though C code generation succeeds.

### Bug Reproduction
`examples/lisp_interpreter/bugrepro/builtin_warning.zig`

---

## 10. ISO C Warnings in 32-bit Mode - **OPEN**

### The Problem
When compiling with `-m32 -std=c89 -pedantic`, the generated code triggers warnings related to 1998-era C constraints.

### Symptoms
- `warning: ISO C90 does not support ‘long long’` (Z98 uses `i64` which maps to `long long`).

---

## 11. Bitwise NOT Support - **RESOLVED**

### Current Status
Bitwise NOT (`~`) is supported for integer types and correctly emitted to C.

### Verification
`examples/lisp_interpreter/bugrepro/bitwise_not.zig`

---

## 12. Tagged Union Support - **RESOLVED**

### Current Status
`union(enum)` types and `switch` payload captures are fully supported and correctly emitted to C89.

### Verification
`examples/lisp_interpreter/bugrepro/tagged_union.zig`
