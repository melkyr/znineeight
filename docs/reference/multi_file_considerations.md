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

## C89 Mapping Details
For more information on how modules map to C89 files, see [C89 Code Generation Strategy](c89_emission.md).

## Implementation Details (Milestone 4 Foundation)
- `CompilationUnit` tracks `current_module_`.
- `Parser` propagates `current_module_` to all created `ASTNode`s.
- `GenericInstantiation` stores `module` and `is_explicit` flags.
- `GenericParamInfo` captures rich metadata for generic arguments (Types and Comptime Values).
