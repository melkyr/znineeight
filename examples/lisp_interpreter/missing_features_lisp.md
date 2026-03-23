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

---

## 5. The `main` Function Return Type - **RESOLVED**

### Current Status
The `C89Emitter` correctly generates `int main(int argc, char* argv[])` for `pub fn main() void`.

---

## 6. Missing Runtime Helpers - **NEW**

### The Problem
The compiler generates calls to helper functions that are missing from the `zig_runtime.h` / `zig_runtime.c` files.

### Symptoms
Warning/Error: `implicit declaration of function ‘__bootstrap_u8_from_i32’`.

### Required Fix
Add `__bootstrap_u8_from_i32` and similar conversion helpers to the runtime library.
