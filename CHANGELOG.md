# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
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
