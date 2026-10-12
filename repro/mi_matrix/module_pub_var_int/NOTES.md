# module_pub_var_int — RED  [std-lib Phase 1]

## What it tests
`pub var x: i32 = 42;` at module scope — a pub mutable module-global scalar. Corpus only covered non-pub `var` (fails) and `pub const` (works); `pub var` of a scalar had zero coverage.

## zig1 evidence
- **dump rc:** 0
- **gcc:** 0 errors
- **Classification:** OK per QUICK_REF compile-only classifier (gcc rc==0); see Notes — runtime gap

## Notes
Compiles gcc-clean but emits WRONG code, same class as `comptime_neg_int`. The module-scope var is demoted to an uninitialized local `int x;` inside `main`, the `= 42` initializer is dropped, and the read goes through uninitialized temp `zT_4` (`zT_3 = zT_4;`). Run prints garbage (`-3130288`), not `43`. Related root cause to existing FAIL `module_var_mutable` (global var C decl missing). **Blocks the std-lib design that relies on module-scope mutable globals** — no pub-var semantics today.
