# RetroZig Lexer

This document details the behavior of the RetroZig lexer, the first stage of the compilation pipeline. The lexer's primary responsibility is to convert a stream of source code characters into a stream of tokens.

## Tokenization Process

The lexer scans the source file character by character, grouping them into meaningful tokens. It recognizes keywords, identifiers, literals, operators, and delimiters. The process also involves skipping non-token elements like whitespace and comments.

### Whitespace

All whitespace characters (`' '`, `'\t'`, `'\r'`, `'\n'`) are consumed and ignored by the lexer. They serve only to separate other tokens. Line breaks (`'\n'`) are significant for tracking token locations (line and column numbers).

### Comments

The lexer supports two types of comments, which are consumed and discarded:

1.  **Line Comments:** A line comment begins with `//` and continues until the end of the line. If the file ends immediately after a `//`, it is handled gracefully.

    ```zig
    // This is a line comment.
    var x = 1; // This comment follows a statement.
    ```

2.  **Block Comments:** A block comment begins with `/*` and ends with `*/`. These comments are nestable, meaning the lexer correctly balances opening `/*` and closing `*/` pairs.

    ```zig
    /* This is a simple block comment. */
    var y = 2;

    /*
      This is a multi-line
      /* nested block comment */
      and is handled correctly.
    */
    var z = 3;
    ```

    If a block comment is not terminated by the end of the file, the lexer will consume the rest of the file without generating an error, as this is considered a user error.

### Operators and Delimiters

The lexer recognizes a variety of single-character and multi-character operators and delimiters:

*   **Single-Character:** `+`, `-`, `*`, `/`, `;`, `(`, `)`, `{`, `}`, `[`, `]`
*   **Multi-Character:** `==`, `!=`, `<=`, `>=`

The lexer uses a lookahead mechanism to distinguish between single-character and multi-character tokens (e.g., between `=` and `==`).

### Error Handling

If the lexer encounters a character that does not belong to any valid token, it produces a `TOKEN_ERROR` token. This allows the parser to handle lexical errors gracefully.
