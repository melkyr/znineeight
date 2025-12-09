# Lexer Implementation Status

This document tracks the implementation status of all tokens required for the RetroZig compiler. It is based on a gap analysis between the official Zig language specification and the current lexer implementation.

## 1. Literals

| Token Type              | Example      | Implemented | Notes                                  |
| ----------------------- | ------------ | ----------- | -------------------------------------- |
| `TOKEN_IDENTIFIER`      | `my_var`     | No          | Part of Task 16.                         |
| `TOKEN_INTEGER_LITERAL` | `123`, `0xFF`| No          | Part of Task 17.                         |
| `TOKEN_STRING_LITERAL`  | `"hello"`    | No          | Part of Task 18.                         |
| `TOKEN_CHAR_LITERAL`    | `'a'`        | No          | New task required.                     |
| `TOKEN_FLOAT_LITERAL`   | `3.14`       | No          | Mentioned in `DESIGN.md`, new task required. |

## 2. Operators

### 2.1 Arithmetic and Bitwise Operators

| Token Type        | Symbol | Implemented | Notes                |
| ----------------- | ------ | ----------- | -------------------- |
| `TOKEN_PLUS`      | `+`    | Yes         |                      |
| `TOKEN_MINUS`     | `-`    | Yes         |                      |
| `TOKEN_STAR`      | `*`    | Yes         |                      |
| `TOKEN_SLASH`     | `/`    | Yes         |                      |
| `TOKEN_PERCENT`   | `%`    | No          | New task required.   |
| `TOKEN_TILDE`     | `~`    | No          | Bitwise NOT. New task required. |
| `TOKEN_AMPERSAND` | `&`    | No          | Bitwise AND. New task required. |
| `TOKEN_PIPE`      | `|`    | No          | Bitwise OR. New task required.  |
| `TOKEN_CARET`     | `^`    | No          | Bitwise XOR. New task required. |
| `TOKEN_LARROW2`   | `<<`   | No          | Bitwise Shift Left. New task required. |
| `TOKEN_RARROW2`   | `>>`   | No          | Bitwise Shift Right. New task required. |

### 2.2 Comparison and Equality Operators

| Token Type            | Symbol | Implemented | Notes |
| --------------------- | ------ | ----------- | ----- |
| `TOKEN_EQUAL_EQUAL`   | `==`   | Yes         |       |
| `TOKEN_BANG_EQUAL`    | `!=`   | Yes         |       |
| `TOKEN_LESS`          | `<`    | Yes         |       |
| `TOKEN_LESS_EQUAL`    | `<=`   | Yes         |       |
| `TOKEN_GREATER`       | `>`    | Yes         |       |
| `TOKEN_GREATER_EQUAL` | `>=`   | Yes         |       |

### 2.3 Assignment and Compound Assignment

| Token Type             | Symbol | Implemented | Notes |
| ---------------------- | ------ | ----------- | ----- |
| `TOKEN_EQUAL`          | `=`    | Yes         |       |
| `TOKEN_PLUS_EQUAL`     | `+=`   | No          | New task required. |
| `TOKEN_MINUS_EQUAL`    | `-=`   | No          | New task required. |
| `TOKEN_STAR_EQUAL`     | `*=`   | No          | New task required. |
| `TOKEN_SLASH_EQUAL`    | `/=`   | No          | New task required. |
| `TOKEN_PERCENT_EQUAL`  | `%=`   | No          | New task required. |
| `TOKEN_AMPERSAND_EQUAL`| `&=`   | No          | New task required. |
| `TOKEN_PIPE_EQUAL`     | `|=`   | No          | New task required. |
| `TOKEN_CARET_EQUAL`    | `^=`   | No          | New task required. |
| `TOKEN_LARROW2_EQUAL`  | `<<=`  | No          | New task required. |
| `TOKEN_RARROW2_EQUAL`  | `>>=`  | No          | New task required. |

### 2.4 Special and Wrapping Operators

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

## 3. Keywords

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

## 4. Delimiters and Other Symbols

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
