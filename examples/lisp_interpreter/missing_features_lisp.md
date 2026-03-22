# Baptism of Water: Lisp Interpreter - Missing Features and Compiler Challenges

This document details the challenges encountered while building the Z98 Lisp interpreter ("Baptism of Water") using the `retrozig` bootstrap compiler. It highlights the gaps between the current compiler implementation and the requirements of a multi-module project.

## Current Status (Updated 2024-03-22)

**Zig-to-C compilation now succeeds!** The compiler correctly processes the multi-module Lisp interpreter source and generates C89 code. However, the generated C code contains semantic errors that prevent final binary compilation.

### Memory Usage Report (Valgrind)
During the compilation of the Lisp interpreter:
- **Total Heap Usage**: ~7.4 MB allocated.
- **Peak Memory**: Well within the 16MB constraint for the 1998 target.
- **Leaks**: ~23 KB definitely lost (primarily in source file reading and import resolution).

---

## 1. Type Consistency (Cross-Module Type Identity) - **IMPROVED**

### The Problem
Previously, identical types imported by different modules were treated as distinct, causing "type mismatch" errors.

### Current Status
**Resolved in Zig-to-C phase.** The `TypeChecker` now correctly identifies structurally equal nominal types across module boundaries. `zig0` successfully completes the semantic analysis of the entire Lisp interpreter without reporting incompatible assignments for these types.

---

## 2. Placeholder Resolution and Circular Dependencies - **IMPROVED**

### The Problem
Recursive types (e.g., `Value` -> `ConsData` -> `Value`) used to trigger assertion failures or resolution loops.

### Current Status
**Resolved.** The two-phase placeholder strategy and multi-pass resolution in `TypeChecker` allow the Lisp interpreter's recursive structures to be fully resolved.

---

## 3. C Code Generation: Optional Pointer Access - **NEW BUG**

### The Problem
When an optional type is passed by reference (e.g., `*?*EnvNode`), the compiler generates invalid C code for member access.

### Symptoms
In `eval.c`:
```c
/* Invalid C code */
*env.has_value = 1;
*env.value = __tmp_try_13_41;
```
The compiler emits `*ptr.member` which has incorrect precedence (accessing `.member` of `ptr` and then dereferencing).

### Required Fix
The `C89Emitter` should use the arrow operator `->` or parentheses `(*ptr).member` when the base of an optional/error union operation is a pointer.

---

## 4. C Code Generation: Missing Type Definitions - **NEW BUG**

### The Problem
Type definitions like slices or error unions are sometimes missing from the header or source files where they are used, even if they are defined in another module.

### Symptoms
`eval.c` uses `Slice_Ptr_z_value_Value` but the definition is only present in `builtins.h`. Since `eval.c` doesn't include `builtins.h` in a way that makes the typedef available before use, C compilation fails.

### Required Fix
Improve `CBackend` dependency scanning to ensure all required `Slice`, `Optional`, and `ErrorUnion` types are emitted in every module that uses them, or centrally in a shared header.

---

## 5. The `main` Function Return Type - **IMPROVED**

### Current Status
The `C89Emitter` now correctly handles `pub fn main() void` by generating an `int main(int argc, char* argv[])` that returns `0` at the end of its block.

---

## 6. General Recommendations for the Bootstrap Compiler

1. **C89 Operator Precedence**: Review all generated C expressions to ensure correct parenthesization, especially for dereferences and member access.
2. **Global Type Registry for C**: Move special type definitions (`Slice_`, `Optional_`, etc.) into a common header included by all modules to prevent "unknown type name" errors.
3. **Signedness of String Literals**: Zig's `[]const u8` maps to `unsigned char*`, but C string literals are `char*`. This generates numerous warnings. A consistent cast or configuration is needed.
4. **Function Pointer Casts**: Builtin registration currently casts function pointers to `void*`, which is technically prohibited by ISO C.
