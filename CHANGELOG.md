# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- Fixed a potential segfault in `TypeChecker::visitFnBody` when analyzing functions returning complex union literals. Added robust null checks and forced signature resolution.
- Added `loc` field to `ASTFnDeclNode` to support precise error reporting in function bodies.

### Added
- Regression test for function return segfault in Batch 62.
