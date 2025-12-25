# RetroZig Lexer Specification

This document provides a detailed specification for the RetroZig lexer. It outlines the tokenization process, error handling, and the complete list of tokens the lexer is responsible for recognizing.

## 1. Tokenization Process

The lexer scans the source file character by character, grouping them into meaningful tokens. It recognizes keywords, identifiers, literals, operators, and delimiters. The process also involves skipping non-token elements like whitespace and comments.

### 1.1 Whitespace

All whitespace characters (`' '`, `'\t'`, `'\r'`, `'\n'`) are consumed and ignored by the lexer. They serve only to separate other tokens. Line breaks (`'\n'`) are significant for tracking token locations (line and column numbers). Tab characters (`\t`) are handled specially for column tracking: they advance the column to the next 4-space tab stop to ensure accurate error reporting.

### 1.2 Comments

The lexer supports two types of comments, which are consumed and discarded:

1.  **Line Comments:** A line comment begins with `//` and continues until the end of the line.
    ```zig
    // This is a line comment.
    var x = 1; // This comment follows a statement.
    ```

2.  **Block Comments:** A block comment begins with `/*` and ends with `*/`. These comments are nestable, meaning the lexer correctly balances opening `/*` and closing `*/` pairs.
    ```zig
    /*
      This is a multi-line
      /* nested block comment */
      and is handled correctly.
    */
    var z = 3;
    ```
    If a block comment is not terminated by the end of the file, the lexer will consume the rest of the file without generating an error.

### 1.3 Error Handling

If the lexer encounters a character that does not belong to any valid token, it produces a `TOKEN_ERROR` token. This allows the parser to handle lexical errors gracefully.

### 1.4 Internal Safety Mechanisms

The lexer is designed with several internal safety features to ensure robust and predictable behavior, especially when handling edge cases at the end of a file.

*   **Safe Peeking:** The lexer's internal `peek(n)` method, used for lookaheads, is designed to be safe against buffer over-reads. If a lookahead operation requests a character at or beyond the end of the source buffer, the lexer will safely return a null character (`\0`) instead of reading from invalid memory. This prevents crashes and ensures that multi-character token checks (e.g., for `..` or `==`) are handled correctly, even when they appear at the very end of the file.

## 2. Token Implementation Status

This section tracks the implementation status of all tokens required for the RetroZig compiler. It is based on a gap analysis between the official Zig language specification and the current lexer implementation.

### 2.1. Literals

| Token Type              | Example      | Implemented | Notes                                  |
| ----------------------- | ------------ | ----------- | -------------------------------------- |
| `TOKEN_IDENTIFIER`      | `my_var`     | Yes         | Now stores its value in the string interner. No longer has a length limit. |
| `TOKEN_INTEGER_LITERAL` | `123`, `0xFF`| Yes         | Implemented as part of Task 17.        |
| `TOKEN_STRING_LITERAL`  | `"hello"`    | Yes         | Now supports escape sequences: `\n`, `\r`, `\t`, `\\`, `\"`, `\xNN`. Also supports C-style strings (c"hello") and multiline strings ("hello\\\nworld"). |
| `TOKEN_CHAR_LITERAL`    | `'a'`        | Yes         | Now supports Unicode escape sequences (e.g., `\u{1F4A9}`) with validation. |
| `TOKEN_FLOAT_LITERAL`   | `3.14`       | Yes         | Implemented as part of Task 19.        |

### 2.2. Operators

#### 2.2.1 Arithmetic and Bitwise Operators

| Token Type        | Symbol | Implemented | Notes                |
| ----------------- | ------ | ----------- | -------------------- |
| `TOKEN_PLUS`      | `+`    | Yes         |                      |
| `TOKEN_MINUS`     | `-`    | Yes         |                      |
| `TOKEN_STAR`      | `*`    | Yes         |                      |
| `TOKEN_SLASH`     | `/`    | Yes         |                      |
| `TOKEN_PERCENT`   | `%`    | Yes         | Implemented as part of Task 20. |
| `TOKEN_TILDE`     | `~`    | Yes         | Implemented as part of Task 20. |
| `TOKEN_AMPERSAND` | `&`    | Yes         | Implemented as part of Task 20. |
| `TOKEN_PIPE`      | `|`    | Yes         | Implemented as part of Task 20. |
| `TOKEN_CARET`     | `^`    | Yes         | Implemented as part of Task 20. |
| `TOKEN_LARROW2`   | `<<`   | Yes         | Implemented as part of Task 20. |
| `TOKEN_RARROW2`   | `>>`   | Yes         | Implemented as part of Task 20. |

