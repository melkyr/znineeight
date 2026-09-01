# module_const_fn_call — RED  [std-lib Phase 1]

## What it tests
`const x: i32 = getInit();` — a module-scope const initialized by a user function call. Corpus only covered builtin-init (`@intCast` in `comptime_neg_int`); a user-fn-call init had zero coverage.

## zig1 evidence
- **dump rc:** 0
- **gcc:** 0 errors
- **Classification:** OK per QUICK_REF compile-only classifier (gcc rc==0); see Notes — runtime gap

## Notes
Compiles gcc-clean but emits WRONG code. `getInit()` is emitted but NEVER called: the emitted `main` reads uninitialized local `int x;` (`zT_0 = x;`). Run prints garbage (`1`), not `42`. Same class as `comptime_neg_int`: comptime/module-scope const initializer expression is dropped at codegen. **Blocks the std-lib design that computes module-scope consts via function calls.**
