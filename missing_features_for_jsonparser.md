# Comprehensive Findings: "Baptism of Fire" JSON Parser

The attempt to compile a non-trivial JSON parser in Z98 revealed significant architectural and implementation gaps in the RetroZig bootstrap compiler. While individual features (like tagged unions or ranges) pass isolated unit tests, they fail to work together in a complex, multi-module application.

## Peak Memory Usage
- **Tiny Program**: ~18 KB
- **JSON Parser (Full Run)**: ~524 KB
- **Limit**: 16 MB (PASS)

## 1. Tagged Union Critical Failures
### C89 Keyword Mismatch
- **Problem**: Tagged unions are correctly identified as `TYPE_UNION` (with `is_tagged=true`) and emitted as C `struct`s. However, the code generator consistently uses the `union` keyword for variable declarations of these types.
- **Result**: `error: ‘z_repro_union_U’ defined as wrong kind of tag`.
- **Workaround**: Downgrade to a manual `struct` + `enum` tag + `union` data field.

### Member Access Resolution
- **Problem**: Accessing union tags (e.g., `JsonValue.Null`) often fails during type checking with `member access '.' only allowed on structs, unions, enums...`.
- **Root Cause**: Inconsistent unwrapping of `TYPE_TYPE` and `TYPE_PLACEHOLDER` in `visitMemberAccess`.
- **Workaround**: Use explicit constant lookups or fully qualified names where necessary.

## 2. Constant Evaluation Limitations
### Character Literals in Ranges
- **Problem**: `switch` ranges using character literals (e.g., `'0'...'9'`) are rejected.
- **Result**: `error: Range bounds must be compile-time constants`.
- **Root Cause**: `TypeChecker::evaluateConstantExpression` lacks a case for `NODE_CHAR_LITERAL`.
- **Workaround**: Use `if-else` chains or manual integer constants in `switch` prongs.

## 3. Slice and Coercion Bugs
### String to Slice Coercion
- **Problem**: Implicitly converting `"literal"` to `[]const u8` fails when passed as a function argument.
- **Result**: `error: incompatible argument type ... expected '[]const u8', got '*const u8'`.
- **Workaround**: Use manual slice construction or `@ptrCast` for C interop functions.

### Missing Slice Definitions
- **Problem**: When a slice is used in a private function, the `typedef struct Slice_...` and its `__make_slice_...` helper are often missing from the generated `.c` file.
- **Workaround**: Ensure the slice type is used in a public signature or as a member of a public struct to force emission.

## 4. Multi-Module / @import Instability
### Cross-Module Symbols
- **Problem**: Frequent `use of undeclared identifier` for symbols imported from other modules.
- **Workaround**: Consolidate logic into fewer files or use `extern` declarations to bridge gaps where `@import` fails.

## 5. Recursive Type Gaps
### Incomplete Self-Reference
- **Problem**: Types like `struct { v: []Self }` fail with `field has incomplete type`.
- **Root Cause**: The layout calculation for slices/arrays triggers recursive resolution that the placeholder system cannot always satisfy.
- **Workaround**: Use single-item pointers (`*Self`) for recursion, as pointers have fixed sizes regardless of target completion.

## Summary
The compiler is currently in a "feature-complete but integration-failed" state for Z98. The Milestone 9 features exist in the codebase but are not robust enough for a production-level application like a JSON parser. Immediate focus should be on fixing the C89 keyword mismatch for tagged unions and handling character literals in constant evaluation.