#### 2.2.2 Comparison and Equality Operators

| Token Type            | Symbol | Implemented | Notes |
| --------------------- | ------ | ----------- | ----- |
| `TOKEN_EQUAL_EQUAL`   | `==`   | Yes         |       |
| `TOKEN_BANG_EQUAL`    | `!=`   | Yes         |       |
| `TOKEN_LESS`          | `<`    | Yes         |       |
| `TOKEN_LESS_EQUAL`    | `<=`   | Yes         |       |
| `TOKEN_GREATER`       | `>`    | Yes         |       |
| `TOKEN_GREATER_EQUAL` | `>=`   | Yes         |       |

#### 2.2.3 Assignment and Compound Assignment

| Token Type             | Symbol | Implemented | Notes |
| ---------------------- | ------ | ----------- | ----- |
| `TOKEN_EQUAL`          | `=`    | Yes         |       |
| `TOKEN_PLUS_EQUAL`     | `+=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_MINUS_EQUAL`    | `-=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_STAR_EQUAL`     | `*=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_SLASH_EQUAL`    | `/=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_PERCENT_EQUAL`  | `%=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_AMPERSAND_EQUAL`| `&=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_PIPE_EQUAL`     | `|=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_CARET_EQUAL`    | `^=`   | Yes         | Implemented as part of Task 21. |
| `TOKEN_LARROW2_EQUAL`  | `<<=`  | Yes         | Implemented as part of Task 21. |
| `TOKEN_RARROW2_EQUAL`  | `>>=`  | Yes         | Implemented as part of Task 21. |

#### 2.2.4 Special and Wrapping Operators

| Token Type         | Symbol | Implemented | Notes                       |
| ------------------ | ------ | ----------- | --------------------------- |
| `TOKEN_DOT`        | `.`    | Yes         | Implemented as part of Task 22. |
| `TOKEN_DOT_ASTERISK`| `.*`   | Yes         | Implemented as part of Task 22. |
| `TOKEN_DOT_QUESTION`| `.?`   | Yes         | Implemented as part of Task 22. |
| `TOKEN_QUESTION`   | `?`    | Yes         | Implemented as part of Task 22. |
| `TOKEN_PLUS2`      | `++`   | Yes         | Implemented as part of Task 22. |
| `TOKEN_STAR2`      | `**`   | Yes         | Implemented as part of Task 22. |
| `TOKEN_PIPE2`      | `||`   | Yes         | Implemented as part of Task 22. |
| `TOKEN_PLUSPERCENT`| `+%`   | Yes         | Implemented as part of Task 22. |
| `TOKEN_MINUSPERCENT`| `-%`   | Yes         | Implemented as part of Task 22. |
| `TOKEN_STARPERCENT`| `*%`   | Yes         | Implemented as part of Task 22. |

### 2.3. Keywords

#### 2.3.1 Implemented Keywords

| Token Type | Keyword |
| --- | --- |
| `TOKEN_BREAK` | `break` |
| `TOKEN_CATCH` | `catch` |
| `TOKEN_CONTINUE` | `continue` |
| `TOKEN_ELSE` | `else` |
| `TOKEN_FOR` | `for` |
| `TOKEN_IF` | `if` |
| `TOKEN_ORELSE` | `orelse` |
| `TOKEN_RESUME` | `resume` |
| `TOKEN_SUSPEND` | `suspend` |
| `TOKEN_SWITCH` | `switch` |
| `TOKEN_TRY` | `try` |
| `TOKEN_WHILE` | `while` |
| `TOKEN_ENUM` | `enum` |
| `TOKEN_ERROR_SET` | `error` |
| `TOKEN_STRUCT` | `struct` |
| `TOKEN_UNION` | `union` |
| `TOKEN_OPAQUE` | `opaque` |
| `TOKEN_EXPORT` | `export` |
| `TOKEN_EXTERN` | `extern` |
| `TOKEN_PUB` | `pub` |
| `TOKEN_LINKSECTION` | `linksection` |
| `TOKEN_USINGNAMESPACE` | `usingnamespace` |
| `TOKEN_ADDRSPACE` | `addrspace` |
| `TOKEN_ALIGN` | `align` |
| `TOKEN_ALLOWZERO` | `allowzero` |
| `TOKEN_AND` | `and` |
| `TOKEN_ANYFRAME` | `anyframe` |
| `TOKEN_ANYTYPE` | `anytype` |
| `TOKEN_CALLCONV` | `callconv` |
| `TOKEN_NOALIAS` | `noalias` |
| `TOKEN_NOSUSPEND` | `nosuspend` |
| `TOKEN_OR` | `or` |
| `TOKEN_PACKED` | `packed` |
| `TOKEN_THREADLOCAL` | `threadlocal` |
| `TOKEN_VOLATILE` | `volatile` |

