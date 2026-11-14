# Static Analyzers in Z98 Bootstrap

The Z98 bootstrap compiler performs several static analysis passes after type checking to ensure code correctness, memory safety, and C89 compatibility. These passes operate on the resolved AST and leverage semantic information from the `SymbolTable`.

## 1. SignatureAnalyzer

The `SignatureAnalyzer` ensures that function signatures (parameter and return types) are compatible with the C89 backend.

### C89 Compatibility Rules
[updated: 2026-10-17 — D1/D2 surface + drift truth-up] The analyzer validates that all types used in function signatures have a direct mapping to C89 or a stable lowered representation:
- **Primitives**: `i8`-`i64`, `u8`-`u64`, `f32`, `f64`, `bool`, `c_char`, `isize`, `usize`.
- **Arbitrary-width ints**: `i1`-`i63` / `u1`-`u64` (the `parseArbIntWidth` family) are accepted — they lower to a stable C89 carrier. Widths beyond 64 bits are not part of the surface.
- **Pointers**: `*T`, `[*]T`, and function pointers.
- **Modern Z98 Types**: Slices (`[]T`), Optionals (`?T`), Error Unions (`E!T`), and Error Sets are accepted as they are lowered to structures or integers. The rules recurse through these wrappers (and through fn-pointer parameter/return lists), so a fn-ptr return of `?Aggregate`/`E!Aggregate` (the D1-fixed shapes) is accepted when the aggregate is complete, and an incomplete base nested in a wrapper is still rejected (ERR 2011).
- **Member type expressions**: `mod.Key`-style member types (including tagged-union `.tag` member types) are validated through the name cache when they resolve, and accepted otherwise.
- **Completeness**: Structs, Unions, Tagged Unions, and Packed Unions MUST be complete (have a known size and layout) when used in a function signature (directly or nested). Incomplete types are rejected with ERR 2011 (`ERR_2011_INCOMPLETE_TYPE`).
- **Parameter Restrictions**: `void` is not allowed as a direct parameter type (ERR 2010). Nested `void` bases (e.g. `*void` params of fn-ptr types) are fine. `anytype` is strictly rejected (ERR 2012), recursively through wrappers.
- **Return Restrictions**: Large named returns (> 64 bytes) trigger WARN 7010 (`WARN_7010_LARGE_RETURN`) due to potential MSVC 6.0 issues.

## 2. LifetimeAnalyzer (Dangling Pointers)

Detects potential dangling pointers by tracking the provenance of local variable addresses. It supports Milestone 11 features including field access, array indexing, and slices.

### Enhanced Provenance Tracking
The analyzer uses a recursive "origin" resolver to track pointers back to their base local variables. It distinguishes between storage allocated on the stack and memory owned by the caller.

#### Base Symbol Classification
In Z98, `SYMBOL_FLAG_LOCAL` is set for all symbols in a function's activation record. The analyzer classifies these as:
- **True Locals**: Variables declared with `var` or `const` inside the function. Always dangerous to return by address.
- **By-Value Parameters**: Parameters of aggregate types (structs, arrays) passed by value. Their storage is local to the call and dangerous to return by address or internal pointer.
- **Pointer-Like Parameters**: Parameters of type `*T` or `[]T`. While the pointer/slice variable itself is local, the memory it *refers to* is owned by the caller and is safe to return as an interior pointer or slice.

#### Resolution Rules
- **Field Access**: Detects returning addresses of fields (`return &s.x;`). If `s` is a True Local or By-Value Parameter, this is a violation.
- **Dereference**: When a pointer is dereferenced (`ptr.*` or `ptr[i]`), the provenance follows the *data* being pointed to. If `ptr` is a tracked local variable, the provenance follows `ptr`'s assignment history. If `ptr` is an untracked pointer parameter, it is considered "External" (safe).
- **Array Indexing**: Recognizes that `&arr[i]` points to the storage of `arr`.
- **Slices**: Understands that slicing an array (`arr[0..5]`) results in a slice whose lifetime is tied to that array's storage.
- **Composition**: Handles nested structures like `&outer.inner.field`.

#### Post-Check Safety
Static analyzers must rely on pre-resolved AST metadata (specifically `node->symbol` and `node->resolved_type`) instead of querying the `SymbolTable` via `findInAnyScope`. This is enforced by a `Z98_ASSERT` in the symbol table that fires if a lookup is attempted during the post-check phase.

To facilitate this, the `getRootSymbol(ASTNode*)` helper (declared in `ast_utils.hpp`) is used to extract the `Symbol*` from an expression by recursively unwrapping unary operators (`&`, `*`) and member accesses. This ensures that analyzers can identify the underlying variable without performing any scope-based lookups.

### Checks
- **Returning Local Address**: Rejects returning the address of a local variable or parameter (`return &x;`).
- **Returning Pointer to Local Storage**: Rejects returning a pointer or slice that refers to the internal storage of a local variable or by-value parameter.
- **Dangling Assignments**: Tracks when a local pointer or slice variable is assigned a local address. If that variable is later returned, it is flagged.
- **Differentiated Reporting**: Distinguishes between "returning address of" (direct `&local`) and "returning pointer to" (via tracked variable or interior pointer).

