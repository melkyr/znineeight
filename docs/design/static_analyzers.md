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

Detects potential dangling pointers by tracking the provenance of local variable addresses. It supports Milestone 11 features including field access, array indexing, and slices.

### Enhanced Provenance Tracking
The analyzer uses a recursive "origin" resolver to track pointers back to their base local variables:
- **Field Access**: Detects returning addresses of fields (`return &s.x;`) or pointers derived from local fields.
- **Array Indexing**: Recognizes that `&arr[i]` points to the local array `arr`.
- **Slices**: Understands that slicing a local array (`arr[0..5]`) results in a slice whose lifetime is tied to that array.
- **Composition**: Handles nested structures like `&outer.inner.field`.

### Checks
- **Returning Local Address**: Rejects returning the address of a local variable or any of its sub-fields/elements.
- **Dangling Assignments**: Tracks when a local pointer or slice variable is assigned a local address. If that variable is later returned, it is flagged.
- **Differentiated Reporting**: Distinguishes between "returning address of" (direct `&local`) and "returning pointer to" (via tracked variable).

### Known Limitations
- **No Field-Level Assignment Tracking**: Tracking assignments to fields (e.g., `s.ptr = &local;`) is currently deferred.
- **No Capture Propagation**: Provancance is not yet tracked through optional/error union captures (`if (opt) |ptr|`).
- **Minimal Aliasing**: Does not track provenance through pointer dereferences (`*ptr = &local;`).

## 3. NullPointerAnalyzer

The `NullPointerAnalyzer` identifies definite and potential null pointer dereferences by tracking the state of pointer variables across branches and loops.

### State Tracking
Variables are tracked using one of four states:
- `PS_UNINIT`: Variable has no initializer.
- `PS_IS_NULL`: Variable is definitely null (assigned `null` or `0`).
- `PS_SAFE`: Variable is definitely non-null (e.g., after `&x` or a null check).
- `PS_MAYBE`: State is unknown or potentially null (e.g., from a function call result).

### Features and Supported Constructs
- **Optional Types**: Understands that `?*T` and `?[*]T` are nullable. Unwrapped values from these types are tracked.
- **Error Unions**: Supports success-path payload tracking. If a function returns `!*T`, the success payload is treated as non-null.
- **Captures**: Recognizes payload captures in `if (opt) |val|` and `while (opt) |val|`. The captured variable `val` is guaranteed `PS_SAFE` within the respective block.
- **Conditional Refinement**: Refines variable states within `if` and `while` blocks based on null comparisons (e.g., `if (ptr != null)`).
- **Operators**:
  - `orelse`: Correctly merges the state of the optional and the fallback expression.
  - `try`: Propagates the non-null state of the success payload.
  - `catch`: Merges the success payload state with the fallback expression state.
- **Member Access**: Conservatively treats member access (e.g., `s.ptr`) as `PS_MAYBE` to avoid false negatives in the absence of tag-aware analysis.

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
