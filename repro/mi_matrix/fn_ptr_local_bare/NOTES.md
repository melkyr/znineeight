# fn_ptr_local_bare — OK  [std-lib Phase 1]

## What it tests
`const f: fn(i32, i32) i32 = add;` — a local function-pointer variable WITHOUT an explicit error set. Corpus only covered fn-ptr with an error set (`inferred_errorset_fnptr/main_green.zig`).

## zig1 evidence
- **dump rc:** 0
- **gcc:** 0 errors
- **Classification:** OK per QUICK_REF classifier

## Notes
Compiles gcc-clean and runs correctly — prints `3` (`f(1, 2)` = `add` = 1+2). Sema emits a non-fatal `warning[3000]` ("initialization type may not be compatible with declared type — source: function, target: pointer") but codegen is correct. **Supports the std-lib design:** bare (error-set-free) fn-ptr locals work. Only the struct-field fn-ptr case is broken (see `fn_ptr_struct_field`).
