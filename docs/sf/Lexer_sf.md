# Self-Hosted Lexer Design Specification

**Version:** 1.1  
**Component:** `zig1` lexer, token stream, and source scanning  
**Parent Document:** DESIGN.md v3.0, AST\_PARSER.md  
**Supersedes:** Bootstrap lexer.cpp (C++ implementation)

---

> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation.

---

## 1. Scope and Relationship to Bootstrap

This document specifies the lexer for the self-hosted Z98 compiler (`zig1`). It replaces the bootstrap's C++ lexer with a Z98-native implementation optimized for cache locality, deterministic output, and strict memory budgeting.

| Bootstrap (`zig0`) | Self-Hosted (`zig1`) | Why |
|---|---|---|
| `Token` with `union { int_val, float_val, string_ptr }` (24+ bytes, pointer) | `Token` with `union { int_val: u64, float_val: f64, string_id: u32 }` (16 bytes, index) | No pointer chasing; string content via `StringInterner` index |
| `std::string` for literal storage | `StringInterner` with FNV-1a hash, open addressing | Arena-backed, deduplicated, deterministic |
| Recursive `skipComments()` with depth limit | Iterative `skipWhitespaceAndComments()` with loop + switch | No recursion; handles nested `/* */` safely |
| Linear keyword table scan (35 entries) | Same, but stored in `pub var` initialized at startup | Z98 constraint: no global aggregate constants |
| `Token` allocated per-token in arena | `Token` stored in flat `ArrayList(Token)` per module | Cache-friendly; reset after parsing completes |
| C++98 with `ArenaAllocator` | Z98 with `std.heap.ArenaAllocator` | Self-hosting |

---

## 2. Token: The Core Structure

### 2.1 Layout

```zig
pub const Token = struct {
    kind: TokenKind,      // u16 enum — 88 possible values
    span_start: u32,      // byte offset in source file (0..4GB)
    span_len: u16,        // length in bytes (0..65535; sufficient for any token)
    value: TokenValue,    // payload union for literals
};

pub const TokenValue = union {
    int_val: u64,         // integer, char, enum tag values
    float_val: f64,       // floating-point literals
    string_id: u32,       // index into StringInterner (identifiers, strings)
    none: void,           // for operators, keywords, delimiters
};
// sizeof = 16 bytes. Four tokens per 64-byte cache line.
```

**Comparison with bootstrap:** The bootstrap `Token` is ~24 bytes due to pointer-sized `string_ptr` and alignment padding. The self-hosted token is 16 bytes and stores MORE information (explicit `span_len`) because it eliminates pointer overhead. String content is accessed via `interner.get(token.value.string_id)`.

**Sentinel:** `TokenKind.eof` is used as the end-of-stream marker. No special "null token" — the lexer always returns a valid `Token`.

**Keyword value convention:** Keywords carry `.{ .none = {} }` as their value — no payload. The parser dispatches on `kind` alone for keywords. Identifiers and string literals carry `.{ .string_id = ... }` pointing into the `StringInterner`. Integer and char literals carry `.{ .int_val = ... }`. Float literals carry `.{ .float_val = ... }`.

### 2.2 Span Encoding

- `span_start`: Absolute byte offset from the start of the source file.
- `span_len`: Number of bytes the token occupies in source.
- `span_end = span_start + span_len` (computed on demand, not stored).

This encoding supports:
- Precise diagnostic reporting (caret under exact token).
- Differential token comparison (`--dump-tokens` must match `zig0` output).
- Source mapping for generated C89 (debug info).

---

## 3. TokenKind Enum (Complete)

This enum defines every token the lexer can produce. It is the contract between the lexer and the parser.

```zig
pub const TokenKind = enum(u16) {
    // ═══ Literals ═══
    integer_literal,      // 123, 0xFF, 0b1010, 0o77, 1_000_000
    float_literal,        // 3.14, 1.0e-5, 2.0e+10
    string_literal,       // "hello\nworld"
    char_literal,         // 'a', '\n', '\xFF'

    // ═══ Identifiers ═══
    identifier,           // foo, bar_baz, _my_var, i32, usize
    builtin_identifier,   // @sizeOf, @intCast, @import, @ptrCast, etc.

    // ═══ Single-character tokens ═══
    lparen,               // (
    rparen,               // )
    lbracket,             // [
    rbracket,             // ]
    lbrace,               // {
    rbrace,               // }
    semicolon,            // ;
    colon,                // :
    comma,                // ,
    dot,                  // .
    underscore,           // _ (bare discard pattern; NOT identifiers starting with _)
    question_mark,        // ? (optional type prefix)
    bang,                 // ! (error union prefix / boolean not)

    // ═══ Arithmetic operators ═══
    plus,                 // +
    minus,                // -
    star,                 // *
    slash,                // /
    percent,              // %

    // ═══ Bitwise operators ═══
    ampersand,            // & (also address-of)
    pipe,                 // | (also capture delimiter)
    caret,                // ^
    tilde,                // ~ (bitwise not)

    // ═══ Shift operators ═══
    shl,                  // <<
    shr,                  // >>

    // ═══ Comparison operators ═══
    eq_eq,                // ==
    bang_eq,              // !=
    less,                 // <
    less_eq,              // <=
    greater,              // >
    greater_eq,           // >=

    // ═══ Assignment operators ═══
    eq,                   // =
    plus_eq,              // +=
    minus_eq,             // -=
    star_eq,              // *=
    slash_eq,             // /=
    percent_eq,           // %=
    ampersand_eq,         // &=
    pipe_eq,              // |=
    caret_eq,             // ^=
    shl_eq,               // <<=
    shr_eq,               // >>=

    // ═══ Dots and ranges ═══
    dot_dot,              // ..   (exclusive range: start..end)
    dot_dot_dot,          // ...  (inclusive range: start...end)
    dot_lbrace,           // .{   (anonymous literal)
    dot_star,             // .*   (dereference: expr.*)

    // ═══ Fat arrow ═══
    fat_arrow,            // =>   (switch prong separator)

    // ═══ Keywords: declarations ═══
    kw_const,
    kw_var,
    kw_fn,
    kw_pub,
    kw_extern,
    kw_export,
    kw_test,

    // ═══ Keywords: types ═══
    kw_struct,
    kw_enum,
    kw_union,

    // ═══ Keywords: control flow ═══
    kw_if,
    kw_else,
    kw_while,
    kw_for,
    kw_switch,
    kw_return,
    kw_break,
    kw_continue,
    kw_defer,
    kw_errdefer,

    // ═══ Keywords: error handling ═══
    kw_try,
    kw_catch,
    kw_orelse,
    kw_error,             // error.TagName

    // ═══ Keywords: boolean / logical ═══
    kw_and,
    kw_or,
    kw_true,
    kw_false,

    // ═══ Keywords: special values ═══
    kw_null,
    kw_undefined,
    kw_unreachable,

    // ═══ Keywords: type names (recognized for faster dispatch) ═══
    kw_void,
    kw_bool,
    kw_noreturn,
    kw_c_char,

    // ═══ Special ═══
    eof,
    err_token,            // unrecognized character (error recovery)

    // ═══ Reserved for extensibility ═══
    // After self-hosting, new keywords can be added here:
    // kw_comptime, kw_inline, kw_noinline, kw_anytype, kw_anyerror,
    // kw_usingnamespace, kw_opaque, kw_asm, kw_linksection,
};
```