The following keywords for compile-time and special functions are also implemented:

| Token Type | Keyword |
| --- | --- |
| `TOKEN_ASM` | `asm` |
| `TOKEN_COMPTIME` | `comptime` |
| `TOKEN_ERRDEFER` | `errdefer` |
| `TOKEN_INLINE` | `inline` |
| `TOKEN_NOINLINE` | `noinline` |
| `TOKEN_TEST` | `test` |
| `TOKEN_UNREACHABLE` | `unreachable` |

### 2.4. Delimiters and Other Symbols

| Token Type      | Symbol | Implemented | Notes              |
| --------------- | ------ | ----------- | ------------------ |
| `TOKEN_LPAREN`    | `(`    | Yes         |                    |
| `TOKEN_RPAREN`    | `)`    | Yes         |                    |
| `TOKEN_LBRACE`    | `{`    | Yes         |                    |
| `TOKEN_RBRACE`    | `}`    | Yes         |                    |
| `TOKEN_LBRACKET`  | `[`    | Yes         |                    |
| `TOKEN_RBRACKET`  | `]`    | Yes         |                    |
| `TOKEN_SEMICOLON` | `;`    | Yes         |                    |
| `TOKEN_COLON`     | `:`    | Yes         | Implemented as part of Task 23. |
| `TOKEN_ARROW`     | `->`   | Yes         | Implemented as part of Task 23. |
| `TOKEN_FAT_ARROW` | `=>`   | Yes         | Implemented as part of Task 23. |
| `TOKEN_ELLIPSIS`  | `...`  | Yes         | Implemented as part of Task 23. |
| `TOKEN_RANGE`     | `..`   | Yes         | Implemented as part of Task 75. |

## 3. Scope for Floats and Integers

This section details the currently supported syntax for numeric literals in the RetroZig lexer.

### 3.1 Integer Literals

The lexer supports decimal and hexadecimal integer literals.

#### Supported Integer Syntax:

*   **Decimal Literals:** A sequence of digits `0-9`.
    *   `123`
    *   `0`
    *   `42`
*   **Hexadecimal Literals:** Prefixed with `0x` or `0X`, followed by a sequence of hex digits (`0-9`, `a-f`, `A-F`).
    *   `0xFF`
    *   `0x1a`
    *   `0XDEADBEEF`

#### Unsupported Integer Syntax:

*   **Octal Literals:** Prefixes like `0o` are not supported.
*   **Binary Literals:** Prefixes like `0b` are not supported.
*   **Underscore Separators:** Underscores within numbers (e.g., `1_000_000`) are not supported.

### 3.2 Floating-Point Literals

The lexer supports decimal and hexadecimal floating-point literals.

#### Supported Floating-Point Syntax:

*   **Decimal Floats:**
    *   Must contain a decimal point (`.`).
    *   Must have digits on both sides of the decimal point.
    *   Can have an optional exponent part, denoted by `e` or `E`, followed by an optional sign (`+` or `-`) and a sequence of digits.
    *   An integer followed by an exponent is also a valid float.
    *   Examples:
        *   `3.14`
        *   `1.23e+4`
        *   `5.67E-8`
        *   `9.0e10`
        *   `1e10`
*   **Hexadecimal Floats:**
    *   Must be prefixed with `0x` or `0X`.
    *   Must contain a binary exponent part, denoted by `p` or `P`. The exponent is a decimal integer.
    *   Can have an integer part and an optional fractional part separated by a decimal point.
    *   Examples:
        *   `0x1.Ap2`
        *   `0x10p-1`
        *   `0xAB.CDp-4`

#### Unsupported/Invalid Floating-Point Syntax:

*   **Missing digits around decimal point:** A decimal point must be surrounded by digits.
    *   Invalid: `123.`
    *   Invalid: `.123`
*   **Invalid exponent:** The exponent part must have at least one digit.
    *   Invalid: `1.2e`
    *   Invalid: `3.4e+`
*   **Invalid hex float format:** A hex float must have a `p` or `P` exponent.
    *   Invalid: `0x1.A`
    *   Invalid: `0x1.Ap`
    *   Invalid: `0x1.Ap-`
