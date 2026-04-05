# Changelog

All notable changes to this project will be documented in this file.

## [0.10.0] - "Xylene" (Milestone 11 Final)

### Optimized
- Reduced memory usage by resetting token arena after parsing all modules and dependencies.
- Implemented a transient arena reset between file emissions in the C backend, reclaiming per-file overhead (~2.8MB saved).
- Tuned `ArenaAllocator` default chunk size to 256KB to reduce internal fragmentation.
- Implemented "TypeChecker::resolveTypeConstant" fast-path to optimize resolution of established type constants.

### Fixed
- **Recursion**: Fully resolved recursion in Z98 applications (like the Lisp interpreter) via a "mutable slot" strategy in `eval.zig`.
- **Tagged Unions**: Fixed a critical bug where nested anonymous struct payloads in `union(enum)` initializers caused `TYPE_UNDEFINED` propagation. Introduced `TYPE_ANONYMOUS_INIT` for robust resolution.
- **C89 Compliance**: `C89Emitter` now ensures all compiler-generated temporaries (`opt_tmp`, `for_idx`) are declared at the top of their respective blocks, maintaining strict C89 definition-before-statement rules.
- **String Literals**: Resolved `-Wpointer-sign` warnings by specializing `__make_slice_u8` to accept `const char*` with internal casts.
- **Local Const Aggregates**: Fixed an issue where local `const` aggregate declarations were treated as type aliases; they now generate correct C89 initializers.
- **Switch Captures**: Fixed state corruption in loops using switch captures; captures are now correctly scoped and initialized within the loop block.
- **Visibility**: Improved cross-module symbol visibility and resolution for tagged union tags and type aliases.

### Added
- **Switch Ranges**: Support for inclusive (`...`) and exclusive (`..`) ranges in switch prongs for integers, enums, and character literals.
- **Braceless Control Flow**: Full support for braceless `if`, `while`, `for`, and `defer` statements.
- **Payload Captures**: Support for `while (optional) |capture|` and `switch (union) |capture|`.
- **Print Lowering**: `std.debug.print` is now lowered by the compiler into multiple runtime calls, allowing for safe and efficient printing on legacy systems.
- **Built-ins**: Added `@intToPtr` and optimized `@sizeOf`/`@alignOf` for all types.
- **Windows 98 Compatibility**: Defensive console output (`WriteConsoleA`), large memory allocations (`VirtualAlloc`), and optimized build scripts.
- **Documentation**: Comprehensive Z98 Language Specification and updated Lisp interpreter documentation.
