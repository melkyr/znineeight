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
- **Dependents List**: Each placeholder maintains a linked list of `DependentNode` structures. Types that depend on the placeholder (e.g., pointers or arrays) are registered in this list.
- **Resolution and Refresh**: When a placeholder is resolved to a concrete type, the list of dependents is captured and detached before the placeholder `Type` union is mutated. The `refreshLayout` function is then called on each dependent to update its size and alignment based on the newly resolved type.
- **Completeness Checks**: Fields in aggregate types are resolved before checking for completeness via `isTypeComplete`.

## Tagged Union and Switch Captures
The type checker robustly handles Zig's tagged union captures in switch statements.

### Implementation Details
- **Capture Typing**: In `visitSwitchExpr`, the type of the capture variable (`|payload|`) is derived from the corresponding field of the tagged union.
- **Placeholder Handling**: If a union field type is a placeholder, it is resolved before creating the capture symbol.
- **Defensive Validation**: Ensures that switch prongs with captures are only used with a single tag case item, preventing ambiguity.

## Strict Error Union and Optional Rules
The compiler enforces strict rules for error union and optional compatibility to match Zig's safety guarantees.

### Implicit Unwrapping Prohibited
- **Implicit wrapping** (`T` -> `!T`, `T` -> `?T`) is allowed for convenience.
- **Implicit unwrapping** (`!T` -> `T`, `?T` -> `T`) is **strictly prohibited**. Attempting to assign or compare a wrapped type directly with its payload type results in a type mismatch error.
- **Explicit unwrapping** via `try`, `catch`, `orelse`, or capture is required.

### AST-Level Wrapping
To support C89's lack of native error unions and optionals, the `TypeChecker::coerceNode` function performs AST transformations to wrap plain values into their target types.
- **Error Unions**: Transformed into a `NODE_STRUCT_INITIALIZER` representing a success result (`.is_error = 0`, `.data.payload = value`).
- **Optionals**: Transformed into a `NODE_STRUCT_INITIALIZER` representing a present value (`.has_value = 1`, `.value = value`) or a missing value (`.has_value = 0` for `null`).
- **Recursion**: Coercion is applied recursively, supporting nested wrapping (e.g., `T` -> `??T`).
- **Void Handling**: For `void` payloads, the `.data.payload` or `.value` fields are omitted from the generated AST.
