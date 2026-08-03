# import_extern_c — OK  [std-lib Phase 1]

## What it tests
Cross-module `extern "c" fn`: module B (`main.zig`) imports module A (`io.zig`) which declares an `extern "c"` fn, and B calls it. This is the bootstrap-compatibility question — can an imported module carry `extern "c"` declarations that resolve at link?

## zig1 evidence
- **dump rc:** 0
- **gcc:** 0 errors
- **Classification:** OK per QUICK_REF classifier

## Notes
Multi-module dump emits 2 `.c` files (one per module); both compile gcc-clean and the linked program runs correctly — prints `hello`. The `extern "c"` declaration in `io.zig` resolves at link against `zig_runtime.c`'s `__bootstrap_print`. **Supports the std-lib design:** an imported module can carry `extern "c"` bootstrap-compatible declarations end-to-end (parse → sema → emit → link → run).
