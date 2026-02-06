# Lexer Design (v1.1)

This document provides an overview of the Lexer for the RetroZig compiler.

## Core Design Philosophy

The lexer is the first stage of the compilation process. It takes the raw source code as input and produces a stream of tokens. Each token represents a single lexical unit, such as a keyword, identifier, literal, or operator. The lexer is designed to be fast, memory-efficient, and robust, with a focus on safety and correctness.

## Key Features and Implementation Details

### Integer Parsing

The lexer uses a custom 64-bit integer parser to handle integer literals. This parser correctly handles `u64` values, avoiding the limitations of `strtol` on 32-bit systems. It supports both decimal and hexadecimal literals.

### Escape Sequence Parsing

Escape sequence parsing is centralized in a single helper function, `parseEscapeSequence`, which is used by both character and string literal parsing. This approach eliminates code duplication and ensures consistent behavior. The parser correctly handles standard escape sequences, hexadecimal escapes (`\xNN`), and Unicode escapes (`\u{...}`). It also includes bounds checking to prevent reading past the end of the source buffer.

### Identifier and Keyword Lookup

Identifier and keyword lookup is performed using an optimized binary search algorithm. The `Keyword` struct includes a pre-calculated length field, which allows the search to be optimized by first comparing the length of the identifier with the length of the keyword. This avoids unnecessary string comparisons and improves performance.

### Safety and Error Handling

The lexer is designed with safety in mind. It includes checks to prevent common issues such as buffer overflows and out-of-bounds reads. For example, the numeric lookahead logic for disambiguating between a float and a range operator includes a check for the null terminator to prevent reading past the end of the buffer.

### Disambiguation

The lexer is responsible for resolving ambiguities in the source code. For example, it must be able to distinguish between a floating-point literal and an integer followed by a range operator.

#### Integer vs. Range Operator Ambiguity

The lexer implements a two-character lookahead to resolve the ambiguity between a float literal and a range operator. When the lexer encounters a `.` after a number, it peeks at the next character. If the next character is also a `.`, the lexer treats the number as an integer and leaves the `..` to be tokenized as a `TOKEN_RANGE` in the next step.

## New Keywords and Operators (Milestone 4)

### Keywords
- `type`: Used for type expressions and generic parameters.
- `anytype`: Used for generic parameters where any type is accepted.
- `comptime`: Used for compile-time constants and parameters.

### Operators
- `--`: Decrement operator (added for complete operator coverage).
- `||`: Error set merging operator.
