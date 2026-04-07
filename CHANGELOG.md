# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.11.0] - "para-Cresol"

### Added
- **Switch Ranges**: Support for inclusive (`...`) and exclusive (`..`) ranges in switch prongs for integers, enums, and character literals.
- **Braceless Control Flow**: Full support for braceless `if`, `while`, `for`, and `defer` statements.
- **Payload Captures**: Support for `while (optional) |capture|` and `switch (union) |capture|`.
- **Print Lowering**: `std.debug.print` is now lowered by the compiler into multiple runtime calls, allowing for safe and efficient printing on legacy systems.
- **Built-ins**: Added `@intToPtr` and optimized `@sizeOf`/`@alignOf` for all types.
- **Documentation**: Comprehensive Z98 Language Specification and updated Lisp interpreter documentation.
- **Mandelbrot Example**: Added a Mandelbrot set renderer example to demonstrate floating-point and fixed-point arithmetic capabilities.
- **C89 Compatibility Macros**: Introduced `ZIG_UNUSED` and `ZIG_INLINE` in `zig_compat.h` to ensure portability across OpenWatcom and MSVC 6.0.

### Fixed
- **Recursion**: Fully resolved recursion in Z98 applications (like the Lisp interpreter) via a "mutable slot" strategy in `eval.zig`.
- **Tagged Unions**: Fixed a critical bug where nested anonymous struct payloads in `union(enum)` initializers caused `TYPE_UNDEFINED` propagation. Introduced `TYPE_ANONYMOUS_INIT` for robust resolution.
- **C89 Compliance**: `C89Emitter` now ensures all compiler-generated temporaries (`opt_tmp`, `for_idx`) are declared at the top of their respective blocks, maintaining strict C89 definition-before-statement rules.
- **String Literals**: Resolved `-Wpointer-sign` warnings by specializing `__make_slice_u8` to accept `const char*` with internal casts.
- **Local Const Aggregates**: Fixed an issue where local `const` aggregate declarations were treated as type aliases; they now generate correct C89 initializers.
- **Switch Captures**: Fixed state corruption in loops using switch captures; captures are now correctly scoped and initialized within the loop block.
- **Visibility**: Improved cross-module symbol visibility and resolution for tagged union tags and type aliases.
- **Runtime IO**: Standardized `__bootstrap_print`, `__bootstrap_write`, and `__bootstrap_panic` to use `const char*` signatures for better platform compatibility.

### Changed
- **Toolchain**: Reverted primary build recommendation to MinGW due to ongoing incompatibilities with OpenWatcom and MSVC 6.0 for the bootstrap compiler itself.
- **Codegen**: Refactored `C89Emitter` to use centralized keyword constants and standardized statement terminators.

## [0.10.0] - "Xylene"

### Optimized
- Reduced memory usage by resetting token arena after parsing all modules and dependencies.
- Implemented a transient arena reset between file emissions in the C backend, reclaiming per-file overhead (~2.8MB saved).
- Tuned `ArenaAllocator` default chunk size to 256KB to reduce internal fragmentation.

### Fixed
- Fixed switch statement prong bodies containing expressions (e.g., function calls) by making `C89Emitter::emitStatement` handle expression nodes correctly.
- Ensured `zig_special_types.h` is included in all generated `.c` and `.h` files, resolving "unknown type name 'Slice_u8'" errors.
- Fixed placeholder finalization to preserve the original type name and generate proper C identifiers, resolving issues with recursive types and cross-module imports.
- Allowed comparison of optional types with `null` literal (`==`, `!=`).
- Improved `@ptrCast` error messages when source is an optional, suggesting `.value`.
- Fixed a potential segfault in `TypeChecker::visitFnBody` when analyzing functions returning complex union literals. Added robust null checks and forced signature resolution.
- Added `loc` field to `ASTFnDeclNode` to support precise error reporting in function bodies.

### Added
- Added common narrowing conversion helpers (`__bootstrap_u8_from_i32`, etc.) to `zig_runtime.h` to resolve implicit declaration warnings during narrowing casts.
- Supported read-only member access for optional types via `.value` and `.has_value`.
- Regression test for function return segfault in Batch 62.
- Implemented "Union Naked Tags" (Milestone 9 Phase 1 extension). Support for writing `Null` instead of `Null: void` in tagged unions.
- Improved Windows 98 compatibility: defensive console output (`WriteConsoleA`), large memory allocations (`VirtualAlloc`), and optimized build scripts.
