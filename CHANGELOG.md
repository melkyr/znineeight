# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.12.0] - "Isophthalic acid"

### Added
- **OpenWatcom Compatibility**: The bootstrap compiler and generated C89 code are now fully compatible with the OpenWatcom 1.9 compiler suite, including optimized build scripts and standardized PAL headers.
- **Tuple Support**: Implemented Tuple types (`struct { T1, T2 }`), literals (`.{ a, b }`), and member access (`t.0`). C89 lowering uses structs with indexed fields (`field0`, `field1`, etc.).
- **Networking Support**: Added a minimal socket API to the Platform Abstraction Layer (PAL), supporting TCP server creation, `select()`, `recv()`, and `send()` on both Windows (Winsock 1.1) and POSIX.
- **MUD Server Example**: Added a minimal telnet Multi-User Dungeon (MUD) server example in `examples/mud_server/` to demonstrate networked application development in Z98.
- **Unified Logging System**: Implemented a global `Logger` architecture intercepted at the platform layer, ensuring robust debugging across 32-bit targets.
- **Documentation**: Added comprehensive test suite documentation in `tdocs/` and a detailed Lexer Design Specification.

### Fixed
- **Lifetime Analysis**: Upgraded `LifetimeAnalyzer` to detect dangling pointers in complex expressions involving field access, array indexing, and slices via recursive provenance tracking.
- **Double-Free Detection**: Major upgrade to `DoubleFreeAnalyzer` (Phases 5-8). Added multi-level aggregate tracking (nested members, arrays, tuples), transfer history diagnostics showing original owner/transfer site, path-aware `errdefer` semantics, and arena leak suppression via the `-Warena-leak` flag.
- **Aggregate Lifting**: Resolved issues where `TYPE_ANYTYPE` placeholders reached the emitter. Implemented two-layer defense for error unions and preserved direct assignments for literals.
- **C89 Global Visibility**: Fixed `CBackend::generateHeaderFile` to correctly emit `extern` declarations for public global variables while skipping type aliases and imports.
- **TypeChecker Robustness**: Improved handling of error unions in control-flow conditions (`if`, `while`) and refined lookahead disambiguation for anonymous literals (named initializers vs. tuples vs. naked tags).
- **Array Initialization**: Ensured valid C89 static initialization for global arrays of aggregates by forcing decomposition of initializers in `C89Emitter`.
- **Lexer Stability**: Resolved an infinite loop bug in the lexer when encountering tuple member access (e.g., `.0`) and stabilized numeric literal parsing.

### Changed
- **Lexer**: Standardized floating-point literal rules (must have a leading digit; `.5` is invalid) and removed `TOKEN_MEMBER_NUMBER` in favor of generic numeric member access.
- **C89 Emitter**: Optimized `emitArrayInitializer` to use positional C89 compound literals to ensure compatibility and valid static initialization.
- **PAL**: Standardized `plat_write_file` to return `long` (bytes written) and simplified `plat_accept` signature for cross-platform ease.
- **Project Status**: Marked as the final feature release for the bootstrap compiler (`zig0`). Future development transitions to the self-hosted phase.

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
