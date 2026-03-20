# RetroZig Detailed Test Failure Analysis

This document provides a comprehensive breakdown of failing tests in the RetroZig bootstrap compiler test suite, including diagnostic information and hypothesized causes.

## Summary of Failing Batches (Current State)

| Batch | Fails | Primary Reason |
|-------|-------|----------------|
| **All** | 0/N | **All 77 batches passing in 64-bit mode.** |

---

## Resolved Regressions & Historically Significant Issues

### Batch 51: Union Capture with Forward Declared Struct
- **Issue**: `UnionCapture_ForwardDeclaredStruct` previously failed with incomplete type errors during switch payload capture.
- **Resolution**: Ensured that the switch payload capture logic robustly resolves placeholder types via the `TypeRegistry` during capture symbol creation. Verified passing in Batch 51.

### Batch 3: Compound Assignment Leak
- **Issue**: `DoubleFreeAnalyzer_CompoundAssignment` previously flagged a leak when a compound assignment was performed on an allocated pointer.
- **Resolution**: The `DoubleFreeAnalyzer` now correctly handles ownership during compound assignments. Verified passing in Batch 3.

### Batch 5: Double Free Analyzer False Negatives
- **Issue**: Widespread failures in `DoubleFreeAnalyzer` where it "lost track" of pointers after function calls.
- **Resolution**: Ownership transfer tracking in `DoubleFreeAnalyzer::isOwnershipTransferCall` has been stabilized, ensuring pointers are correctly tracked across common control flow paths and function boundaries. Verified passing in Batch 5.

### Test Infrastructure (Linking & Compilation)
- **Symptoms**: Several batches (8, 9, 72, 73, 74, _bugs) were failing to generate test runners or link correctly due to "undefined reference" errors.
- **Root Cause**: The original `test.sh` relied on a grep-based dependency discovery that missed files containing `TEST_FUNC` definitions in certain subdirectory structures.
- **Fix**: Rewrote `test.sh` to use an optimized indexing strategy that pre-scans all source files, ensuring all required implementation files are correctly included in the generated batch runners. Restored `exit 1` on compilation failure for reliable error reporting.
- **Verification**: All 77 batch runners now compile, link, and pass successfully.

---

## Registry & Module Resolution
- **Status**: The refactor to support the new module resolution using `TypeRegistry` is fully integrated and stable.
- **Stability**: Cross-module type lookups and recursive definitions are handled correctly by the centralized registry. No regressions observed in multi-file or cross-module test cases (e.g., Batch 19, 31, 33, 73).