**Total: 88 token kinds** (86 defined + `eof` + `err_token`). This fits in `u16` with ample room for post-self-hosting additions.

### 3.1 Type-Name Keywords: Why Only Some?

| Keyword | Lexed as | Reason |
|---|---|---|
| `void`, `bool`, `noreturn`, `c_char` | `kw_*` keyword | Used in type-expression parsing to disambiguate from identifiers |
| `i8`..`i64`, `u8`..`u64`, `isize`, `usize`, `f32`, `f64` | `identifier` | No parsing benefit; resolved to primitives during semantic analysis |
| `struct`, `enum`, `union` | `kw_*` keyword | Required to parse container declarations |

This reduces the token enum size and avoids unnecessary keyword table entries.

### 3.2 Keyword Table

Keywords are stored in a flat array initialized at startup (Z98 constraint: no global aggregate constants):

```zig
pub var keyword_table: []KeywordEntry = undefined;
pub var keyword_count: usize = 0;

pub const KeywordEntry = struct {
    name: []const u8,
    kind: TokenKind,
};

pub fn initKeywordTable(alloc: *Allocator) !void {
    var table = try alloc.alloc(KeywordEntry, 35);
    var i: usize = 0;
    table[i] = .{ .name = "const",       .kind = .kw_const };       i += 1;
    table[i] = .{ .name = "var",         .kind = .kw_var };         i += 1;
    table[i] = .{ .name = "fn",          .kind = .kw_fn };          i += 1;
    table[i] = .{ .name = "pub",         .kind = .kw_pub };         i += 1;
    table[i] = .{ .name = "extern",      .kind = .kw_extern };      i += 1;
    table[i] = .{ .name = "export",      .kind = .kw_export };      i += 1;
    table[i] = .{ .name = "test",        .kind = .kw_test };        i += 1;
    table[i] = .{ .name = "struct",      .kind = .kw_struct };      i += 1;
    table[i] = .{ .name = "enum",        .kind = .kw_enum };        i += 1;
    table[i] = .{ .name = "union",       .kind = .kw_union };       i += 1;
    table[i] = .{ .name = "if",          .kind = .kw_if };          i += 1;
    table[i] = .{ .name = "else",        .kind = .kw_else };        i += 1;
    table[i] = .{ .name = "while",       .kind = .kw_while };       i += 1;
    table[i] = .{ .name = "for",         .kind = .kw_for };         i += 1;
    table[i] = .{ .name = "switch",      .kind = .kw_switch };      i += 1;
    table[i] = .{ .name = "return",      .kind = .kw_return };      i += 1;
    table[i] = .{ .name = "break",       .kind = .kw_break };       i += 1;
    table[i] = .{ .name = "continue",    .kind = .kw_continue };    i += 1;
    table[i] = .{ .name = "defer",       .kind = .kw_defer };       i += 1;
    table[i] = .{ .name = "errdefer",    .kind = .kw_errdefer };    i += 1;
    table[i] = .{ .name = "try",         .kind = .kw_try };         i += 1;
    table[i] = .{ .name = "catch",       .kind = .kw_catch };       i += 1;
    table[i] = .{ .name = "orelse",      .kind = .kw_orelse };      i += 1;
    table[i] = .{ .name = "error",       .kind = .kw_error };       i += 1;
    table[i] = .{ .name = "and",         .kind = .kw_and };         i += 1;
    table[i] = .{ .name = "or",          .kind = .kw_or };          i += 1;
    table[i] = .{ .name = "true",        .kind = .kw_true };        i += 1;
    table[i] = .{ .name = "false",       .kind = .kw_false };       i += 1;
    table[i] = .{ .name = "null",        .kind = .kw_null };        i += 1;
    table[i] = .{ .name = "undefined",   .kind = .kw_undefined };   i += 1;
    table[i] = .{ .name = "unreachable", .kind = .kw_unreachable }; i += 1;
    table[i] = .{ .name = "void",        .kind = .kw_void };        i += 1;
    table[i] = .{ .name = "bool",        .kind = .kw_bool };        i += 1;
    table[i] = .{ .name = "noreturn",    .kind = .kw_noreturn };    i += 1;
    table[i] = .{ .name = "c_char",      .kind = .kw_c_char };      i += 1;

    keyword_table = table;
    keyword_count = i; // 35
}

pub fn lookupKeyword(text: []const u8) ?TokenKind {
    // Linear scan: 35 entries is fast on Pentium II.
    // Post-self-hosting: replace with perfect hash for O(1).
    var i: usize = 0;
    while (i < keyword_count) : (i += 1) {
        if (mem_eql(keyword_table[i].name, text)) return keyword_table[i].kind;
    }
    return null;
}
```

**Extensibility:** New keywords are added to both the `TokenKind` enum and the `initKeywordTable` function. No other lexer changes required.

---

## 4. Lexer: Core Implementation

### 4.1 Structure

