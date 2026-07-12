# func_ptr_return_type — RED

## What it does
Function `getOp` returns a function pointer (`fn(i32,i32) i32`). `main` calls the returned pointer with `(10, 5)` and prints the result — expects `15` once fixed.

## zig1 RED evidence
- **dump rc:** 0
- **gcc error (7 errors):** `unknown type name 'zT_DDF5E411_FP_int_int_int'`
  - Lines 12, 34, 51, 54, 56, 64 of generated C reference the typedef, but it is never emitted.

## Oracle (zig0)
- **Source 1:** `examples/zig0/func_ptr_return/func_ptr_return.zig` — z0 dump rc=0, gcc `main.c` errors=0
- **Source 2:** `repro/mi_matrix/func_ptr_return_type/main.zig` — z0 dump rc=0, gcc `main.c` errors=0
- **Verdict:** oracle clean → zig1 bug.

## Layer
`c89_emit` — FP-return typedef referenced but not hoisted/emitted. The typedef for a function-returning-function-pointer type is used in forward declarations, function signatures, and local vars but never `typedef`'d at the top of the output.

## Expected post-fix
Prints `15`.
