# Technical Debt Report: TypeChecker and Memory

This document outlines identified technical debt, duplicated code, high-complexity areas, and missing guards in `type_checker.cpp` and `memory.hpp`.

## TypeChecker (`src/bootstrap/type_checker.cpp`, `src/include/type_checker.hpp`)

### Duplicated Code

- **RAII Guards**:
  - *Location*: `type_checker.hpp`.
  - *Description*: Multiple RAII guard structs (`FunctionContextGuard`, `LoopContextGuard`, `VisitDepthGuard`, etc.) follow the exact same pattern: save a value in constructor, restore in destructor.
  - *Target*: Consolidate into a generic `ValueGuard<T>` template.

- **Literal Promotion/Coercion logic**:
  - *Location*: `checkBinaryOperation`, `checkComparisonWithLiteralPromotion`, `checkArithmeticWithLiteralPromotion`, `coerceNode`.
  - *Description*: The logic to check if an integer literal fits into a target type is repeated with variations.
  - *Target*: Standardize on a single `canLiteralFitInType(Type* literal, Type* target)` utility.

- **Manual AST Node Synthesis**:
  - *Location*: `coerceNode` (for Array->Slice and Naked Tag transformations).
  - *Description*: Manual `arena.alloc`, `plat_memset`, and field-by-field initialization of `ASTNode` and its variants.
  - *Target*: Use the synthesis helpers like `createIntegerLiteral`, `createBinaryOp`, etc., consistently.

### Nested Conditionals & High Complexity

- **Method**: `visitMemberAccess`
  - *Target Conditions*:
    - Complex disambiguation logic to determine if an access is static (Type access) or instance-based.
    - Chained checks for `NODE_IDENTIFIER` vs `NODE_MEMBER_ACCESS` on the base expression.
    - Deep nesting for handling Slices, Structs, Unions, and Modules.

- **Method**: `coerceNode`
  - *Target Conditions*:
    - Massive logic block handling various coercions (Array->Slice, String->Slice, Enum->Union, Naked Tag->Union).
    - Contains manual AST transformation logic that should be abstracted.
    - High cyclomatic complexity due to many independent "if" blocks for different type categories.

- **Method**: `checkBinaryOperation`
  - *Target Conditions*:
    - Large switch statement over `op`.
    - Complex nested logic for pointer arithmetic vs numeric arithmetic.
    - Error reporting boilerplate is repeated for many cases.

- **Method**: `visit` (Main Dispatcher)
  - *Target Conditions*:
    - A 60+ case switch statement.
    - Embedded "Soft Registry Consistency Check" logic at the beginning and end of the method adds overhead and complexity to the core dispatcher.

### Missing Guards

- **Method**: `visit` (Recursion Depth)
  - *Condition*: While a `VisitDepthGuard` exists, the error reporting path (`Exceeded maximum recursion depth`) might still allow some processing to continue if not handled carefully by all callers.

- **Method**: `coerceNode` (Recursion Depth)
  - *Condition*: Uses a `static int recursion_depth` which is not thread-safe (though the compiler is currently single-threaded) and relies on manual increment/decrement, which is prone to leaks on early returns.

- **Optional Nodes**:
  - *Condition*: Many visitors assume `node->as.variant.field` is non-null after a successful parse, but don't consistently guard against null if the parser failed or produced a partial node.

---

## Memory (`src/include/memory.hpp`)

### Duplicated Code

- **Allocation and Zeroing**:
  - *Location*: Throughout `type_checker.cpp` and `parser.cpp`.
  - *Description*: The pattern `ptr = arena.alloc(sizeof(T)); plat_memset(ptr, 0, sizeof(T));` is ubiquitous.
  - *Target*: Add a `ArenaAllocator::allocZeroed<T>()` template method.

- **Alignment Logic**:
  - *Location*: `alloc_aligned` and `try_alloc_in_chunk`.
  - *Description*: The mask-based alignment calculation `(offset + mask) & ~mask` is repeated.

### Nested Conditionals & High Complexity

- **Method**: `ArenaAllocator::alloc_aligned`
  - *Target Conditions*:
    - Overlapping limit checks: `total_used_for_stats + size > total_cap` AND `total_used_for_stats + size > hard_limit_`.
    - The logic for determining new chunk size is branched based on `total_cap`.

- **Method**: `ArenaAllocator::try_alloc_in_chunk`
  - *Target Conditions*:
    - Contains secondary checks for `total_cap` and `hard_limit_`, leading to redundant logic with `alloc_aligned`.

### Missing Guards

- **Alignment Overflow**:
  - *Condition*: `(chunk->offset + mask)` could theoretically overflow `size_t` if `offset` is near the maximum value, though unlikely given the 16MB `hard_limit_`.

- **DynamicArray Capacity**:
  - *Condition*: `ensure_capacity` does not check if `new_cap * sizeof(T)` overflows `size_t`.

- **Chunk Allocation Failure**:
  - *Condition*: If `plat_alloc` fails in `alloc_aligned`, it returns `NULL`, but some callers in the codebase do not check the return value of `ArenaAllocator::alloc` before using it.

- **Error Reporting**:
  - *Condition*: `ArenaAllocator` calls `plat_abort()` directly for `hard_limit_` violations, which bypasses any potentially cleaner error handling in the `CompilationUnit` or `ErrorHandler`.
