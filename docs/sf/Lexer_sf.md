# Self-Hosted Lexer Design Specification
**Version:** 1.0  
**Component:** `zig1` lexer, token stream, and source scanning  
**Parent Document:** DESIGN.md v3.0, AST_PARSER_p2.md  
**Supersedes:** Bootstrap lexer.cpp (C++ implementation)

---

## Disclaimer
Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation.

---

## 1. Scope and Relationship to Bootstrap

This document specifies the lexer for the self-hosted Z98 compiler (`zig1`). It replaces the bootstrap's C++ lexer with a Z98-native implementation optimized for cache locality, deterministic output, and strict memory budgeting.

| Bootstrap (`zig0`) | Self-Hosted (`zig1`) | Why |
|---|---|---|
| `Token` with `union { int_val, float_val, string_ptr }` (24+ bytes, pointer) | `Token` with `union { int_val: u64, float_val: f64, string_id: u32 }` (16 bytes, index) | No pointer chasing; string content via `StringInterner` index |
| `std::string` for literal storage | `StringInterner` with FNV-1a hash, open addressing | Arena-backed, deduplicated, deterministic |
| Recursive `skipComments()` with depth limit | Iterative `skipWhitespaceAndComments()` with state machine | No recursion; handles nested `/* */` safely |
| Linear keyword table scan (35 entries) | Same, but stored in `pub var` initialized at startup | Z98 constraint: no global aggregate constants |
| `Token` allocated per-token in arena | `Token` stored in flat `ArrayList(Token)` per module | Cache-friendly; reset after parsing completes |
| C++98 with `ArenaAllocator` | Z98 with `std.heap.ArenaAllocator` | Self-hosting |

---

## 2. Token: The Core Structure

### 2.1 Layout

```zig
pub const Token = struct {
    kind: TokenKind,      // u16 enum — 88+ possible values
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

### 2.2 Span Encoding

- `span_start`: Absolute byte offset from the start of the source file.
- `span_len`: Number of bytes the token occupies.
- `span_end = span_start + span_len` (computed on demand).

This encoding supports:
- Precise diagnostic reporting (caret under exact token).
- Differential AST comparison (spans must match `zig0` output).
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
    identifier,           // foo, bar_baz, _underscore, i32, usize
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
    at_sign,              // @ (used before builtin names)
    underscore,           // _ (discard pattern)
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
pub var keyword_table: []const KeywordEntry = undefined;

pub const KeywordEntry = struct {
    name: []const u8,
    kind: TokenKind,
};

pub fn initKeywordTable(alloc: *Allocator) !void {
    keyword_table = try alloc.alloc(KeywordEntry, 35);
    var i: usize = 0;
    keyword_table[i] = .{ .name = "const", .kind = .kw_const }; i += 1;
    keyword_table[i] = .{ .name = "var", .kind = .kw_var }; i += 1;
    // ... all 35 entries ...
    keyword_table[i] = .{ .name = "c_char", .kind = .kw_c_char }; i += 1;
}

pub fn lookupKeyword(text: []const u8) ?TokenKind {
    // Linear scan: 35 entries is fast; perfect hash deferred to post-self-hosting
    for (keyword_table) |entry| {
        if (mem_eql(entry.name, text)) return entry.kind;
    }
    return null;
}
```

**Extensibility:** New keywords are added to both the `TokenKind` enum and the `keyword_table` initialization. No other lexer changes required.

---

## 4. Lexer: Core Implementation

### 4.1 Structure

```zig
pub const Lexer = struct {
    source: []const u8,     // entire source file content
    pos: usize,             // current byte offset
    line: u32,              // current line number (1-based)
    col: u32,               // current column (1-based, for diagnostics)
    file_id: u32,           // SourceManager file ID
    interner: *StringInterner,
    diag: *DiagnosticCollector,
};
```

### 4.2 Helper Methods

```zig
pub fn init(source: []const u8, file_id: u32,
            interner: *StringInterner,
            diag: *DiagnosticCollector) Lexer {
    return .{
        .source = source,
        .pos = 0,
        .line = 1,
        .col = 1,
        .file_id = file_id,
        .interner = interner,
        .diag = diag,
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
    const c = self.peek();
    if (c == '\n') {
        self.line += 1;
        self.col = 1;
    } else if (c != 0) {
        self.col += 1;
    }
    self.pos += 1;
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
```

### 4.3 Whitespace and Comment Skipping