```zig
pub const Lexer = struct {
    source: []const u8,       // entire source file content
    pos: usize,               // current byte offset
    line: u32,                // current line number (1-based)
    col: u32,                 // current column (1-based, for diagnostics)
    file_id: u32,             // SourceManager file ID
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    string_buf: ArrayList(u8), // reusable scratch buffer for string literal scanning
};
```

**Note:** `string_buf` is a shared scratch buffer allocated once during `init`. It is cleared (`.items.len = 0`) at the start of each `scanString` call, avoiding per-string-literal allocation overhead.

### 4.2 Helper Methods

```zig
pub fn init(source: []const u8, file_id: u32,
            interner: *StringInterner,
            diag: *DiagnosticCollector,
            alloc: *Allocator) Lexer {
    return .{
        .source = source,
        .pos = 0,
        .line = 1,
        .col = 1,
        .file_id = file_id,
        .interner = interner,
        .diag = diag,
        .string_buf = ArrayList(u8).init(alloc),
    };
}

fn peek(self: *Lexer) u8 {
    if (self.pos >= self.source.len) return 0; // EOF sentinel
    return self.source[self.pos];
}

fn peekN(self: *Lexer, n: usize) u8 {
    const idx = self.pos + n;
    if (idx >= self.source.len) return 0;
    return self.source[idx];
}

fn advance(self: *Lexer) u8 {
    if (self.pos >= self.source.len) return 0; // guard: don't advance past end
    const c = self.source[self.pos];
    self.pos += 1;
    if (c == '\n') {
        self.line += 1;
        self.col = 1;
    } else {
        self.col += 1;
    }
    return c;
}

fn match(self: *Lexer, expected: u8) bool {
    if (self.peek() != expected) return false;
    _ = self.advance();
    return true;
}

fn isAtEnd(self: *Lexer) bool {
    return self.pos >= self.source.len;
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
```

### 4.3 Whitespace and Comment Skipping

```zig
pub fn skipWhitespaceAndComments(self: *Lexer) void {
    while (!self.isAtEnd()) {
        const c = self.peek();
        switch (c) {
            // Whitespace: consume and continue looping
            ' ', '\t', '\r', '\n' => {
                _ = self.advance();
            },

            // Potential comment
            '/' => {
                if (self.peekN(1) == '/') {
                    // Line comment: skip to end of line
                    _ = self.advance(); // skip first '/'
                    _ = self.advance(); // skip second '/'
                    while (!self.isAtEnd() and self.peek() != '\n') {
                        _ = self.advance();
                    }
                    // Don't consume the '\n' — the next loop iteration handles it
                } else if (self.peekN(1) == '*') {
                    // Block comment: handle nested /* */
                    _ = self.advance(); // skip '/'
                    _ = self.advance(); // skip '*'
                    var depth: u32 = 1;
                    while (!self.isAtEnd() and depth > 0) {
                        if (self.peek() == '*' and self.peekN(1) == '/') {
                            _ = self.advance(); // skip '*'
                            _ = self.advance(); // skip '/'
                            depth -= 1;
                        } else if (self.peek() == '/' and self.peekN(1) == '*') {
                            _ = self.advance(); // skip '/'
                            _ = self.advance(); // skip '*'
                            depth += 1;
                        } else {
                            _ = self.advance(); // skip any character (advance handles line tracking)
                        }
                    }
                    if (depth > 0) {
                        // Unterminated block comment — report but don't crash
                        try self.diag.diagnostics.append(.{
                            .level = 0,
                            .file_id = self.file_id,
                            .span_start = @intCast(u32, self.pos),
                            .span_end = @intCast(u32, self.pos),
                            .message = "unterminated block comment",
                        });
                    }
                } else {
                    return; // '/' is a real operator token — stop skipping
                }
            },

            // Non-whitespace, non-comment: stop skipping
            else => return,
        }
    }
}
```

**Key decisions:**
- Nested `/* */` comments are supported (Zig-compatible).
- Line/column tracking is handled by `advance()` — every character consumed goes through it.
- No recursion: iterative loop with `depth` counter handles arbitrary nesting.
- Unterminated block comments produce a diagnostic instead of crashing.
- The outer `while` loop continues after consuming whitespace or comments, so `"   /* comment */   42"` correctly skips everything before the `42`.

### 4.4 Token Creation Helpers

```zig
fn makeToken(self: *Lexer, kind: TokenKind, start: usize, value: TokenValue) Token {
    return .{
        .kind = kind,
        .span_start = @intCast(u32, start),
        .span_len = @intCast(u16, self.pos - start),
        .value = value,
    };
}

fn makeErrorToken(self: *Lexer, start: usize) Token {
    // Error recovery: produces a token the parser will handle as AstKind.err
    return .{
        .kind = .err_token,
        .span_start = @intCast(u32, start),
        .span_len = 1,
        .value = .{ .none = {} },
    };
}
```

---

## 5. Scanning Logic: Key Cases

### 5.1 Main Dispatch Loop

