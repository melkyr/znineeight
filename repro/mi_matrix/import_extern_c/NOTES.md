# import_extern_c — OK  [std-lib Phase 1]

## What it tests
Cross-module import: module B (`main.zig`) imports module A (`io.zig`), and B calls
A's `printHello()`. A imports the local `std.zig` and prints via `std.io.print`.
Exercises the cross-module module-resolution + emission path.

## Migration note (F4 fix, 2026-08-13)
Pre-F4 this repro tested `extern "c" fn __bootstrap_print(s: *const u8)` declarations
resolving at link against `zig_runtime.c`'s `__bootstrap_print`. F4 REMOVED the
`__bootstrap_*` wrappers (F4-stdlib-review finding 1) → the extern no longer resolved
at link (`undefined reference to __bootstrap_print`). Migrated to `std.io.print`
per the F4 bounded fix; the cross-module test shape is unchanged.

## zig1 evidence
- **dump rc:** 0
- **gcc:** 0 errors
- **run:** prints `hello`
- **Classification:** OK per QUICK_REF classifier
