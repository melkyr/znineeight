# Technical Debt Report: Parser and Lexer

This document outlines identified technical debt, duplicated code, high-complexity areas, and missing guards in `lexer.cpp` and `parser.cpp`.

## Lexer (`src/bootstrap/lexer.cpp`, `src/include/lexer.hpp`)

### Duplicated Code

- **Token Initialization**:
  - *Location*: `lexCharLiteral`, `parseHexFloat`, `lexNumericLiteral`, `nextToken`, `lexStringLiteral`, `lexIdentifierOrKeyword`.
  - *Description*: Every token creation manually copies `file_id`, `line`, and `column` from the lexer state to the `Token` structure.
  - *Target*: Consolidate into a `createToken(Zig0TokenType type)` helper.

- **Numeric Parsing Loops**:
  - *Location*: `parseDecimalFloat`, `parseInteger`, `parseHexFloat`, `parseEscapeSequence`.
  - *Description*: The logic for consuming digits while skipping underscores (`_`) is repeated multiple times with slight variations for different bases.
  - *Target*: Create a `consumeDigits(int base)` or `parseNumberPart(int base)` utility.

- **Escape Sequence Handling**:
  - *Location*: `lexCharLiteral`, `lexStringLiteral`.
  - *Description*: Both functions call `parseEscapeSequence` but handle the results and error states with similar boilerplate.

### Nested Conditionals & High Complexity

- **Method**: `nextToken`
  - *Target Conditions*:
    - The `@` builtin identifier handling uses a long chain of `plat_strncmp` calls.
    - Nested block comment parsing logic (nesting level tracking) is implemented directly inside the main switch.
    - DISAMBIGUATION logic for `.` (checking for `..`, `...`, `.*`, `.?) is deeply branched.

- **Method**: `parseEscapeSequence`
  - *Target Conditions*:
    - The `\u{...}` and `\xHH` parsing logic contains nested loops and multiple exit points for validation (hex digit checks, bounds checks).

- **Method**: `lexNumericLiteral`
  - *Target Conditions*:
    - Disambiguation between float literals and integer range operators (`..`) involves complex lookahead logic that is hard to follow.

### Missing Guards

- **Constructor**: `Lexer::Lexer`
  - *Condition*: `src.getFile(file_id)` is called and its `content` is accessed without verifying if `src.getFile` returned a valid pointer.

- **Method**: `parseEscapeSequence`
  - *Condition*: Increments `this->current` after seeing `u` or `x` without verifying that it hasn't reached `\0` (EOF).

- **Method**: `lexStringLiteral`
  - *Condition*: The `DynamicArray` buffer grows indefinitely for extremely long string literals without a "sanity limit" check, which could lead to excessive memory consumption before hitting arena limits.

- **Method**: `match` / `advance`
  - *Condition*: Inconsistent handling of newline updates between `match` (which doesn't seem to handle `\n` line increments) and `advance` (which does).

---

## Parser (`src/bootstrap/parser.cpp`, `src/include/parser.hpp`)

### Duplicated Code

- **AST Node Creation**:
  - *Location*: `createNode`, `createNodeAt`.
  - *Description*: `createNode` is essentially a wrapper that calls `peek().location` and then repeats the exact allocation and `plat_memset` logic found in `createNodeAt`.
  - *Target*: Refactor `createNode` to simply call `createNodeAt(type, peek().location)`.

- **DynamicArray Allocation**:
  - *Location*: `parsePostfixExpression` (for `call_node->args`), `parseSwitch` (for `expr_prongs`/`stmt_prongs`), `parseStructInitializer` (for `init_data->fields`), `parseFnDecl` (for `fn_decl->params`), etc.
  - *Description*: The pattern of `arena_->alloc(sizeof(DynamicArray<T>))` followed by a placement `new` and `error("Out of memory")` check is repeated dozens of times.
  - *Target*: Create a template utility `allocateArray<T>()` or similar.

- **Recursion Depth Management**:
  - *Location*: `parsePostfixExpression`, `parseUnaryExpr`, `parsePrecedenceExpr`, `parseAssignmentExpression`, `parseBlockStatement`, `parseType`.
  - *Description*: Manual increment/decrement of `recursion_depth_` with identical error checks.
  - *Target*: Implement an RAII `RecursionGuard` struct.

- **OOM Guards**:
  - *Location*: Everywhere `arena_->alloc` is called.
  - *Description*: Repeated `if (!ptr) error("Out of memory");`.
  - *Target*: Use a `mustAlloc` helper in the `Parser` class.

### Nested Conditionals & High Complexity

- **Method**: `parseFnDecl`
  - *Target Conditions*:
    - Parameter parsing loop contains nested logic for `comptime`, `anytype`, and `type` parameters.
    - Generic detection logic is intertwined with parameter collection.
    - Disambiguation for return type vs. body start (`{`) is complex.

- **Method**: `parseType`
  - *Target Conditions*:
    - Large switch/if-else chain handling various type prefixes (`*`, `[]`, `!`, `?`, `fn`).
    - Trailing loop for binary type operators (`!` error unions and `||` error set merges) adds another layer of complexity.

- **Method**: `parsePostfixExpression`
  - *Target Conditions*:
    - The `while(true)` loop contains complex branching for function calls, array/slice access (with its own internal range logic), member access, and dereferences.

- **Method**: `resolveAndVerifyType`
  - *Target Conditions*:
    - Deeply nested `if-else` blocks for resolving different type variants, especially for recursive types (pointers, arrays, function pointers).

### Missing Guards

- **Memory Allocation**:
  - *Condition*: In `parsePostfixExpression` (line 330), `arena_->alloc` for `call_node->args` is checked for null, but then a placement `new` is performed. While checked, the pattern is inconsistent across the file—some allocations (like those inside `DynamicArray` itself if it were to grow) are hidden. More importantly, some `createNode` calls are used immediately without checking for the internal `alloc` failure if `error()` were to return (currently it aborts, but that's a debt in itself).

- **Method**: `is_at_end`
  - *Condition*: If the token stream is corrupted (missing `TOKEN_EOF`), it reports an error and returns `true`. Callers may proceed assuming a valid EOF was reached, potentially leading to incomplete ASTs.

- **Method**: `parseStatement`
  - *Condition*: Missing `recursion_depth_` check, unlike `parseBlockStatement` or `parseExpression` chain.

- **Method**: `parsePrimitiveType`
  - *Condition*: Declared in `parser.hpp` but has no implementation in `parser.cpp`.

- **Method**: `Parser::error`
  - *Condition*: Calls `plat_abort()` immediately. This prevents the compiler from reporting multiple independent syntax errors in one pass.