```zig
pub fn nextToken(self: *Lexer) Token {
    self.skipWhitespaceAndComments();
    if (self.isAtEnd()) {
        return self.makeToken(.eof, self.pos, .{ .none = {} });
    }

    const start = self.pos;
    const c = self.advance();

    return switch (c) {
        // ═══ Single-character tokens ═══
        '(' => self.makeToken(.lparen, start, .{ .none = {} }),
        ')' => self.makeToken(.rparen, start, .{ .none = {} }),
        '[' => self.makeToken(.lbracket, start, .{ .none = {} }),
        ']' => self.makeToken(.rbracket, start, .{ .none = {} }),
        '{' => self.makeToken(.lbrace, start, .{ .none = {} }),
        '}' => self.makeToken(.rbrace, start, .{ .none = {} }),
        ';' => self.makeToken(.semicolon, start, .{ .none = {} }),
        ':' => self.makeToken(.colon, start, .{ .none = {} }),
        ',' => self.makeToken(.comma, start, .{ .none = {} }),
        '~' => self.makeToken(.tilde, start, .{ .none = {} }),
        '?' => self.makeToken(.question_mark, start, .{ .none = {} }),

        // ═══ Dot variants: . / .. / ... / .{ / .* ═══
        '.' => blk: {
            if (self.match('.')) {
                if (self.match('.')) {
                    break :blk self.makeToken(.dot_dot_dot, start, .{ .none = {} });
                }
                break :blk self.makeToken(.dot_dot, start, .{ .none = {} });
            }
            if (self.match('{')) {
                break :blk self.makeToken(.dot_lbrace, start, .{ .none = {} });
            }
            if (self.match('*')) {
                break :blk self.makeToken(.dot_star, start, .{ .none = {} });
            }
            break :blk self.makeToken(.dot, start, .{ .none = {} });
        },

        // ═══ Operators with = variants ═══
        '+' => if (self.match('='))
            self.makeToken(.plus_eq, start, .{ .none = {} })
        else
            self.makeToken(.plus, start, .{ .none = {} }),
        '-' => if (self.match('='))
            self.makeToken(.minus_eq, start, .{ .none = {} })
        else
            self.makeToken(.minus, start, .{ .none = {} }),
        '*' => if (self.match('='))
            self.makeToken(.star_eq, start, .{ .none = {} })
        else
            self.makeToken(.star, start, .{ .none = {} }),
        '/' => if (self.match('='))
            self.makeToken(.slash_eq, start, .{ .none = {} })
        else
            self.makeToken(.slash, start, .{ .none = {} }),
        '%' => if (self.match('='))
            self.makeToken(.percent_eq, start, .{ .none = {} })
        else
            self.makeToken(.percent, start, .{ .none = {} }),
        '^' => if (self.match('='))
            self.makeToken(.caret_eq, start, .{ .none = {} })
        else
            self.makeToken(.caret, start, .{ .none = {} }),

        // ═══ Compound: & / &= , | / |= , = / == / => , ! / != ═══
        '&' => if (self.match('='))
            self.makeToken(.ampersand_eq, start, .{ .none = {} })
        else
            self.makeToken(.ampersand, start, .{ .none = {} }),
        '|' => if (self.match('='))
            self.makeToken(.pipe_eq, start, .{ .none = {} })
        else
            self.makeToken(.pipe, start, .{ .none = {} }),
        '=' => blk: {
            if (self.match('=')) break :blk self.makeToken(.eq_eq, start, .{ .none = {} });
            if (self.match('>')) break :blk self.makeToken(.fat_arrow, start, .{ .none = {} });
            break :blk self.makeToken(.eq, start, .{ .none = {} });
        },
        '!' => if (self.match('='))
            self.makeToken(.bang_eq, start, .{ .none = {} })
        else
            self.makeToken(.bang, start, .{ .none = {} }),

        // ═══ Shift: < / <= / << / <<= , > / >= / >> / >>= ═══
        '<' => blk: {
            if (self.match('<')) {
                if (self.match('=')) break :blk self.makeToken(.shl_eq, start, .{ .none = {} });
                break :blk self.makeToken(.shl, start, .{ .none = {} });
            }
            if (self.match('=')) break :blk self.makeToken(.less_eq, start, .{ .none = {} });
            break :blk self.makeToken(.less, start, .{ .none = {} });
        },
        '>' => blk: {
            if (self.match('>')) {
                if (self.match('=')) break :blk self.makeToken(.shr_eq, start, .{ .none = {} });
                break :blk self.makeToken(.shr, start, .{ .none = {} });
            }
            if (self.match('=')) break :blk self.makeToken(.greater_eq, start, .{ .none = {} });
            break :blk self.makeToken(.greater, start, .{ .none = {} });
        },

        // ═══ String and char literals ═══
        '"' => self.scanString(start),
        '\'' => self.scanChar(start),

        // ═══ Builtin identifier: @name ═══
        // A bare '@' not followed by alpha is an error-recovery token.
        // In valid Z98, '@' always precedes a builtin name like @sizeOf.
        '@' => blk: {
            if (isAlpha(self.peek())) {
                break :blk self.scanBuiltinIdentifier(start);
            }
            try self.diag.diagnostics.append(.{
                .level = 0,
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "bare '@' is not valid; expected builtin name (e.g., @sizeOf)",
            });
            break :blk self.makeErrorToken(start);
        },

        // ═══ Identifiers, keywords, and numbers ═══
        else => blk: {
            if (isAlpha(c) or c == '_') {
                break :blk self.scanIdentifierOrKeyword(start);
            }
            if (isDigit(c)) {
                break :blk self.scanNumber(start, c);
            }
            // Unrecognized character
            try self.diag.diagnostics.append(.{
                .level = 0,
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "unrecognized character",
            });
            break :blk self.makeErrorToken(start);
        },
    };
}
```

### 5.2 Number Scanning

```zig
fn scanNumber(self: *Lexer, start: usize, first: u8) Token {
    var is_float = false;
    var base: u8 = 10;

    // Handle prefixes: 0x, 0b, 0o
    if (first == '0' and !self.isAtEnd()) {
        const next = self.peek();
        if (next == 'x' or next == 'X') {
            base = 16; _ = self.advance();
        } else if (next == 'b' or next == 'B') {
            base = 2; _ = self.advance();
        } else if (next == 'o' or next == 'O') {
            base = 8; _ = self.advance();
        }
    }

    // Scan digit body (integer or pre-decimal part)
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (c == '_') { _ = self.advance(); continue; } // underscore separator
        if (!isDigitInBase(c, base)) break;
        _ = self.advance();
    }

    // Check for float: decimal point followed by non-dot (avoid conflict with .. and ...)
    if (base == 10 and self.peek() == '.' and self.peekN(1) != '.') {
        _ = self.advance(); // consume '.'
        is_float = true;
        while (!self.isAtEnd()) {
            const c = self.peek();
            if (c == '_') { _ = self.advance(); continue; }
            if (!isDigit(c)) break;
            _ = self.advance();
        }
    }

    // Check for exponent: e/E (decimal floats only)
    if (base == 10 and (self.peek() == 'e' or self.peek() == 'E')) {
        _ = self.advance();
        if (self.peek() == '+' or self.peek() == '-') { _ = self.advance(); }
        while (!self.isAtEnd() and isDigit(self.peek())) {
            _ = self.advance();
        }
        is_float = true;
    }

    const text = self.source[start..self.pos];

    if (is_float) {
        const value = parseF64(text);
        return self.makeToken(.float_literal, start, .{ .float_val = value });
    } else {
        const value = parseU64(text, base);
        return self.makeToken(.integer_literal, start, .{ .int_val = value });
    }
}

fn isDigitInBase(c: u8, base: u8) bool {
    return switch (base) {
        2 => c >= '0' and c <= '1',
        8 => c >= '0' and c <= '7',
        10 => c >= '0' and c <= '9',
        16 => (c >= '0' and c <= '9') or
              (c >= 'a' and c <= 'f') or
              (c >= 'A' and c <= 'F'),
        else => false,
    };
}
```

