# RetroZig Detailed Test Failure Analysis

This document provides a comprehensive breakdown of failing tests in the RetroZig bootstrap compiler test suite, including diagnostic information and hypothesized causes.

## Summary of Failing Batches

| Batch | Fails | Primary Reason |
|-------|-------|----------------|
| **3** | 1/115 | Memory leak detected in `DoubleFreeAnalyzer_CompoundAssignment`. |
| **5** | 18/34 | Widespread failures in Double Free Analysis and path-aware state tracking. |
| **51** | 1/4   | `UnionCapture_ForwardDeclaredStruct`: Pipeline execution failed due to incomplete type error. |

---

## Detailed Diagnostics

### Batch 51: Union Capture with Forward Declared Struct
- **Test**: `UnionCapture_ForwardDeclaredStruct`
- **Location**: `tests/integration/task9_9_union_capture_tests.cpp:8`
- **Symptoms**: `test.zig:3:8: error: type mismatch hint: field 'u' has incomplete type '(placeholder) U'`
- **Diagnosis**: The switch payload capture logic is encountering a placeholder type that hasn't been fully resolved when the capture symbol is created.
- **Analysis**: While basic recursive types are now handled, the interaction between tagged union switch captures and forward-declared structs still triggers "incomplete type" errors if the field type is a placeholder during `validateSwitch`.

### Batch 3: Compound Assignment Leak
- **Test**: `DoubleFreeAnalyzer_CompoundAssignment`
- **Location**: `tests/test_type_checker_compound_assignment.cpp:114`
- **Symptoms**: `FAIL: found_leak`
- **Diagnosis**: The `DoubleFreeAnalyzer` flags an immediate leak when a compound assignment (like `+=`) is performed on an allocated pointer.
- **Analysis**: In `src/bootstrap/double_free_analyzer.cpp`, `visitCompoundAssignment` reports a leak if the lvalue is `AS_ALLOCATED`. While technically true that the original pointer value is lost, the test might need updating or the analyzer should be more nuanced.

### Batch 5: Double Free Analyzer False Negatives
- **Failing Tests**: `DoubleFree_SimpleDoubleFree` (0), `DoubleFree_MemoryLeak` (3), `DoubleFree_DeferDoubleFree` (4), `DoubleFree_ReassignmentLeak` (5), `DoubleFree_NullReassignmentLeak` (6), `DoubleFree_LocationInLeakWarning` (13), `DoubleFree_LocationInReassignmentLeak` (14), `DoubleFree_LocationInDoubleFreeError` (15), `DoubleFree_SwitchPathAware` (22), `DoubleFree_SwitchBothFree` (23), `DoubleFree_LoopConservativeVerification` (27), `DoubleFree_NestedDeferScopes` (28), `DoubleFree_PointerAliasing` (29), `Integration_FullPipeline` (32), `Integration_CorrectUsage` (33).
- **Issue**: The analyzer is currently too conservative with function calls, causing it to "lose track" of pointers.
- **Cause**: In `DoubleFreeAnalyzer::isOwnershipTransferCall`, any function call (except `arena_free`) transitions a pointer to `AS_TRANSFERRED`. The analyzer subsequently ignores double-frees or leaks for transferred pointers.
- **Integration Failure**: `Integration_FullPipeline` expects errors that aren't reported because pointers are marked as transferred upon reaching any call.

---

## Recently Resolved Batches

- **Batch 2 (Parser Expressions)**: All 114 tests passing. Fixed floating-point precision issues in test assertions.
- **Batch 19 (void conversions)**: All 31 tests passing. Resolved by fixing built-in symbol visibility (`arena_alloc_default`) in the `SymbolTable`.
- **Batch 31 (Multi-file)**: All 10 tests passing. Resolved memory corruption in `ErrorHandler` and improved cross-module symbol resolution.
- **Batch 33 (Imports)**: All 3 tests passing. Updated `SymbolTable` to correctly count and resolve the `builtin` module.
- **Batch 48 (Recursive Types)**: All 8 tests passing. Improved two-phase placeholder resolution.
- **Batch 53 (Recursive Composites)**: All 4 tests passing. Fixed "children_type base mismatch" by ensuring registry-aware placeholder creation in `visitArrayType`.
- **Batch 73 (Mutual Recursion)**: All 5 tests passing. Fixed "Pipeline failed unexpectedly" by stabilizing registry lookups during mutual recursion.