```zig
pub fn skipWhitespaceAndComments(self: *Lexer) void {
    while (!self.isAtEnd()) {
        const c = self.peek();
        return switch (c) {
            ' ', '\t', '\r' => { _ = self.advance(); },
            '\n' => { _ = self.advance(); },
            '/' => {
                if (self.peekN(1) == '/') {
                    // Single-line comment: skip to end of line
                    while (!self.isAtEnd() and self.peek() != '\n') {
                        _ = self.advance();
                    }
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
                            if (self.peek() == '\n') {
                                self.line += 1;
                                self.col = 1;
                            } else {
                                self.col += 1;
                            }
                            self.pos += 1;
                        }
                    }
                } else {
                    return; // not a comment
                }
            },
            else => return,
        };
    }
}
```

**Key decisions:**
- Nested `/* */` comments are supported (Zig-compatible).
- Line/column tracking is updated inside the skip loop for accurate diagnostics.
- No recursion: iterative state machine handles arbitrary nesting depth.

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
        // === Single-character tokens ===
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

        // === Dot variants: . / .. / ... / .{ / .* ===
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

        // === Operators with = variants ===
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

        // === Compound: & / &= , | / |= , = / == / => , ! / != ===
        '&' => if (self.match('='))
            self.makeToken(.ampersand_eq, start, .{ .none = {} })
        else
            self.makeToken(.ampersand, start, .{ .none = {} }),
        '|' => if (self.match('='))
            self.makeToken(.pipe_eq, start, .{ .none = {} })
        else
            self.makeToken(.pipe, start, .{ .none = {} }),
        '=' => {
            if (self.match('=')) {
                return self.makeToken(.eq_eq, start, .{ .none = {} });
            }
            if (self.match('>')) {
                return self.makeToken(.fat_arrow, start, .{ .none = {} });
            }
            return self.makeToken(.eq, start, .{ .none = {} });
        },
        '!' => if (self.match('='))
            self.makeToken(.bang_eq, start, .{ .none = {} })
        else
            self.makeToken(.bang, start, .{ .none = {} }),

        // === Shift: < / <= / << / <<= , > / >= / >> / >>= ===
        '<' => {
            if (self.match('<')) {
                if (self.match('=')) {
                    return self.makeToken(.shl_eq, start, .{ .none = {} });
                }
                return self.makeToken(.shl, start, .{ .none = {} });
            }
            if (self.match('=')) {
                return self.makeToken(.less_eq, start, .{ .none = {} });
            }
            return self.makeToken(.less, start, .{ .none = {} });
        },
        '>' => {
            if (self.match('>')) {
                if (self.match('=')) {
                    return self.makeToken(.shr_eq, start, .{ .none = {} });
                }
                return self.makeToken(.shr, start, .{ .none = {} });
            }
            if (self.match('=')) {
                return self.makeToken(.greater_eq, start, .{ .none = {} });
            }
            return self.makeToken(.greater, start, .{ .none = {} });
        },

        // === String and char literals ===
        '"' => self.scanString(start),
        '\'' => self.scanChar(start),

        // === Builtin identifier: @name ===
        '@' => {
            if (self.isAlpha(self.peek())) {
                return self.scanBuiltinIdentifier(start);
            }
            return self.makeToken(.at_sign, start, .{ .none = {} });
        },

        // === Identifiers and keywords ===
        else => {
            if (self.isAlpha(c) or c == '_') {
                return self.scanIdentifierOrKeyword(start, c);
            }
            if (self.isDigit(c)) {
                return self.scanNumber(start, c);
            }
            // Unrecognized character
            try self.diag.addDiagnostic(.{
                .level = 0, // error
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "unrecognized character",
            });
            return self.makeErrorToken(start);
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

    // Scan integer part
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (c == '_') { _ = self.advance(); continue; } // underscore separator
        if (!self.isDigitInBase(c, base)) break;
        _ = self.advance();
    }

    // Check for float: decimal point or exponent
    if (self.peek() == '.' and self.peekN(1) != '.') {
        // Avoid conflict with .. and ...
        _ = self.advance(); // consume '.'
        is_float = true;
        while (!self.isAtEnd()) {
            const c = self.peek();
            if (c == '_') { _ = self.advance(); continue; }
            if (!self.isDigit(c)) break;
            _ = self.advance();
        }
    }

    if (self.peek() == 'e' or self.peek() == 'E') {
        _ = self.advance();
        if (self.peek() == '+' or self.peek() == '-') { _ = self.advance(); }
        while (!self.isAtEnd() and self.isDigit(self.peek())) {
            _ = self.advance();
        }
        is_float = true;
    }

    const text = self.source[start..self.pos];

    if (is_float) {
        // Parse f64; on error, report and return 0.0
        const value = parseFloat(text) catch |err| {
            try self.diag.addDiagnostic(.{
                .level = 0,
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "invalid float literal",
            });
            return self.makeToken(.float_literal, start, .{ .float_val = 0.0 });
        };
        return self.makeToken(.float_literal, start, .{ .float_val = value });
    } else {
        // Parse u64; on overflow, report and clamp
        const value = parseInteger(text, base) catch |err| {
            try self.diag.addDiagnostic(.{
                .level = 0,
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "integer literal out of range",
            });
            return self.makeToken(.integer_literal, start, .{ .int_val = 0 });
        };
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

**Critical: Float vs Range Disambiguation**  
The lexer checks `self.peekN(1) != '.'` before consuming a decimal point to avoid misinterpreting `0..10` as `0.` (float) followed by `.10`. This is essential for `for` loop range syntax.

### 5.3 String Literal Scanning

```zig
fn scanString(self: *Lexer, start: usize) Token {
    var buf = ArrayList(u8).init(self.diag.allocator);
    defer buf.deinit();

    while (!self.isAtEnd()) {
        const c = self.advance();
        if (c == '"') break;
        if (c == '\n' or c == 0) {
            try self.diag.addDiagnostic(.{
                .level = 0,
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "unterminated string literal",
            });
            break;
        }
        if (c == '\\') {
            const escaped = self.parseEscapeSequence() catch |err| {
                try self.diag.addDiagnostic(.{
                    .level = 0,
                    .file_id = self.file_id,
                    .span_start = @intCast(u32, self.pos - 1),
                    .span_end = @intCast(u32, self.pos),
                    .message = "invalid escape sequence",
                });
                continue;
            };
            try buf.append(escaped);
        } else {
            try buf.append(c);
        }
    }

    // Null-terminate for C89 compatibility (not stored, but useful for interop)
    const content = buf.items;
    const string_id = self.interner.intern(content);

    return self.makeToken(.string_literal, start, .{ .string_id = string_id });
}

fn parseEscapeSequence(self: *Lexer) !u8 {
    if (self.isAtEnd()) return error.UnexpectedEOF;
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
        'u' => self.parseUnicodeEscape(), // Z98: only ASCII; reject >0x7F
        else => c, // unrecognized: pass through (Zig-compatible)
    };
}

fn parseHexEscape(self: *Lexer) !u8 {
    var value: u8 = 0;
    var count: u8 = 0;
    while (count < 2 and !self.isAtEnd()) {
        const c = self.peek();
        const digit = hexDigitValue(c) catch break;
        value = value * 16 + digit;
        _ = self.advance();
        count += 1;
    }
    if (count == 0) return error.InvalidHexEscape;
    return value;
}

fn hexDigitValue(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => error.InvalidHexDigit,
    };
}
```

### 5.4 Character Literal Scanning

```zig
fn scanChar(self: *Lexer, start: usize) Token {
    if (self.isAtEnd()) {
        try self.diag.addDiagnostic(.{
            .level = 0,
            .file_id = self.file_id,
            .span_start = @intCast(u32, start),
            .span_end = @intCast(u32, self.pos),
            .message = "unterminated character literal",
        });
        return self.makeToken(.char_literal, start, .{ .int_val = 0 });
    }

    var value: u32 = 0;
    if (self.peek() == '\\') {
        _ = self.advance();
        value = self.parseEscapeSequence() catch |err| {
            try self.diag.addDiagnostic(.{
                .level = 0,
                .file_id = self.file_id,
                .span_start = @intCast(u32, start),
                .span_end = @intCast(u32, self.pos),
                .message = "invalid escape in char literal",
            });
            0
        };
    } else {
        value = self.advance();
    }

    // Expect closing quote
    if (self.peek() != '\'') {
        try self.diag.addDiagnostic(.{
            .level = 0,
            .file_id = self.file_id,
            .span_start = @intCast(u32, start),
            .span_end = @intCast(u32, self.pos),
            .message = "expected closing ' in char literal",
        });
    } else {
        _ = self.advance();
    }

    return self.makeToken(.char_literal, start, .{ .int_val = @intCast(u64, value) });
}
```

### 5.5 Identifier and Keyword Scanning

```zig
fn scanIdentifierOrKeyword(self: *Lexer, start: usize, first: u8) Token {
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (!self.isAlpha(c) and !self.isDigit(c) and c != '_') break;
        _ = self.advance();
    }

    const text = self.source[start..self.pos];
    const string_id = self.interner.intern(text);

    // Check if it's a keyword
    if (lookupKeyword(text)) |kind| {
        return self.makeToken(kind, start, .{ .none = {} });
    }

    return self.makeToken(.identifier, start, .{ .string_id = string_id });
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
```

### 5.6 Builtin Identifier Scanning

```zig
fn scanBuiltinIdentifier(self: *Lexer, start: usize) Token {
    // '@' already consumed; scan the name
    while (!self.isAtEnd()) {
        const c = self.peek();
        if (!self.isAlpha(c) and !self.isDigit(c) and c != '_') break;
        _ = self.advance();
    }

    const text = self.source[start..self.pos]; // includes '@'
    const string_id = self.interner.intern(text);

    return self.makeToken(.builtin_identifier, start, .{ .string_id = string_id });
}
```

---

## 6. String Interning Integration

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

    pub fn init(alloc: *Allocator, initial_capacity: u32) !StringInterner {
        var buckets = try alloc.alloc(u32, initial_capacity);
        @memset(buckets, 0); // 0 = empty slot
        return .{
            .buckets = buckets,
            .entries = ArrayList(InternEntry).init(alloc),
            .allocator = alloc,
        };
    }

    pub fn intern(self: *StringInterner, text: []const u8) !u32 {
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
        const copied_text = try self.allocator.dupe(u8, text); // arena-backed
        try self.entries.append(.{
            .text = copied_text,
            .hash = hash,
            .next = self.buckets[bucket],
        });
        self.buckets[bucket] = new_idx;
        return new_idx;
    }

    pub fn get(self: *StringInterner, id: u32) []const u8 {
        return self.entries.items[id].text;
    }

    fn fnv1a(data: []const u8) u32 {
        var h: u32 = 2166136261;
        var i: usize = 0;
        while (i < data.len) {
            h ^= @intCast(u32, data[i]);
            h *%= 16777619;
            i += 1;
        }
        return h;
    }
};
```

**Z98 Constraint:** The `StringInterner` must be declared as `pub var` and initialized via an `init` function at startup, not as a global constant.

---

## 7. Error Handling and Recovery

### 7.1 Diagnostic Integration

The lexer reports errors via the `DiagnosticCollector` but never aborts. This allows the parser to attempt recovery and collect multiple errors.

```zig
// In nextToken, unrecognized character:
try self.diag.addDiagnostic(.{
    .level = 0, // error
    .file_id = self.file_id,
    .span_start = @intCast(u32, start),
    .span_end = @intCast(u32, self.pos),
    .message = "unrecognized character",
});
return self.makeErrorToken(start);
```

### 7.2 Error Token

```zig
fn makeErrorToken(self: *Lexer, start: usize) Token {
    return .{
        .kind = .err_token,
        .span_start = @intCast(u32, start),
        .span_len = 1,
        .value = .{ .none = {} },
    };
}
```

The parser recognizes `.err_token` and emits an `AstKind.err` node, allowing continued traversal.

### 7.3 Recovery Points

The lexer itself has minimal recovery logic; recovery is primarily the parser's responsibility. However, the lexer ensures:
- Unterminated strings/chars produce a diagnostic and a token (not a crash).
- Invalid escape sequences are reported but scanning continues.
- Numeric overflow is clamped with a diagnostic.

---

## 8. Memory Budget Analysis

For a 2000-line Z98 source file (typical compiler module), estimated lexer memory usage:

| Component | Per-item | Estimated count | Total |
|---|---|---|---|
| `Token` | 16 bytes | ~8000 tokens | 128 KB |
| `StringInterner.buckets` | 4 bytes | 4096 entries | 16 KB |
| `StringInterner.entries` | 16 bytes | ~2000 entries | 32 KB |
| `StringInterner` text storage | variable | ~50 KB source text | 50 KB |
| Temporary `ArrayList` buffers | variable | peak ~4 KB | 4 KB |
| **Total** | | | **~230 KB** |

For the entire self-hosted compiler (~14,600 lines across ~17 modules), peak lexer memory is approximately **1.6 MB** — well within the 16 MB budget.

**Token Arena Reset:** After each module's AST is built, the `module` arena (holding tokens and AST nodes) is reset. Only interned strings persist in the `permanent` arena.

---

## 9. Extensibility Hooks

| Feature | Extension Point | What Changes |
|---|---|---|
| New keywords | Add to `TokenKind` enum + `keyword_table` init | Lexer + 1 enum value |
| New operators | Add to `TokenKind` + update `nextToken` switch | Lexer dispatch logic |
| New literal syntax | Add case in `parsePrimary` (parser) + lexer support | Lexer + parser |
| Unicode identifiers | Modify `isAlpha`/`isDigit` to handle UTF-8 | Lexer character classification |
| Raw string literals | Add `r"..."` case in `scanString` | Lexer string scanning |
| Custom diagnostics | Extend `Diagnostic` struct + collector | Lexer error reporting |

**Post-self-hosting:** When `comptime` is available, the keyword table can be generated at compile-time, and perfect hashing can replace linear scan for O(1) lookup.

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
| `test_float_basic` | `"3.14"` | `.float_literal`, value≈3.14 |
| `test_float_scientific` | `"1.0e-5"` | `.float_literal` |
| `test_float_range_disambig` | `"0..10"` | `.integer_literal(0)`, `.dot_dot`, `.integer_literal(10)` |
| `test_string_basic` | `"\"hello\""` | `.string_literal`, content="hello" |
| `test_string_escape` | `"\"a\\nb\""` | `.string_literal`, contains newline |
| `test_char_basic` | `"'a'"` | `.char_literal`, value=97 |
| `test_char_escape` | `"'\\n'"` | `.char_literal`, value=10 |
| `test_dot_variants` | `". .. ... .{ .*"` | Correct token kinds for each |
| `test_shift_ops` | `"<< >> <<= >>="` | `.shl`, `.shr`, `.shl_eq`, `.shr_eq` |
| `test_fat_arrow` | `"=>"` | `.fat_arrow` |
| `test_all_keywords` | one token per keyword | Correct `.kw_*` kind for each |
| `test_builtin_ident` | `"@sizeOf"` | `.builtin_identifier` |
| `test_line_comment` | `"42 // comment\n43"` | Two integer tokens, comment skipped |
| `test_block_comment_nested` | `"42 /* nested /* inner */ outer */ 43"` | Two integer tokens, nested comments handled |
| `test_unrecognized` | `"42 $ 43"` | `.integer_literal`, `.err_token`, `.integer_literal` |

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

**Canonical token format:**
```
kind span_start span_len [value]
integer_literal 0 2 42
identifier 3 3 "foo"
kw_if 7 2
```

### 10.3 Integration Tests (Layer 3-4)

Run the lexer as part of the full pipeline against reference programs:
- `mandelbrot.zig`: Float literals, hex constants, string escapes.
- `eval.zig`: Deeply nested switches, builtin calls, error literals.
- `zig1` source itself: All language features.

Verify:
1. Token stream matches `zig0` output (differential).
2. Generated C89 compiles and runs correctly.
3. Peak memory stays under 16 MB.

---

## 11. Z98-Specific Implementation Constraints

| Limitation | Workaround | Notes |
|---|---|---|
| No global aggregate constants | `pub var` + `initKeywordTable()` at startup | Used for keyword table |
| No `@enumToInt`/`@intToEnum` | Manual `toInt()`/`fromInt()` helpers | See `TokenKind` usage |
| Strict `i32` ↔ `usize` coercion | `@intCast` everywhere | Common in lexer arithmetic |
| No pointer captures | Unwrap optional before use | `if (opt != null) { var p = &opt.value; }` |
| Arena allocation only | All buffers use `Allocator` interface | No `new`/`delete` |
| Deterministic output required | Seeded hashers, stable iteration order | For `--dump-tokens` diff |

---

## Appendix A: TokenKind Count and Mapping

**Total:** 88 token kinds in `u16` (bootstrap had ~72 `Zig0TokenType` values).

**New kinds not in bootstrap:**
- `dot_lbrace`, `dot_star` — explicit tokens for `.{` and `.*` (bootstrap handled via context)
- `builtin_identifier` — separate from `identifier` for faster dispatch
- `err_token` — explicit error recovery token

**Removed from bootstrap:**
- `TOKEN_RANGE` merged into `dot_dot`/`dot_dot_dot` distinction
- `TOKEN_CHAR_LITERAL` value stored as `u64` not separate union variant
- `TOKEN_FLOAT_LITERAL` parsing unified with integer via `scanNumber`

**Reserved for extensibility:** The last 10 values of `u16` (65526..65535) are reserved for future token kinds without breaking binary compatibility.

---

> **Next Component Preview:** The parser (`AST_PARSER_p2.md`) consumes the token stream produced by this lexer and builds the flat, index-based AST. The lexer's deterministic output and span accuracy are critical for differential AST comparison during development.