**Critical: Float vs Range Disambiguation.**  
The lexer checks `self.peekN(1) != '.'` before consuming a decimal point to avoid misinterpreting `0..10` as `0.` (float) followed by `.10`. This is essential for `for` loop range syntax. Additionally, float detection is restricted to `base == 10` — hex/binary/octal literals cannot be floats.

#### 5.2.1 Integer Parsing (CRT-free)

```zig
/// Parse a u64 from text with the given base.
/// Handles: underscore separators, 0x/0b/0o prefixes.
/// On overflow, returns max u64 (caller should have already validated).
fn parseU64(text: []const u8, base: u8) u64 {
    var result: u64 = 0;
    var i: usize = 0;

    // Skip prefix: "0x", "0b", "0o"
    if (text.len > 2 and text[0] == '0') {
        const p = text[1];
        if (p == 'x' or p == 'X' or p == 'b' or p == 'B' or p == 'o' or p == 'O') {
            i = 2;
        }
    }

    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '_') continue; // skip separator

        const digit: u64 = switch (c) {
            '0'...'9' => @intCast(u64, c - '0'),
            'a'...'f' => @intCast(u64, c - 'a' + 10),
            'A'...'F' => @intCast(u64, c - 'A' + 10),
            else => break, // non-digit ends the number
        };

        if (digit >= @intCast(u64, base)) break; // digit out of range for base

        // Overflow check: if result * base + digit would overflow u64
        const max_before_mul = 0xFFFFFFFFFFFFFFFF / @intCast(u64, base);
        if (result > max_before_mul) return 0xFFFFFFFFFFFFFFFF; // saturate on overflow
        result = result * @intCast(u64, base);
        if (result > 0xFFFFFFFFFFFFFFFF - digit) return 0xFFFFFFFFFFFFFFFF;
        result += digit;
    }

    return result;
}
```

#### 5.2.2 Float Parsing (Minimal, CRT-free)

```zig
/// Parse a f64 from decimal text.
/// Handles: integer.fraction, exponent (e/E), sign on exponent.
/// Does NOT handle: hex floats, NaN, Inf, subnormals.
/// This is sufficient for Z98 programs; full IEEE 754 parsing is a post-self-hosting upgrade.
fn parseF64(text: []const u8) f64 {
    var result: f64 = 0.0;
    var i: usize = 0;
    var negative = false;

    // Optional sign (shouldn't appear in lexer output, but defensive)
    if (i < text.len and text[i] == '-') { negative = true; i += 1; }
    if (i < text.len and text[i] == '+') { i += 1; }

    // Integer part
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '_') continue;
        if (c == '.' or c == 'e' or c == 'E') break;
        if (!isDigit(c)) break;
        result = result * 10.0 + @intToFloat(f64, @intCast(i32, c - '0'));
    }

    // Fractional part
    if (i < text.len and text[i] == '.') {
        i += 1;
        var frac_mul: f64 = 0.1;
        while (i < text.len) : (i += 1) {
            const c = text[i];
            if (c == '_') continue;
            if (c == 'e' or c == 'E') break;
            if (!isDigit(c)) break;
            result += @intToFloat(f64, @intCast(i32, c - '0')) * frac_mul;
            frac_mul *= 0.1;
        }
    }

    // Exponent
    if (i < text.len and (text[i] == 'e' or text[i] == 'E')) {
        i += 1;
        var exp_neg = false;
        if (i < text.len and text[i] == '-') { exp_neg = true; i += 1; }
        if (i < text.len and text[i] == '+') { i += 1; }

        var exp: i32 = 0;
        while (i < text.len and isDigit(text[i])) : (i += 1) {
            exp = exp * 10 + @intCast(i32, text[i] - '0');
        }

        // Apply exponent via repeated multiply/divide
        // (Sufficient precision for Z98 use cases; not bit-exact for edge cases)
        var power: f64 = 1.0;
        var e: i32 = 0;
        while (e < exp) : (e += 1) {
            power *= 10.0;
        }
        if (exp_neg) {
            result /= power;
        } else {
            result *= power;
        }
    }

    if (negative) result = -result;
    return result;
}
```

**Note:** This float parser is sufficient for all reference programs (mandelbrot.zig uses `3.5`, `2.0`, `-2.5`, `-1.0`, and `4.0`). Full IEEE 754 round-trip accuracy can be achieved post-self-hosting by implementing Eisel-Lemire or similar algorithm.

### 5.3 String Literal Scanning

```zig
fn scanString(self: *Lexer, start: usize) Token {
    // Reuse shared scratch buffer — clear but don't reallocate
    self.string_buf.items.len = 0;

    while (!self.isAtEnd()) {
        const c = self.peek();
        if (c == '"') {
            _ = self.advance(); // consume closing quote
            break;
        }
        if (c == '\n' or c == 0) {
            try self.diag.diagnostics.append(.{
                .level = 0,
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "unterminated string literal",
            });
            break;
        }
        _ = self.advance(); // consume the character
        if (c == '\\') {
            const escaped = self.parseEscapeSequence();
            try self.string_buf.append(escaped);
        } else {
            try self.string_buf.append(c);
        }
    }

    const string_id = self.interner.intern(self.string_buf.items);
    return self.makeToken(.string_literal, start, .{ .string_id = string_id });
}

fn parseEscapeSequence(self: *Lexer) u8 {
    if (self.isAtEnd()) return '\\'; // defensive: return literal backslash
    const c = self.advance();
    return switch (c) {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        '\\' => '\\',
        '"' => '"',
        '\'' => '\'',
        '0' => 0,
        'x' => self.parseHexEscape(),
        else => blk: {
            // Unrecognized escape: report diagnostic, return the character as-is
            try self.diag.diagnostics.append(.{
                .level = 1, // warning
                .file_id = self.file_id,
                .span_start = @intCast(u32, self.pos - 2),
                .span_end = @intCast(u32, self.pos),
                .message = "unrecognized escape sequence",
            });
            break :blk c;
        },
    };
}

fn parseHexEscape(self: *Lexer) u8 {
    var value: u8 = 0;
    var count: u8 = 0;
    while (count < 2 and !self.isAtEnd()) : (count += 1) {
        const c = self.peek();
        const digit = hexDigitValue(c);
        if (digit == 0xFF) break; // not a hex digit — stop
        value = value * 16 + digit;
        _ = self.advance();
    }
    if (count == 0) {
        try self.diag.diagnostics.append(.{
            .level = 0,
            .file_id = self.file_id,
            .span_start = @intCast(u32, self.pos - 2),
            .span_end = @intCast(u32, self.pos),
            .message = "\\x requires at least one hex digit",
        });
    }
    return value;
}

fn hexDigitValue(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return 0xFF; // sentinel: not a hex digit
}
```

