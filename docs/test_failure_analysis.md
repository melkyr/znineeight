> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Z98 Detailed Test Failure Analysis

This document provides a comprehensive breakdown of failing tests in the Z98 bootstrap compiler test suite, including diagnostic information and hypothesized causes.

## Summary of Failing Batches

| Batch | Fails | Primary Reason |
|-------|-------|----------------|
| 5 | 1 | `test_DoubleFree_TransferTracking` has incorrect semantic expectations. |
| 44 | 1 | Print lowering mismatch due to tuple evolution (regression). |

---

## Detailed Diagnostics

### Batch 5 (Double Free Analyzer)
- **Failure**: `test_DoubleFree_TransferTracking`
- **Root Cause**: The test expects `@ptrToInt(p)` to count as an ownership transfer. In Zig, this is a value-read only. The analyzer correctly identifies a leak because `p` is never freed, but the test's `ASSERT_FALSE(has_leak)` fails.
- **Status**: Analysis complete. Correction planned in follow-up task. See `docs/batch5_failure_analysis.md` for details.

### Batch 44 (Print Lowering)
- **Failure**: Mismatch in lowered C code for `std.debug.print`.
- **Root Cause**: Evolution of tuple support and anonymous literals caused a regression in the synthetic AST generated for print lowering.

---

## Recently Resolved Batches

- **Batch 51 (Union Capture)**: All 4 tests passing. Resolved via runner optimization.
- **Batch 3 (Compound Assignment Leak)**: All 115 tests passing. Resolved via runner optimization.
- **Batch 2 (Parser Expressions)**: All 114 tests passing. Fixed floating-point precision issues in test assertions.
- **Batch 19 (void conversions)**: All 31 tests passing. Resolved by fixing built-in symbol visibility (`arena_alloc_default`) in the `SymbolTable`.
- **Batch 31 (Multi-file)**: All 10 tests passing. Resolved memory corruption in `ErrorHandler` and improved cross-module symbol resolution.
- **Batch 33 (Imports)**: All 3 tests passing. Updated `SymbolTable` to correctly count and resolve the `builtin` module.
- **Batch 48 (Recursive Types)**: All 8 tests passing. Improved two-phase placeholder resolution.
- **Batch 53 (Recursive Composites)**: All 4 tests passing. Fixed "children_type base mismatch" by ensuring registry-aware placeholder creation in `visitArrayType`.
- **Batch 73 (Mutual Recursion)**: All 5 tests passing. Fixed "Pipeline failed unexpectedly" by stabilizing registry lookups during mutual recursion.
