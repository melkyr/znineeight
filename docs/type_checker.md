# Type Checker Implementation Notes

## Slice-to-Pointer Coercion
The compiler implements implicit coercion from slices (`[]T`) and arrays (`[N]T`) to many-item pointers (`[*]T`).

### Implementation Details
- **Type Checking**: `TypeChecker::areTypesCompatible` and `TypeChecker::IsTypeAssignableTo` allow these coercions while enforcing const-correctness.
- **AST Transformation**: In contexts where coercion is allowed (assignment, variable declaration, function call, return statement), the `TypeChecker` injects a synthetic `NODE_MEMBER_ACCESS` node to access the `.ptr` field of the slice or a `NODE_UNARY_OP` (`TOKEN_AMPERSAND`) on a `NODE_ARRAY_ACCESS` for arrays.
- **Const Correctness**: Coercion from `[]const T` to `[*]T` is rejected. Coercion from `[]T` to `[*]const T` is allowed.
- **Chained Coercions**: Array to many-item pointer is handled directly as a separate rule to avoid unnecessary intermediate slices.

### Codebase Locations
- `src/bootstrap/type_checker.cpp`: Implementation of compatibility rules and AST transformations.
- `src/include/type_checker.hpp`: Definition of the `injectPtrAccessIfNeeded` helper function.

## Recursive Type Resolution
The compiler supports mutually recursive and self-referencing types using a placeholder mechanism.

### Placeholder Mechanism
- **Initialization**: When resolving a type declaration (struct, union, or enum), a `TYPE_PLACEHOLDER` is inserted into the symbol table.
- **Lazy Resolution**: During field resolution, if a type is still a placeholder, it is resolved via `resolvePlaceholder`. This ensures that forward-declared types are correctly handled.
- **Completeness Checks**: Fields in aggregate types are resolved before checking for completeness via `isTypeComplete`.

## Tagged Union and Switch Captures
The type checker robustly handles Zig's tagged union captures in switch statements.

### Implementation Details
- **Capture Typing**: In `visitSwitchExpr`, the type of the capture variable (`|payload|`) is derived from the corresponding field of the tagged union.
- **Placeholder Handling**: If a union field type is a placeholder, it is resolved before creating the capture symbol.
- **Defensive Validation**: Ensures that switch prongs with captures are only used with a single tag case item, preventing ambiguity.

## Strict Error Union Rules
The compiler enforces strict rules for error union compatibility to match Zig's safety guarantees.

### Implicit Unwrapping Prohibited
- **Implicit wrapping** (`T` -> `!T`) is allowed for convenience.
- **Implicit unwrapping** (`!T` -> `T`) is **strictly prohibited**. Attempting to assign or compare an error union directly with its payload type results in a type mismatch error.
- **Explicit unwrapping** via `try` or `catch` is required.
