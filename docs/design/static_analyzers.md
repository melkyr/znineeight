# Static Analyzers in Z98 Bootstrap

The Z98 bootstrap compiler performs several static analysis passes after type checking to ensure code correctness, memory safety, and C89 compatibility. These passes operate on the resolved AST and leverage semantic information from the `SymbolTable`.

## 1. SignatureAnalyzer

The `SignatureAnalyzer` ensures that function signatures (parameter and return types) are compatible with the C89 backend.

### C89 Compatibility Rules
The analyzer validates that all types used in function signatures have a direct mapping to C89 or a stable lowered representation:
- **Primitives**: `i8`-`i64`, `u8`-`u64`, `f32`, `f64`, `bool`, `c_char`, `isize`, `usize`.
- **Pointers**: `*T`, `[*]T`, and function pointers.
- **Modern Z98 Types**: Slices (`[]T`), Optionals (`?T`), Error Unions (`!T`), and Error Sets are accepted as they are lowered to structures or integers.
- **Completeness**: Structs, Unions, and Tagged Unions MUST be complete (have a known size and layout) when used in a function signature. Incomplete types are rejected with `ERR_NON_C89_FEATURE`.
- **Parameter Restrictions**: `void` is not allowed as a parameter type. `anytype` is strictly rejected.
- **Return Restrictions**: Large structs (> 64 bytes) trigger `WARN_EXTRACTION_LARGE_PAYLOAD` due to potential MSVC 6.0 issues.

## 2. LifetimeAnalyzer (Dangling Pointers)

Detects potential dangling pointers by tracking the provenance of local variable addresses.

### Checks
- **Returning Local Address**: Rejects `return &local;`.
- **Dangling Assignments**: Tracks when a local pointer variable is assigned the address of a local (e.g., `ptr = &local;`). If that pointer is later returned, it is flagged as a violation.
- **Parameter Safety**: Returning a parameter value is safe, but returning the address of a parameter (`&param`) is rejected.

## 3. NullPointerAnalyzer

Detects potential null pointer dereferences.

### Features
- **Optional Handling**: Understands that `?*T` is nullable.
- **Unwrapping**: Recognizes that `if (opt) |val|` ensures `val` is non-null.
- **Orelse**: Understands that `opt orelse default` provides a non-null fallback.

## 4. DoubleFreeAnalyzer

Detects double `arena_free` calls and memory leaks when using the `ArenaAllocator`.

### Features
- **Allocation Tracking**: Tracks variables initialized with `arena_alloc`.
- **Free Validation**: Ensures `arena_free` is called exactly once on each allocated pointer.
- **Leak Detection**: Warns if an allocated pointer is not freed or is reassigned before being freed.
- **Defer/Errdefer**: Correctly handles cleanup actions queued via `defer` and `errdefer`.

## Pipeline Order
The analyzers run in the following sequence after `TypeChecker`:
1. `SignatureAnalyzer`
2. `NullPointerAnalyzer`
3. `LifetimeAnalyzer`
4. `DoubleFreeAnalyzer`
