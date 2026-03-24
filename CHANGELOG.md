# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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
- Fixed pointer dereference precedence in C89 codegen by explicitly parenthesizing dereference bases in member access.
- Fixed tag assignment for void payload variants in tagged unions to set only the `.tag` field.
- Fixed switch payload capture for aggregate types (structs/unions) by using `memcpy` to bypass C89's direct assignment limitations for anonymous structures.
- Added `<string.h>` inclusion to `zig_runtime.h` for `memcpy` support.
