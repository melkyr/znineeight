# Lexer Design

This document provides an overview of the Lexer for the RetroZig compiler.

## Core Design Philosophy

The lexer is the first stage of the compilation process. It takes the raw source code as input and produces a stream of tokens. Each token represents a single lexical unit, such as a keyword, identifier, literal, or operator.

### Disambiguation

The lexer is responsible for resolving ambiguities in the source code. For example, it must be able to distinguish between a floating-point literal and an integer followed by a range operator.

#### Integer vs. Range Operator Ambiguity

The lexer implements a two-character lookahead to resolve the ambiguity between a float literal and a range operator. When the lexer encounters a `.` after a number, it peeks at the next character. If the next character is also a `.`, the lexer treats the number as an integer and leaves the `..` to be tokenized as a `TOKEN_RANGE` in the next step.
