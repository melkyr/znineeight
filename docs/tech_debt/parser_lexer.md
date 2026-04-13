# Technical Debt: Parser and Lexer

This document tracks technical debt and potential improvements for the bootstrap Lexer and Parser.

## Lexer Issues
- **Cyclomatic Complexity**: The `nextToken` method has high complexity due to manual character matching and state management.
- **Newline Handling**: Inconsistent newline handling in some matching patterns.
- `TOKEN_MEMBER_NUMBER` was removed to avoid ambiguity with floats, but this requires `Parser` lookahead for `t.0`.

## Parser Issues
- **Missing Null Checks**: Recurring pattern of missing null checks after `arena_->alloc` calls (though the arena itself is hard-limited).
- **Complexity in `parseAnonymousLiteral`**: Lookahead logic for disambiguating named initializers vs tuples vs naked tags is dense and hard to maintain.
- **Incomplete Implementation**: `Parser::parsePrimitiveType` is declared in `parser.hpp` but missing from `parser.cpp`.
