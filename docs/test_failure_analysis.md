# RetroZig Detailed Test Failure Analysis

This document provides a comprehensive breakdown of failing tests in the RetroZig bootstrap compiler test suite, including diagnostic information and hypothesized causes.

## Summary of Failing Batches

| Batch | Fails | Primary Reason |
|-------|-------|----------------|
| **2** | 1/114 | Floating-point precision/type mismatch in `ASSERT_EQ` (32-bit mode only). |
| **3** | 1/115 | Memory leak detected in `DoubleFreeAnalyzer_CompoundAssignment`. |
| **5** | 18/34 | Widespread failures in Double Free Analysis and path-aware state tracking. |
| **19** | 7/31  | Failures in implicit `*void` conversion tests (Task 182). |
| **31** | 10/10 | Compilation error in `utils.zig` prevents all tests in this batch. |
| **33** | 1/3   | `Import_Simple` failed: unexpected module count. |
| **48** | 2/8   | `RecursiveTypes_RecursiveSlice` and `CrossModule_EnumAccess` failed silently. |
| **53** | 1/4   | `PlaceholderHardening_RecursiveComposites`: children_type base mismatch. |
| **73** | 1/5   | `Phase7_ValidMutualRecursionPointers`: Pipeline failed unexpectedly. |

---

## Detailed Diagnostics

### Batch 2: Floating-Point Assertion Failure (32-bit mode)
- **Test**: `Parser_ParsePrimaryExpr_FloatLiteral`
- **Location**: `tests/test_parser_expressions.cpp:268`
- **Symptoms**: `FAIL: Expected 3 but got 3`
- **Diagnosis**: The `ASSERT_EQ` macro in `src/include/test_framework.hpp` is fundamentally broken for floating-point numbers. It uses `!=` for comparison and then casts both values to `long` for printing.
- **Analysis**: In 32-bit mode, precision differences in how `3.14` is represented or compared trigger the `!=` check. The resulting error message `Expected 3 but got 3` confirms the destructive cast.
- **Recommendation**: Use `compare_floats` from `test_utils.hpp` instead of `ASSERT_EQ`.

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

### Batch 19: Implicit *void Conversions
- **Failing Tests**: `Task182_ArenaAllocReturnsVoidPtr`, `Task182_ImplicitVoidPtrToTypedPtrAssignment`, `Task182_ImplicitVoidPtrToTypedPtrArgument`, `Task182_ImplicitVoidPtrToTypedPtrReturn`, `Task182_ConstCorrectness_AddConst`, `Task182_ConstCorrectness_PreserveConst`, `Task182_MultiLevelPointer_Support`.
- **Symptoms**: `Expected success: 1, Got: 0` followed by type mismatch errors.
- **Diagnosis**: Implicit conversion from `*void` to `*T` or vice-versa is either not implemented or too restrictive in the current `TypeChecker`.

### Batch 31: Multi-file Encoding/Memory Issue
- **Test**: `CBackend_MultiFile`
- **Symptoms**: `utils.zig:1:11: error: [Garbage Characters]`
- **Analysis**: Column 11 is the start of the identifier `Point`. Garbage characters suggest the `ErrorHandler` is printing a stale or uninitialized string pointer. This points to a regression in cross-module symbol resolution where module metadata or string interning is failing to persist across module boundaries.

### Batch 33: Module Count Mismatch
- **Test**: `Import_Simple`
- **Location**: `tests/integration/import_tests.cpp:34`
- **Symptoms**: `FAIL: Expected 3 but got 2`
- **Analysis**: The test expects 3 modules (likely `builtin`, `test_main`, and `test_lib`) but only finds 2. This might indicate that `builtin` is not being counted or one of the user modules is being merged/skipped.

### Batch 48: Recursive Types & Cross-Module
- **Failing Tests**: `test_RecursiveTypes_RecursiveSlice` (2), `test_CrossModule_EnumAccess` (4).
- **Symptoms**: Failures without explicit error messages.
- **Analysis**: These complex type scenarios involving cross-module lookups or recursive slice definitions are likely hitting unhandled edge cases in the registry or the two-phase placeholder resolution.

### Batch 53: Recursive Composite Base Mismatch
- **Test**: `PlaceholderHardening_RecursiveComposites`
- **Symptoms**: `children_type base mismatch`
- **Analysis**: Triggered when a type (like a struct) contains a slice of itself. The base mismatch indicates that during resolution, the underlying pointer of the slice was not correctly reconciled with the finalized version of the struct.

### Batch 73: Phase 7 Mutual Recursion
- **Test**: `Phase7_ValidMutualRecursionPointers`
- **Symptoms**: `Pipeline failed unexpectedly`
- **Analysis**: This failure usually indicates a `plat_abort()` or crash during multi-file mutual recursion validation. It suggests the registry is not yet fully robust against circular dependencies between named types in different modules.
