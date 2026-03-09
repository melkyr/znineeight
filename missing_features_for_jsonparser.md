# Missing Features for JSON Parser

This document details the findings from the "baptism of fire" where the Z98 compiler was tested against a multi-module JSON parser implementation.

## Feature Status Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| Multi-module Imports | ✅ Works | `@import` correctly loads and parses dependencies. |
| Built-in Functions | ✅ Improved | `@ptrCast`, `@intCast`, `@sizeOf` work. Added support for Enums/ErrorSets in `@enumToInt`. |
| Error Unions (`!T`) | ✅ Improved | Supported in signatures. `try` expressions now handle `void` and error wrapping better. |
| Optionals (`?T`) | ✅ Works | Supported with `null` and `orelse`. |
| Slices (`[]T`) | ✅ Works | Supported, now with better header generation to avoid "unknown type" errors. |
| Tagged Unions | ⚠️ Manual Only | Use struct + enum tag. Bare `union(enum)` is still unstable. |
| Control Flow Lifting | ✅ Improved | Lifted expressions now correctly skip `void` declarations in C. |
| Forward Decls | ❌ Missing | Static functions in C are called before definition, causing errors. |

## Detailed Discoveries and Workarounds

### 1. Codegen: Void Declarations
**Issue**: The AST lifter was generating `void __tmp_...;` for lifted expressions that yielded `void`. This is invalid C.
**Fix**: Updated `ControlFlowLifter` to skip variable declarations for `void` types and updated `C89Emitter` to emit `0` (as a dummy statement) for identifiers with `void` type.

### 2. Header Generation: Incomplete Types
**Issue**: Slices and Error Unions were being used in typedefs before their constituent aggregate types were defined in C headers.
**Fix**: Implemented post-order dependency traversal in `MetadataPreparationPass` to ensure headers define types in the correct order.

### 3. C89: Implicit Declarations
**Issue**: The current emitter does not generate forward declarations for all local (static) functions, leading to "previous implicit declaration" errors when functions are used before their definition (common in recursive parsers).
**Workaround**: Manually ordering functions in Zig or adding a forward-declaration pass to the emitter.

### 4. Extraction Analysis: Multi-module Segfault
**Issue**: Compiling multiple modules caused a crash in the extraction report because it was trying to print reports for all modules simultaneously.
**Fix**: Guarded report generation to only run once per file ID.

### 5. Symbol Table: Type Resolution
**Issue**: `@enumToInt` only supported `enum` types.
**Fix**: Extended `TypeChecker` to allow `@enumToInt` to operate on `ErrorSet` and added support for Enum types in numeric operation checks.

## Technical Constraints Lessons
*   **Memory**: Arena allocation remains the backbone. The 16MB limit is tight but manageable.
*   **MSVC 6.0**: Strict C89 compliance is essential. Avoid all C99+ features (no `//` comments in C, no mid-block declarations).
*   **Pathing**: Cross-platform path normalization is tricky; resolved a segfault related to relative path handling in filenames without directory components.
