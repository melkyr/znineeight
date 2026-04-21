# Rogue MUD - Compiler Investigation Results

This document contains the findings of a deep-dive investigation into several bugs and quirks identified during the implementation of the `rogue_mud` project, specifically focusing on cross-module resolution and mangling issues.

## 1. Cross-module Symbol Hash Inconsistency (Issue 14.A)

### The Problem
Generated C code fails to link because the same symbol is assigned different mangled hashes in different modules.
Example: `ui.h` uses `zV_1c8b95_ANSI_GREEN` while `ui.c` defines `zC_43327b_ANSI_GREEN`.

### Why and How it Happens
The root cause is in `NameMangler::mangle` (`src/bootstrap/name_mangler.cpp`). The compiler generates hashes for module names based on their **relative path** from the current working directory (`.`).

**The Chain of Events:**
1.  **Entry Module Compilation:** When `zig0` starts with `main.zig`, the `CompilationUnit` adds the source.
2.  **Import Discovery:** The `TypeChecker` encounters `@import("ui.zig")`.
3.  **Path Normalization Drift:**
    *   If `ui.zig` is compiled as a standalone unit or if it's the "home" module for a type resolution pass, its path might be processed as `"ui"`. `fnv1a_32("ui")` results in hash `43327b`.
    *   If `ui.zig` is imported via `examples/rogue_mud/ui.zig`, the `get_relative_path` logic might produce the full relative string. `fnv1a_32("examples/rogue_mud/ui.zig")` results in hash `1c8b95`.
4.  **Inconsistent Hashing:** The `NameMangler` blindly hashes whatever string it is given as the `module_path`. Since different modules may refer to the same file using different relative paths, they produce different hashes.
5.  **Link Failure:** The linker sees two different symbols for what should be the same global constant.

### Cascade of Events
`CompilationUnit::resolveImportsRecursive` -> Resolves absolute path -> `addSource` -> `setCurrentModule` -> `TypeChecker::check` -> calls `NameMangler::mangle` with the module name or path -> `get_relative_path(module_path, ".")` -> `fnv1a_32`.

---

## 2. Const vs Var Mangling Inconsistency (Issue 14.C)

### The Problem
`pub const` symbols get the `zC_` prefix in the definition module but `zV_` in the header or importing modules.

### Why and How it Happens
The `TypeChecker` determines the mangling kind ('C' for Const, 'V' for Var) dynamically based on the `node->is_const` property of the `ASTVarDeclNode`.

**The Chain of Events:**
1.  **Definition Phase:** In the home module, the `TypeChecker` visits the `pub const` declaration. `node->is_const` is true, so it calls `mangle('C', ...)`.
2.  **Import/Lookup Phase:** When another module imports the first one, it performs a `SymbolTable::lookup`.
3.  **Flag Propagation Failure:** In some resolution paths (like `handleModuleMemberFound`), the `TypeChecker` creates or updates symbols. If the `is_const` flag is not correctly synchronized between the home module's `Symbol` and the importer's view, the importer might default to 'V'.
4.  **Code Generation:** The `CBackend` generates the header prototypes using the mangled name stored in the symbol. If that name was generated with 'V' during a lookup, but 'C' during definition, the names mismatch.

---

## 3. Unresolved Call Warnings (Issue 13)

### The Problem
The compiler issues "Unresolved call" warnings at the end of compilation, even if the code eventually compiles.

### Why and How it Happens
These warnings are emitted by the `CallSiteLookupTable` when it contains entries that were never resolved to a concrete mangled name.

**The Chain of Events:**
1.  **Parsing/Initial Pass:** `TypeChecker` encounters a function call. It registers the call site in the `CallSiteLookupTable`.
2.  **Premature Validation:** `SignatureAnalyzer` or `CallResolutionValidator` runs after the initial `check` pass.
3.  **Missing Mangled Name:** For complex cross-module calls (like `room_mod.Room_centerX(room)`), the mangled name for the target function might not have been generated yet if the target module's `visitFnSignature` hasn't been called or if the lookup failed to trigger a resolution.
4.  **Warning Emission:** The `CompilationUnit` prints all unresolved entries at the end of the pipeline.

---

## 4. Missing Empty Tuple Definition (Issue 14.B)

### The Problem
C compiler errors: "storage size of '...Tuple_empty' isn't known".

### Why and How it Happens
Functions like `std.debug.print` with no arguments desugar to `struct Tuple_empty`.

**The Chain of Events:**
1.  **Monomorphization/Lowering:** `TypeChecker` sees a call with no args. It generates a `TYPE_TUPLE` with zero elements.
2.  **Mangling:** `NameMangler::mangleType` returns `"Tuple_empty"`.
3.  **Emission Drift:** The `CBackend` emits the definition of `struct Tuple_empty` only in the module where it *first* decided it was needed.
4.  **Header Missing:** The definition is not placed in `zig_special_types.h` (the global header), so other modules importing it just see the name but not the body.

---

## High-Level Proposal for Solutions (Z98 zig1)

### 1. Deterministic Stable Hashing (Fix for 14.A)
Instead of hashing relative paths, `zig1` should:
*   Intern all source paths as **Absolute Paths**.
*   The hash for a module should be derived from its **Canonical Name** or a hash of its **Absolute Path** (normalized to be platform-independent).
*   Ensure that the `module_id` or `module_hash` is assigned once per unique file and remains constant regardless of how the file is imported.

### 2. Symbol Kind Synchronization (Fix for 14.C)
*   The `Symbol` structure should carry the mangling kind as a primary attribute.
*   Once a symbol is mangled, its `mangled_name` should be immutable and shared across all modules that reference it.
*   Lookup logic must ensure that the `is_const` property is correctly retrieved from the symbol's original definition, not inferred from the call site.

### 3. Unified Validation Pass (Fix for 13)
*   Delay `CallResolutionValidator` and `SignatureAnalyzer` until **after** all modules have completed their initial `TypeChecker::check` pass.
*   Ensure that `handleModuleMemberFound` aggressively resolves target function signatures so their mangled names are available.

### 4. Global Special Types (Fix for 14.B)
*   The `CBackend` should treat `Tuple_empty` like `Slice_u8` and emit it into the global `zig_special_types.h` or ensure every module's `.h` has a safe forward-declaration/definition guard.

---
**Investigation performed with `zig0_debug` (Milestone 11).**