**Note on unicode escapes:** Z98 targets ASCII-only C89. The `\u{XXXX}` escape syntax is not supported. If encountered, the unrecognized-escape path will produce a warning and pass through the character. Full unicode escape support can be added post-self-hosting.

### 5.4 Character Literal Scanning

```zig
fn scanChar(self: *Lexer, start: usize) Token {
    if (self.isAtEnd() or self.peek() == '\'') {
        try self.diag.diagnostics.append(.{
            .level = 0,
            .file_id = self.file_id,
            .span_start = @intCast(u32, start),
            .span_end = @intCast(u32, self.pos),
            .message = "empty character literal",
        });
        if (self.peek() == '\'') { _ = self.advance(); } // consume closing '
        return self.makeToken(.char_literal, start, .{ .int_val = 0 });
    }

    var value: u32 = 0;
    const c = self.advance();
    if (c == '\\') {
        value = @intCast(u32, self.parseEscapeSequence());
    } else {
        value = @intCast(u32, c);
    }

    // Expect closing quote
    if (self.peek() != '\'') {
        try self.diag.diagnostics.append(.{
            .level = 0,
            .file_id = self.file_id,
            .span_start = @intCast(u32, start),
            .span_end = @intCast(u32, self.pos),
            .message = "expected closing ' in character literal",
        });
    } else {
        _ = self.advance(); // consume closing '
    }

    return self.makeToken(.char_literal, start, .{ .int_val = @intCast(u64, value) });
}
```

### 5.5 Identifier and Keyword Scanning

```zig
fn scanIdentifierOrKeyword(self: *Lexer, start: usize) Token {
    // First character already consumed by caller's advance()
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (!isAlpha(c) and !isDigit(c) and c != '_') break;
        _ = self.advance();
    }

    const text = self.source[start..self.pos];

    // Check for bare discard pattern: exactly "_"
    if (text.len == 1 and text[0] == '_') {
        return self.makeToken(.underscore, start, .{ .none = {} });
    }

    // Check keyword table
    if (lookupKeyword(text)) |kind| {
        return self.makeToken(kind, start, .{ .none = {} });
    }

    // Regular identifier — intern the text
    const string_id = self.interner.intern(text);
    return self.makeToken(.identifier, start, .{ .string_id = string_id });
}
```

**Bare underscore handling:** `_` as a single character produces `.underscore` (discard pattern). `_foo`, `__internal`, or any multi-character identifier starting with `_` produces `.identifier`. This distinction is required for `for (arr) |_|` and `for (arr) |_, idx|` patterns.

### 5.6 Builtin Identifier Scanning

```zig
fn scanBuiltinIdentifier(self: *Lexer, start: usize) Token {
    // '@' already consumed by caller; scan the name part
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (!isAlpha(c) and !isDigit(c) and c != '_') break;
        _ = self.advance();
    }

    // Intern the full text including '@'
    const text = self.source[start..self.pos];
    const string_id = self.interner.intern(text);

    return self.makeToken(.builtin_identifier, start, .{ .string_id = string_id });
}
```

---

## 6. Utility Function: `mem_eql`

Slice equality comparison used by the keyword lookup and throughout the compiler. This is a fundamental utility that lives in `util.zig`:

```zig
/// Compare two byte slices for equality.
/// Used by keyword lookup, string interner, and all name comparisons.
pub fn mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}
```

This function does NOT depend on the PAL — it operates purely on Z98 slices. It is the Z98 equivalent of the bootstrap's `strcmp` but works on length-delimited slices rather than null-terminated C strings.

---

## 7. String Interning Integration

All identifier and string literal content is interned into a global `StringInterner` allocated from the `permanent` arena.

```zig
pub const StringInterner = struct {
    buckets: []u32,                    // hash → index into entries (0 = empty)
    entries: ArrayList(InternEntry),
    allocator: *Allocator,

    pub const InternEntry = struct {
        text: []const u8,              // owned by arena
        hash: u32,
        next: u32,                     // chaining index (0 = end)
    };

    pub fn init(alloc: *Allocator, bucket_count: u32) !StringInterner {
        var buckets = try alloc.alloc(u32, bucket_count);
        // Zero-fill: 0 = empty slot
        var i: usize = 0;
        while (i < buckets.len) : (i += 1) { buckets[i] = 0; }

        var self = StringInterner{
            .buckets = buckets,
            .entries = ArrayList(InternEntry).init(alloc),
            .allocator = alloc,
        };

        // Reserve index 0 as null sentinel.
        // Code that checks `name_id == 0` means "no name".
        try self.entries.append(.{ .text = "", .hash = 0, .next = 0 });

        return self;
    }

    pub fn intern(self: *StringInterner, text: []const u8) u32 {
        const hash = fnv1a(text);
        const bucket = hash % @intCast(u32, self.buckets.len);
        var idx = self.buckets[bucket];

        // Search existing entries
        while (idx != 0) {
            const entry = self.entries.items[idx];
            if (entry.hash == hash and mem_eql(entry.text, text)) {
                return idx;
            }
            idx = entry.next;
        }

        // Not found: insert new entry
        const new_idx = @intCast(u32, self.entries.items.len);
        // Copy text into permanent arena
        var copied = self.allocator.alloc(u8, text.len) catch unreachable;
        var j: usize = 0;
        while (j < text.len) : (j += 1) { copied[j] = text[j]; }

        self.entries.append(.{
            .text = copied,
            .hash = hash,
            .next = self.buckets[bucket],
        }) catch unreachable;
        self.buckets[bucket] = new_idx;
        return new_idx;
    }

    pub fn get(self: *StringInterner, id: u32) []const u8 {
        return self.entries.items[id].text;
    }

    fn fnv1a(data: []const u8) u32 {
        var h: u32 = 2166136261;
        var i: usize = 0;
        while (i < data.len) : (i += 1) {
            h ^= @intCast(u32, data[i]);
            h *%= 16777619;
        }
        return h;
    }
};
```

