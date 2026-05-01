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
