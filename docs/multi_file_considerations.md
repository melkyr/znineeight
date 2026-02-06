# Multi-File Considerations for Milestone 6

## Current Limitation (Milestone 4-5)
- Single-file compilation only.
- `@import` statements are recognized by the parser but strictly rejected by `C89FeatureValidator`.
- The compiler tracks a "current module" based on the filename of the source being compiled.

## Design for Milestone 6 Import System

### 1. Module Names
- Use logical names, not filenames: `@import("std")` → module "std".
- Map logical names to file paths via include search paths (to be implemented with `-I` flag).
- In the current implementation, the module name is derived from the base filename without extension (e.g., `main.zig` -> `main`).

### 2. Symbol Resolution
- Each module has its own symbol table or a way to distinguish symbols by module.
- Public symbols (marked `pub`) are exported and visible to importing modules.
- Lookup priority: current scope → imported modules (in import order).
- `SymbolTable::lookupWithModule(module, name)` is provided as a placeholder for module-aware lookups.

### 3. Catalogue Merging
- `GenericCatalogue`, `ErrorSetCatalogue`, etc., must support merging across modules.
- `GenericCatalogue::mergeFrom` is implemented to combine instantiations and definitions from different compilation units.
- Names in merged catalogues may be prefixed with the module name to avoid collisions (e.g., `std.ArrayList` vs `my_lib.ArrayList`).

### 4. AST Storage
- Every `ASTNode` now contains a `module` field (pointer to interned module name).
- This ensures that subsequent analysis passes (Type Checker, Validator) can identify the provenance of any syntax construct, which is essential for correct error reporting and cross-module template instantiation.

### 5. Circular Import Detection
- Milestone 6 will implement a simple mechanism to reject circular imports in the bootstrap compiler.
- The `CompilationUnit` or a dedicated `ModuleGraph` will track visited files during import resolution.

## Implementation Details (Milestone 4 Foundation)
- `CompilationUnit` tracks `current_module_`.
- `Parser` propagates `current_module_` to all created `ASTNode`s.
- `GenericInstantiation` stores `module` and `is_explicit` flags.
- `GenericParamInfo` captures rich metadata for generic arguments (Types and Comptime Values).
