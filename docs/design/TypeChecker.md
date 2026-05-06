# TypeChecker Implementation Details

## Overview
The \`TypeChecker\` is responsible for semantic analysis and type validation of the Z98 AST. It employs a multi-pass strategy and a robust scoping mechanism to handle cross-module dependencies and recursive types.

## 1. Signature Resolution Guard
To prevent local symbol misidentification during on-demand signature resolution, the \`TypeChecker\` uses an \`is_resolving_signature_\` flag, typically managed via the \`ResolvingSignatureGuard\` RAII helper.

- **Purpose**: When the \`TypeChecker\` is forced to resolve a function signature (e.g., during a cross-module call or forward reference), this flag ensures that the parameters and return type are NOT incorrectly tagged with the \`SYMBOL_FLAG_LOCAL\` flag.
- **Mechanism**: The \`isLocalContext()\` method checks this flag. If \`is_resolving_signature_\` is true, \`isLocalContext()\` returns false even if the checker is currently visiting a function body.

## 2. L-Value Handling
The \`TypeChecker\` strictly enforces l-value requirements for operations like address-taking (\`&\`) and assignments.

### 2.1 Member Access as L-Value
Member access expressions (\`struct.field\`) are recognized as valid l-values in \`visitUnaryOp\` for the \`TOKEN_AMPERSAND\` operator. This allows taking the address of struct fields (e.g., \`&compiler.alloc\`).

### 2.2 Constness of Member Access
The \`isLValueConst\` method recursively determines if an l-value is mutable. For member access:
- If the base is a module (\`module.symbol\`), the mutability is determined by the symbol's \`SYMBOL_FLAG_CONST\`.
- If the base is a struct/union, it is const if the base expression itself is const (e.g., a field of a \`const\` struct).
- Special fields like \`Optional.value\`, \`Optional.has_value\`, and \`TaggedUnion.tag\` are always treated as read-only.

## 3. Cross-Module Context Switching
See [Bootstrap Type System & Semantic Analysis](Bootstrap_type_system_and_semantics.md) Section 27 for details on module context switching during call site resolution.

## 4. Placeholder Registration for Imports
To support cross-module type aliases and bare imports that may appear anywhere in a file (including at the bottom), `registerPlaceholders` creates a `TYPE_PLACEHOLDER` for every top-level `const` alias that originates from an `@import`. This includes:
- Bare module imports: `const util = @import("util.zig");`
- Member access imports: `const LispError = @import("value.zig").LispError;`
- Aliases-of-aliases: `const ga_mod = @import(...); const U8ArrayList = ga_mod.U8ArrayList;`

These placeholders are registered in the defining module's scope and type registry during Pass 0. They are then resolved in a fixed-point loop during Phase 0.5 (Pass 2) to ensure all transitive dependencies between placeholders are fully satisfied before Pass 2 type checking begins.

## 5. Canonical Module Identity
To ensure robust type deduplication in large multi-module projects, the `TypeRegistry` uses the interned absolute canonical path of a module as its key, rather than a `Module*` pointer. This ensures that:
- Types are correctly identified even if multiple `Module` objects are created for the same file.
- Lookups are case-insensitive and normalized across different platforms.

## 6. Post-Check Phase Flag
The `TypeChecker` includes an `is_post_check_phase_` flag that is enabled for all validation and analysis passes occurring after Phase 2 (Type Checking).

- **Purpose**: Prevents later passes from incorrectly re-resolving identifiers or leaking scope. Once the AST is fully resolved, subsequent visitors must rely solely on the `resolved_type` already stored in the `ASTNode`.
- **Hardenened Identifier Lookup**: When the flag is set, `visitIdentifier` skips the symbol table lookup and directly returns the pre-resolved type.
- **Safety**: This mechanism prevents "undeclared identifier" errors in synthetic AST nodes (like those created during `visitArraySlice`) which may be visited after their lexical scope has been popped.

## 7. Type Alias Labeling for Emitter
To resolve "Transitive Alias Blockades", `visitVarDecl` contains special logic for global constant type aliases (e.g., `const Foo = mod.Foo;`).

- **Mechanism**: After the initializer is resolved, if `isTypeExpression` returns true for the initializer and it's a global constant, the `resolved_type` of the declaration node is overwritten with `TYPE_TYPE`.
- **Purpose**: This explicitly tells the `C89Emitter` that the declaration is a type alias and should not result in any C code emission (global variable). The underlying concrete type remains stored in the `Symbol`'s `symbol_type` for all other compiler passes.
- **Robust Predicate**: `isTypeExpression` was enhanced to recognize `NODE_MEMBER_ACCESS` that resolves to type symbols or aggregate types, ensuring that cross-module aliases like `const T = @import("a.zig").T` are correctly identified.

## 8. On-demand Signature Resolution Context
The `resolveCallSite` function handles forward references to functions and variables by triggering on-demand signature or declaration resolution. To ensure these lookups are correctly isolated to the defining module, `resolveCallSite` switches the `current_module_` context to the target module before calling `visitFnSignature` or `visitVarDecl`. It utilizes the `ResolvingSignatureGuard` to prevent parameters and return types from being incorrectly tagged with the `SYMBOL_FLAG_LOCAL` flag during this on-demand resolution.

## 9. Local Variable Pre-Insertion
To prevent "use of undeclared identifier" errors for variables with inferred types, `visitVarDecl` employs a pre-insertion strategy for local variables.

- **Problem**: Previously, for an inferred variable like `var x = (a + b);`, the compiler would resolve the initializer first. If the initializer resolution hit an error or returned `TYPE_UNDEFINED`, the function would return early without ever inserting `x` into the symbol table. Subsequent references to `x` would then fail with a confusing "undeclared identifier" error instead of the actual type error.
- **Solution**: The `TypeChecker` now inserts the variable into the local symbol table **before** resolving the initializer.
- **Mechanism**:
  1. A new `Symbol` is built with name, `SYMBOL_FLAG_LOCAL`, and `TYPE_UNDEFINED`.
  2. The symbol is inserted into the current scope.
  3. The initializer is resolved.
  4. The symbol's type is updated with the resolved type of the initializer.
- **Safety**: This ensures that even if type inference fails, the identifier itself is known to the compiler, allowing for better error recovery and preventing cascading "undeclared" errors.