**Index 0 sentinel:** Entry 0 is reserved (empty string, hash 0). All real interned strings start at index 1. This allows `name_id == 0` to mean "no name" throughout the compiler — consistent with `AstNode.child_N == 0` meaning "no child".

**Z98 Constraint:** The `StringInterner` must be declared as `pub var` and initialized via `init` at startup, not as a global constant.

---

## 8. Error Handling and Recovery

### 8.1 Diagnostic Integration

The lexer reports errors via `DiagnosticCollector.diagnostics.append(...)` and never aborts. This allows the parser to attempt recovery and collect multiple errors in a single compilation.

Error tokens (`.err_token`) are produced for:
- Unrecognized characters.
- Bare `@` without a following identifier.

Warning-level diagnostics are produced for:
- Unrecognized escape sequences in strings (the character is passed through).

Error-level diagnostics are produced for:
- Unterminated string/character literals.
- Invalid hex escape sequences.
- Unterminated block comments.
- Integer literal overflow (value is saturated to `0xFFFFFFFFFFFFFFFF`).

### 8.2 Recovery Guarantees

The lexer guarantees:
1. **Every call to `nextToken` returns a valid `Token`** — even on error.
2. **The lexer always makes progress** — at least one byte is consumed per `nextToken` call (unless at EOF).
3. **No abort, no panic, no recursion** — errors produce diagnostics and tokens, not crashes.
4. **The parser can always proceed** — `.err_token` is recognized by the parser, which emits `AstKind.err` and synchronizes.

---

## 9. Memory Budget Analysis

For a 2000-line Z98 source file (typical compiler module), estimated lexer memory usage:

| Component | Per-item | Estimated count | Total |
|---|---|---|---|
| `Token` | 16 bytes | ~8,000 tokens | 128 KB |
| `StringInterner.buckets` | 4 bytes | 4,096 entries | 16 KB |
| `StringInterner.entries` | 16 bytes | ~2,000 entries | 32 KB |
| `StringInterner` text storage | variable | ~50 KB source text | 50 KB |
| `string_buf` scratch | variable | peak ~4 KB | 4 KB |
| **Total** | | | **~230 KB** |

For the entire self-hosted compiler (~14,600 lines across ~17 modules), peak lexer memory is approximately **1.6 MB**. The interned strings persist in the `permanent` arena; tokens are in the `module` arena and reset after parsing.

**Token Arena Reset:** After each module's AST is built, the token `ArrayList` memory is freed (module arena reset). Only interned strings survive in the permanent arena.

---

## 10. Testing Strategy

### 10.1 Unit Tests (Layer 1)

| Test | Input | Verified Property |
|---|---|---|
| `test_integer_decimal` | `"42"` | `.integer_literal`, value=42 |
| `test_integer_hex` | `"0xFF"` | `.integer_literal`, value=255 |
| `test_integer_binary` | `"0b1010"` | `.integer_literal`, value=10 |
| `test_integer_octal` | `"0o77"` | `.integer_literal`, value=63 |
| `test_integer_underscore` | `"1_000_000"` | `.integer_literal`, value=1000000 |
| `test_integer_zero` | `"0"` | `.integer_literal`, value=0 |
| `test_integer_max_u64` | `"18446744073709551615"` | `.integer_literal`, value=max u64 |
| `test_integer_overflow` | `"99999999999999999999"` | `.integer_literal`, value=max u64, diagnostic |
| `test_float_basic` | `"3.14"` | `.float_literal`, value≈3.14 |
| `test_float_scientific` | `"1.0e-5"` | `.float_literal` |
| `test_float_no_frac` | `"2.0"` | `.float_literal`, value=2.0 |
| `test_float_range_disambig` | `"0..10"` | `.integer_literal(0)`, `.dot_dot`, `.integer_literal(10)` |
| `test_string_basic` | `"\"hello\""` | `.string_literal`, content="hello" |
| `test_string_escape_n` | `"\"a\\nb\""` | `.string_literal`, contains newline |
| `test_string_escape_hex` | `"\"\\xFF\""` | `.string_literal`, byte 0xFF |
| `test_string_unterminated` | `"\"hello"` | `.string_literal` + error diagnostic |
| `test_char_basic` | `"'a'"` | `.char_literal`, value=97 |
| `test_char_escape` | `"'\\n'"` | `.char_literal`, value=10 |
| `test_char_hex` | `"'\\x41'"` | `.char_literal`, value=65 ('A') |
| `test_char_empty` | `"''"` | `.char_literal` + error diagnostic |
| `test_dot_variants` | `". .. ... .{ .*"` | Correct token kinds for each |
| `test_shift_ops` | `"<< >> <<= >>="` | `.shl`, `.shr`, `.shl_eq`, `.shr_eq` |
| `test_fat_arrow` | `"=>"` | `.fat_arrow` |
| `test_eq_variants` | `"= == =>"` | `.eq`, `.eq_eq`, `.fat_arrow` |
| `test_all_keywords` | one per keyword | Correct `.kw_*` kind for each of 35 keywords |
| `test_builtin_ident` | `"@sizeOf"` | `.builtin_identifier`, text="@sizeOf" |
| `test_builtin_import` | `"@import"` | `.builtin_identifier`, text="@import" |
| `test_bare_at` | `"@+"` | `.err_token` + diagnostic |
| `test_bare_underscore` | `"_"` | `.underscore` (not `.identifier`) |
| `test_underscore_ident` | `"_foo"` | `.identifier`, text="_foo" |
| `test_line_comment` | `"42 // comment\n43"` | Two `.integer_literal` tokens |
| `test_block_comment` | `"42 /* inner */ 43"` | Two `.integer_literal` tokens |
| `test_nested_comment` | `"42 /* a /* b */ c */ 43"` | Two `.integer_literal` tokens |
| `test_unterminated_comment` | `"42 /* no close"` | `.integer_literal` + error diagnostic |
| `test_unrecognized` | `"42 $ 43"` | `.integer_literal`, `.err_token`, `.integer_literal` |
| `test_eof` | `""` | `.eof` |
| `test_whitespace_only` | `"   \t\n  "` | `.eof` |

