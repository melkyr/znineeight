# module_pub_var_struct — RED  [std-lib Phase 1]

## What it tests
`pub var out: Writer = undefined;` — a module-scope mutable global of struct type. No repro covered a pub global of struct type.

## zig1 evidence
- **dump rc:** 0
- **gcc:** 0 errors
- **Classification:** OK per QUICK_REF compile-only classifier (gcc rc==0); see Notes — runtime gap

## Notes
Compiles gcc-clean but emits WRONG code. The field-store `out.tag = 7;` writes correctly, but the read `__bootstrap_print_int(out.tag)` goes through uninitialized temp `zT_4` (`zT_5 = zT_4.tag;`) instead of `out.tag` — the global's value is never read back. Run prints garbage (`-303052209`), not `7`. Same class as `module_pub_var_int`/`comptime_neg_int`: module-global reads/writes don't reliably reference the actual global. **Blocks the std-lib design that needs mutable struct-valued module globals.**