### Known Limitations
- **No Field-Level Assignment Tracking**: Tracking assignments to fields (e.g., `s.ptr = &local;`) is currently deferred.
- **No Capture Propagation** [updated: 2026-10-17 — D1/D2 surface + drift truth-up]: RESOLVED — provenance IS tracked through payload captures (`if (opt) |ptr|`, `while`, `for`, `switch`-prong, `catch |e|`) via `bindCaptureState`; the capture inherits the captured expression's provenance (tech-debt §2.1). Base classification (T5): function locals/params/captures are classified without the symbol table (the real pipeline registers module-level names only); pointer-like params seed `Provenance.external` so interiors (`&self.items[i]`) follow the caller-owned pointee while bare `&p` is param_addr.
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
- **Captures**: Recognizes payload captures in `if (opt) |val|` and `while (opt) |val|` (and `for`/`switch`-prong/`catch |e|` captures) [updated: 2026-10-17 — D1/D2 surface + drift truth-up]. The captured variable `val` is guaranteed `PS_SAFE` within the respective block (bound by capture name via `bindCaptureState`).
- **Conditional Refinement**: Refines variable states within `if` and `while` blocks based on null comparisons (e.g., `if (ptr != null)`).
- **Operators**:
  - `orelse`: Correctly merges the state of the optional and the fallback expression.
  - `try`: Propagates the non-null state of the success payload.
  - `catch`: Merges the success payload state with the fallback expression state.
- **Member Access**: Conservatively treats member access (e.g., `s.ptr`) as `PS_MAYBE` to avoid false negatives in the absence of tag-aware analysis.

## 4. DoubleFreeAnalyzer

Detects double `arena_free` calls and memory leaks when using the `ArenaAllocator`.

### Features
- **Allocation Tracking**: Tracks variables and fields initialized with `arena_alloc` or function calls returning `!*T`.
- **Aggregate Tracking**: Supports tracking pointers within structures and slices using composite names (e.g., `container.ptr`, `slice.ptr`). Recursive name generation supports single-level nesting.
- **Array Support**: Distinguishes between distinct constant array indices (e.g., `arr[0]` vs `arr[1]`). Non-constant indices are collapsed to a generic `arr[]`.
- **Free Validation**: Ensures `arena_free` is called exactly once on each allocated pointer, including composite names.
- **Leak Detection**: Warns if an allocated pointer is not freed or is reassigned before being freed. It understands base variable scope depths for composite names to avoid premature leak reporting.
- **Improved Control Flow**:
  - **Loops**: Only marks variables modified within a loop as `AS_UNKNOWN`, preserving the state of untouched pointers.
  - **Error Unions**: Recognizes `try` expressions and `!*T` return types as potential allocation sources.
- **Path-Aware Errdefer**: Correctly distinguishes between success and error exit paths. `errdefer` blocks only execute if the function returns an error type (`error` or `!T`).
- **Ownership Transfer Tracking**: Tracks explicit ownership transfers (e.g., `var b = a;` where `a` is allocated). The source variable is marked as `AS_TRANSFERRED`, and the target variable inherits the allocation state.
- **Arena Leak Suppression**: By default, the analyzer suppresses leak warnings for arena-allocated pointers unless the `-Warena-leak` flag is provided.

### Enhanced Diagnostics
- **Transfer History**: Leak and double-free messages include information about the original owner and the location where ownership was transferred, improving debuggability for complex ownership models.

### Known Limitations
- **Ownership Transfer**: Conservatively assumes unknown function calls do NOT transfer ownership unless they are whitelisted (`arena_create`, `deep_copy`, `transfer_ownership`). Note: `@ptrToInt` is treated as a read, not a transfer.
- **Captures** [updated: 2026-10-17 — D1/D2 surface + drift truth-up]: payload captures (`if (op) |q|`, `while`, `for`, `switch`-prong, `catch |e|`) bind through `bindCaptureState`: the capture inherits the origin's allocation state when known (origin marked `transferred`), so free/double-free through a capture is tracked. Alias chains (`var op = p` where `p` is allocated) keep `op` untracked — see `docs/tech_debt/static_analyzers.md` §4.3.

### Enhancements (Post-Milestone 11)
- **Recursion Depth Guards**: Implemented `MAX_RECURSION_DEPTH = 64` for all recursive analysis functions to prevent stack overflow on deeply nested expressions.
- **Transparent Cast Tracking**: `extractVariableName` now looks through `NODE_PAREN_EXPR`, `NODE_PTR_CAST`, and `NODE_INT_CAST` (including `@ptrToInt` and `@intToPtr`) to maintain state tracking across identity-preserving casts.
- **Precise Array Indexing**: The analyzer now distinguishes between distinct constant array indices (e.g., `arr[0]` vs `arr[1]`). Non-constant indices are collapsed to a generic `arr[]` for conservative tracking.
- **Tuple Support**: Full support for tuple member access (e.g., `tup.0`) using the same composite name tracking logic as struct fields.

## Pipeline Order
The analyzers run in the following sequence after `TypeChecker`:
1. `SignatureAnalyzer`
2. `NullPointerAnalyzer`
3. `LifetimeAnalyzer`
4. `DoubleFreeAnalyzer`
