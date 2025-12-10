# RetroZig Lexer Specification

This document provides a detailed specification for the RetroZig lexer. It outlines the tokenization process, error handling, and the complete list of tokens the lexer is responsible for recognizing.

## 1. Tokenization Process

The lexer scans the source file character by character, grouping them into meaningful tokens. It recognizes keywords, identifiers, literals, operators, and delimiters. The process also involves skipping non-token elements like whitespace and comments.

### 1.1 Whitespace

All whitespace characters (`' '`, `'\t'`, `'\r'`, `'\n'`) are consumed and ignored by the lexer. They serve only to separate other tokens. Line breaks (`'\n'`) are significant for tracking token locations (line and column numbers).

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

## 2. Token Implementation Status

This section tracks the implementation status of all tokens required for the RetroZig compiler. It is based on a gap analysis between the official Zig language specification and the current lexer implementation.

### 2.1. Literals

| Token Type              | Example      | Implemented | Notes                                  |
| ----------------------- | ------------ | ----------- | -------------------------------------- |
| `TOKEN_IDENTIFIER`      | `my_var`     | No          | Part of Task 16.                         |
| `TOKEN_INTEGER_LITERAL` | `123`, `0xFF`| No          | Part of Task 17.                         |
| `TOKEN_STRING_LITERAL`  | `"hello"`    | No          | Part of Task 18.                         |
| `TOKEN_CHAR_LITERAL`    | `'a'`        | Yes         | Implemented as part of Task 18.        |
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
| `TOKEN_PLUS_EQUAL`     | `+=`   | No          | New task required. |
| `TOKEN_MINUS_EQUAL`    | `-=`   | No          | New task required. |
| `TOKEN_STAR_EQUAL`     | `*=`   | No          | New task required. |
| `TOKEN_SLASH_EQUAL`    | `/=`   | No          | New task required. |
| `TOKEN_PERCENT_EQUAL`  | `%=`  | No          | New task required. |
| `TOKEN_AMPERSAND_EQUAL`| `&=`   | No          | New task required. |
| `TOKEN_PIPE_EQUAL`     | `|=`   | No          | New task required. |
| `TOKEN_CARET_EQUAL`    | `^=`   | No          | New task required. |
| `TOKEN_LARROW2_EQUAL`  | `<<=`  | No          | New task required. |
| `TOKEN_RARROW2_EQUAL`  | `>>=`  | No          | New task required. |

#### 2.2.4 Special and Wrapping Operators

| Token Type         | Symbol | Implemented | Notes                       |
| ------------------ | ------ | ----------- | --------------------------- |
| `TOKEN_DOT`        | `.`    | No          | New task required.          |
| `TOKEN_DOT_ASTERISK`| `.*`   | No          | New task required.          |
| `TOKEN_DOT_QUESTION`| `.?`   | No          | New task required.          |
| `TOKEN_QUESTION`   | `?`    | No          | For optionals. New task required. |
| `TOKEN_PLUS2`      | `++`   | No          | Array concatenation. New task required. |
| `TOKEN_STAR2`      | `**`   | No          | Array multiplication. New task required. |
| `TOKEN_PIPE2`      | `||`   | No          | Error set merge. New task required. |
| `TOKEN_PLUSPERCENT`| `+%`   | No          | Wrapping addition. New task required. |
| `TOKEN_MINUSPERCENT`| `-%`   | No          | Wrapping subtraction. New task required. |
| `TOKEN_STARPERCENT`| `*%`   | No          | Wrapping multiplication. New task required. |

### 2.3. Keywords

The following keywords are defined in the Zig grammar but are not yet implemented in the lexer.

- `addrspace`
- `align`
- `allowzero`
- `and`
- `anyframe`
- `anytype`
- `asm`
- `break`
- `callconv`
- `catch`
- `comptime`
- `continue`
- `else`
- `enum`
- `errdefer`
- `error`
- `export`
- `extern`
- `for`
- `inline`
- `noalias`
- `nosuspend`
- `noinline`
- `opaque`
- `or`
- `orelse`
- `packed`
- `pub`
- `resume`
- `linksection`
- `struct`
- `suspend`
- `switch`
- `test`
- `threadlocal`
- `try`
- `union`
- `unreachable`
- `usingnamespace`
- `volatile`

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
| `TOKEN_COLON`     | `:`    | No          | New task required. |
| `TOKEN_ARROW`     | `->`   | No          | New task required. |
| `TOKEN_FAT_ARROW` | `=>`   | No          | New task required. |
| `TOKEN_ELLIPSIS`  | `...`  | No          | New task required. |
