> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Multi-File Considerations for Milestone 6

Multi-file support is implemented in the bootstrap compiler as of Milestone 6.

## Compilation Model

The compiler now supports multiple Zig modules within a single `CompilationUnit`. Each module typically corresponds to one Zig source file.

- **`@import` Support**: The parser recognizes `@import` and the `TypeChecker` uses it to populate the module dependency list.
- **Orchestration**: The `CBackend` class manages the generation of paired `.c` and `.h` files for all modules in the unit.
- **Header Generation**: Public declarations (`pub`) are automatically extracted into the corresponding header file.

## Symbol Resolution and Namespacing

### Module Names
Module names are interned strings. For files, the name is derived from the basename without the `.zig` extension.

### Global Namespacing
To avoid C-level collisions, symbols are mangled using the module name as a prefix: `z_ModuleName_SymbolName`.

### Cross-Module Access
When a module accesses a member of an imported module (e.g., `utils.Point`), the `TypeChecker` resolves the reference via `SymbolTable::lookupWithModule`. The `C89Emitter` then uses the mangled name for emission.

### Resolution Stability
To ensure correct resolution across complex import graphs and two-pass analysis:
- **Topological Sorting**: Modules are sorted by dependency order to ensure each module's dependencies are analyzed before it.
- **Top-Level Protection**: The `isTopLevelDeclaration` check ensures that symbols defined at the file scope are never accidentally marked as local variables during re-visitation.
- **Signature Isolation**: The `is_resolving_signature_` guard ensures that cross-module lookups for function types do not inherit the local scope context of the calling function.

## C89 Mapping Details
For more information on how modules map to C89 files, see [C89 Code Generation Strategy](c89_emission.md).

## Implementation Details (Milestone 4 Foundation)
- `CompilationUnit` tracks `current_module_`.
- `Parser` propagates `current_module_` to all created `ASTNode`s.
- `GenericInstantiation` stores `module` and `is_explicit` flags.
- `GenericParamInfo` captures rich metadata for generic arguments (Types and Comptime Values).