### 10.2 Differential Testing (Layer 2)

Both `zig0` and `zig1` support `--dump-tokens`:

```bash
#!/bin/sh
# token_diff_test.sh <source.zig>
SOURCE=$1
./zig0 --dump-tokens "$SOURCE" > /tmp/tok_zig0.txt
./zig1 --dump-tokens "$SOURCE" > /tmp/tok_zig1.txt
diff /tmp/tok_zig0.txt /tmp/tok_zig1.txt
if [ $? -ne 0 ]; then
    echo "FAIL: Token mismatch for $SOURCE"
    exit 1
fi
echo "PASS: Tokens match for $SOURCE"
```

**Canonical token dump format:**
```
integer_literal 0 2 42
identifier 3 3 "foo"
kw_if 7 2
dot_dot 10 2
eof 12 0
```

Format: `kind span_start span_len [value]`. Keywords have no value field. Identifiers and strings show the interned text in quotes. Integers show the decimal value. Floats show the decimal value.

### 10.3 Integration Tests (Layers 3–4)

Run the lexer as part of the full pipeline against reference programs:
- `mandelbrot.zig`: Float literals (`3.5`, `2.0`, `1.0e-5`), hex constants, extern functions.
- `game_of_life.zig`: Tagged union initializers (`.Alive`, `.Dead`), `@intCast`, `extern "c"`.
- `eval.zig`: Deeply nested switches, error literals, `try`/`catch`/`orelse`, builtin calls.
- `mud.zig`: String literals with `\r\n`, multiple `@intCast`, struct initializers.
- `zig1` source itself: All language features used by the compiler.

Verify:
1. Token stream matches `zig0` output (differential).
2. Generated C89 compiles and runs correctly.
3. Peak memory stays under 16 MB.
4. Deterministic: two runs produce identical `--dump-tokens` output.

---

## 11. Z98-Specific Implementation Constraints

| Limitation | Workaround | Notes |
|---|---|---|
| No global aggregate constants | `pub var` + `initKeywordTable()` at startup | Used for keyword table |
| No `@enumToInt`/`@intToEnum` | Manual helpers or direct cast | Used in `makeToken`, `parseU64` |
| Strict `i32` ↔ `usize` coercion | `@intCast` everywhere | Common in lexer arithmetic |
| No pointer captures | Unwrap optional before use | Pattern: `if (opt != null) { ... }` |
| Arena allocation only | All buffers use `Allocator` interface | No `new`/`delete` |
| Deterministic output required | Seeded FNV-1a hash, stable iteration | For `--dump-tokens` diff |
| No `try` in non-error-returning functions | Check `diag.diagnostics.append` return or use `catch unreachable` | Lexer functions that report diagnostics |

---

## 12. Extensibility Hooks

| Feature | Extension Point | What Changes |
|---|---|---|
| New keywords | Add to `TokenKind` enum + `initKeywordTable` | Lexer + 1 enum value + 1 table entry |
| New operators | Add to `TokenKind` + add case in `nextToken` switch | Lexer dispatch logic |
| New literal syntax | Add scanning function + token kind | New `scanXyz` method |
| Unicode identifiers | Modify `isAlpha`/`isDigit` to handle UTF-8 | Character classification only |
| Raw string literals | Add `r"..."` recognition in `nextToken` | New case before `'"'` |
| Multi-line strings | Add `\\` (line continuation) support | String scanning logic |
| Perfect hash keywords | Replace linear scan with computed hash table | `lookupKeyword` only |

**Post-self-hosting priority:** Replace linear keyword scan with perfect hash (O(1) lookup). At 35 keywords, the linear scan takes ~17 comparisons on average — fast enough for bootstrap, but a perfect hash eliminates branch mispredictions.

---

## Appendix A: Token Kind Count and Mapping

**Total: 88 token kinds** in `u16`.

Breakdown:
- Literals: 4 (integer, float, string, char)
- Identifiers: 2 (identifier, builtin\_identifier)
- Delimiters/punctuation: 13 (parens, brackets, braces, semicolon, colon, comma, dot, underscore, question, bang)
- Arithmetic operators: 5 (+, -, *, /, %)
- Bitwise operators: 4 (&, |, ^, ~)
- Shift operators: 2 (<<, >>)
- Comparison operators: 6 (==, !=, <, <=, >, >=)
- Assignment operators: 11 (=, +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=)
- Dot/range: 4 (.., ..., .{, .*)
- Fat arrow: 1 (=>)
- Keywords: 35 (declarations, types, control flow, error handling, boolean, special values, type names)
- Special: 2 (eof, err\_token)
- **Sum: 4+2+13+5+4+2+6+11+4+1+35+2 = 89**

**Correction from v1.0:** The actual count is 89, not 88. The `underscore` token was miscounted in the original tally. The `u16` enum has ample room regardless.

**New kinds not in bootstrap:**
- `dot_lbrace`, `dot_star` — explicit tokens for `.{` and `.*` (bootstrap handled via context in parser)
- `builtin_identifier` — separate from `identifier` for faster parser dispatch
- `err_token` — explicit error recovery token
- `underscore` — separate from `identifier` for discard pattern recognition

**Removed from bootstrap:**
- `TOKEN_RANGE` — replaced by `dot_dot`/`dot_dot_dot` distinction (range type encoded in token)
- `TOKEN_DOT_ASTERISK` — renamed to `dot_star`
