# Bug Deep Dive: Header Type Mismatch for Special Types

## Overview
A "field has incomplete type" error occurs in the generated C89 headers when a "special type" (Optional, Error Union, or Slice) is used across modules and its payload depends on a type defined in an imported module.

## Reproduction
The issue is reproduced using `examples/rogue_mud/test/header_repro.zig` and `examples/rogue_mud/test/header_repro_mod.zig`.

**header_repro_mod.zig**:
```zig
pub const Data = struct {
    value: i32,
};
```

**header_repro.zig**:
```zig
const mod = @import("header_repro_mod.zig");
pub const Container = struct {
    data: ?mod.Data, // Optional payload is from another module
};
```

When compiled with `zig0`, the generated `header_repro.h` contains:

```c
// ... forward declarations ...
struct zS_79208a_Data;

#ifndef ZIG_OPTIONAL_Optional_zS_79208a_Data
#define ZIG_OPTIONAL_Optional_zS_79208a_Data
struct Optional_zS_79208a_Data {
    struct zS_79208a_Data value; // ERROR: zS_79208a_Data is incomplete here
    int has_value;
};
typedef struct Optional_zS_79208a_Data Optional_zS_79208a_Data;
#endif

// ... later ...
#include "header_repro_mod.h" // Definition of zS_79208a_Data is here
```

## Compiler Trace (with DEBUG_HEADER_GEN)
Using the instrumented `zig0`, we can see the order of operations in `CBackend::generateHeaderFile`:

```
--- generateHeaderFile for module: header_repro ---
Pass 0: Forward declarations
  Forward declaring struct/union: Arena
  Forward declaring struct/union: zS_79208a_Data
  Forward declaring struct/union: zS_0141cd_Container
Pass 1: Type definitions
  Emitting definition for: unnamed (owned=0, special=1)
  Emitting definition for: zS_0141cd_Container (owned=1, special=0)
  Including header: header_repro_mod.h
```

Note that `unnamed` (the `Optional_zS_79208a_Data` type) is emitted in **Pass 1**, but `header_repro_mod.h` is only included **after** all definitions in the current module are emitted.

## Root Cause Analysis
The bug is located in `src/bootstrap/cbackend.cpp`, specifically within `CBackend::generateHeaderFile`.

### Why it happens
The `generateHeaderFile` function follows a fixed sequence:
1. Emit Forward Declarations for all reachable types.
2. Emit Definitions for owned types and all Special Types (Slices, Optionals, Error Unions).
3. Emit `#include` for all imported modules.

Special types in Z98 are designed to be "self-contained" within each header that uses them. This is why `CBackend` defines them even if they are not "owned" by the current module. However, for `Optional<T>` and `ErrorUnion<T>`, the generated C `struct` contains the payload `T` **by value**.

C89 requires a type to be complete before it can be used as a member of another struct by value. Since the imported header containing the definition of `T` is included *after* the special type definition, the C compiler encounters an incomplete type error.

### Why it doesn't happen in other situations
1. **Pointers**: If a struct contains a pointer to a type in another module, it only needs a forward declaration, which is correctly emitted at the top of the header.
2. **Same-module Special Types**: If the payload is in the same module, the `MetadataPreparationPass` topological sort ensures the payload is defined before the special type.
3. **Primitive Payloads**: Special types with primitive payloads (e.g., `?i32`) work because primitives are always "complete".

## Proposed Solution
The `#include` statements for imported modules should be moved up in the header generation process.

Specifically, they should be emitted **after** the forward declarations but **before** the definitions of owned and special types.

### Revised `generateHeaderFile` Sequence:
1. Emit Header Guards and core runtime includes.
2. **Pass 0**: Emit Forward Declarations for all reachable types.
3. **NEW STEP**: Emit `#include` for all imported modules.
4. **Pass 1**: Emit Definitions for owned and special types.

### Impact on Circular Dependencies
Zig0 handles circular imports by:
- Using header guards for every definition.
- Emitting forward declarations for all used types at the top of every header.

By keeping the forward declarations at the very top (Step 2) and then including other headers (Step 3), we ensure that even in a circular dependency, the C compiler has at least a forward declaration of every type before it starts processing the included headers. The guards then ensure that each type is defined exactly once in the final compilation unit, in the correct order.
