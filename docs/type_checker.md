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
