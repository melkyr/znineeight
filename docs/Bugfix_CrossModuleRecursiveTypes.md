# Bugfix Report: Cross-Module Recursive Type Resolution

## Issue Description

The compiler would fail with a `DynamicArray` assertion error (`index < len`) during the semantic analysis of multi-module Zig programs containing recursive types (e.g., the Lisp interpreter's `Value` struct).

### Failure Pattern
```
retrozig: src/include/memory.hpp:570: T& DynamicArray<T>::operator[](size_t) [with T = Type*; size_t = long unsigned int]: Assertion 'index < len' failed.
```

### Discovery
Using instrumentation in `DynamicArray::operator[]` to capture stack traces, the failure was pinpointed to loops iterating over `DynamicArray<Type*>` (specifically function parameters and struct fields) during recursive type resolution.

When a `TYPE_PLACEHOLDER` is resolved, it triggers a cascade of `refreshLayout` calls. If this resolution occurs while another part of the compiler is already iterating over a related type's field or parameter array, the recursive calls can mutate or reallocate that same array, invalidating the iterator/index of the outer loop.

## Solution

The fix consists of two complementary strategies:

### 1. Robust Dependent Resolution (Work-Queue)
In `TypeChecker::resolvePlaceholder`, the logic was updated to use a **Work-Queue algorithm**.
- The list of dependents (linked list) is captured and detached from the placeholder *before* mutation.
- The captured list is processed.
- A loop then repeatedly checks if any *new* dependents were added to the placeholder during the resolution of the initial batch, and processes them as well.
- This ensures that every dependent, even those registered during the resolution cascade, gets refreshed exactly once.

### 2. Iterator Stability (Snapshotting Pattern)
A **Snapshotting Pattern** was applied to all critical iteration points involving `DynamicArray` of types or fields:
- **Implementation**: Before entering a loop that might trigger recursive type resolution, a temporary array (snapshot) of the elements is allocated from the `ArenaAllocator`. The loop then iterates over this stable snapshot.
- **Affected Areas**:
    - `TypeChecker::resolveAllPlaceholders`: Snapshots for `TYPE_FUNCTION`, `TYPE_STRUCT`, `TYPE_UNION`, and `TYPE_TUPLE`.
    - `TypeChecker::visitFnBody`: Snapshot for function parameters during re-registration.
    - `MetadataPreparationPass`: Snapshots for module symbol buckets, reachable types, and static functions.
    - `CBackend::scanType`: Snapshots for recursive type discovery.
    - `type_system.cpp`: Snapshots in `signaturesMatch` and `typeToStringInternal`.

## Results
- The `repro_bug.zig` case now completes semantic analysis successfully.
- All 77 integration test batches pass.
- Peak memory usage remains well within the 16MB limit.
