// lexer.zig — z9edit headless core: per-line syntax tokenizer.
//
// Z98 subset only, no imports, GUI-free. `lexLine` is called once per visible
// line and carries two pieces of state across calls: block-comment depth and an
// unterminated quoted string. An unterminated `"..."` continues on the next
// line (editor coloring only; the compiler's own lexer rejects it). Tokens cover
// every byte of the line, so callers can paint by slicing (whitespace is
// `plain`). `lexErrCodeAt` is a stateless `error[NNNN]` lookup for the status
// bar.

pub const TokKind = enum(u8) { plain, keyword, builtin, errcode, string, comment, number, type_name, ident, punct };

pub const Token = struct { kind: TokKind, start: u32, len: u32 };

pub const LexState = struct {
    block_depth: u8,
    in_string: bool,
};

pub fn lexInitState() LexState {
    return LexState{ .block_depth = 0, .in_string = false };
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentChar(c: u8) bool {
    return isIdentStart(c) or isDigit(c);
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r';
}

fn eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn isKeyword(s: []const u8) bool {
    var kw: []const u8 = "const var fn pub return if else while for switch break continue defer errdefer struct enum union extern comptime try catch orelse anytype true false null undefined asm async await and or nosuspend suspend resume usingnamespace export inline noinline threadlocal linksection callconv align allowzero volatile addrspace";
    var start: usize = 0;
    var i: usize = 0;
    while (i <= kw.len) : (i += 1) {
        if (i == kw.len or kw[i] == ' ') {
            if (i > start and eql(s, kw[start..i])) return true;
            start = i + 1;
        }
    }
    return false;
}

fn isTypeName(s: []const u8) bool {
    var ty: []const u8 = "void bool u8 u16 u32 u64 u128 usize i8 i16 i32 i64 i128 isize f16 f32 f64 f80 f128 c_char c_int c_uint c_long c_ulong c_longlong c_ulonglong anyerror type noreturn comptime_int comptime_float";
    var start: usize = 0;
    var i: usize = 0;
    while (i <= ty.len) : (i += 1) {
        if (i == ty.len or ty[i] == ' ') {
            if (i > start and eql(s, ty[start..i])) return true;
            start = i + 1;
        }
    }
    return false;
}

fn put(out: []Token, count: *usize, kind: TokKind, start: usize, len: usize) void {
    if (count.* >= out.len) return;
    out[count.*] = Token{ .kind = kind, .start = @intCast(u32, start), .len = @intCast(u32, len) };
    count.* += 1;
}

fn errCodeAt(line: []const u8, start: usize) usize {
    // `start` points at 'e' of "error[". Returns the index just past ']' or 0.
    if (start + 7 >= line.len) return 0;
    if (line[start + 5] != '[') return 0;
    var i = start + 6;
    var digits: usize = 0;
    while (i < line.len and isDigit(line[i])) : (i += 1) {
        digits += 1;
    }
    if (digits == 0 or i >= line.len or line[i] != ']') return 0;
    return i + 1;
}

fn errCodeNumber(line: []const u8, start: usize, end: usize) u32 {
    var v: u32 = 0;
    var i = start + 6;
    while (i < end and line[i] != ']') : (i += 1) {
        v = v * 10 + @intCast(u32, line[i] - '0');
    }
    return v;
}

pub fn lexLine(st: *LexState, line: []const u8, out: []Token) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < line.len) {
        // Carried block comment.
        if (st.block_depth > 0) {
            const start = i;
            while (i < line.len) {
                if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '*') {
                    st.block_depth += 1;
                    i += 2;
                } else if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '/') {
                    st.block_depth -= 1;
                    i += 2;
                    if (st.block_depth == 0) break;
                } else {
                    i += 1;
                }
            }
            put(out, &n, .comment, start, i - start);
            continue;
        }

        // Carried quoted string.
        if (st.in_string) {
            const start = i;
            while (i < line.len) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 2;
                } else if (line[i] == '"') {
                    i += 1;
                    st.in_string = false;
                    break;
                } else {
                    i += 1;
                }
            }
            put(out, &n, .string, start, i - start);
            continue;
        }

        const c = line[i];

        if (isSpace(c)) {
            const start = i;
            while (i < line.len and isSpace(line[i])) : (i += 1) {}
            put(out, &n, .plain, start, i - start);
            continue;
        }

        if (c == '/' and i + 1 < line.len and line[i + 1] == '/') {
            put(out, &n, .comment, i, line.len - i);
            i = line.len;
            continue;
        }

        if (c == '/' and i + 1 < line.len and line[i + 1] == '*') {
            const start = i;
            st.block_depth = 1;
            i += 2;
            while (i < line.len) {
                if (i + 1 < line.len and line[i] == '/' and line[i + 1] == '*') {
                    st.block_depth += 1;
                    i += 2;
                } else if (i + 1 < line.len and line[i] == '*' and line[i + 1] == '/') {
                    st.block_depth -= 1;
                    i += 2;
                    if (st.block_depth == 0) break;
                } else {
                    i += 1;
                }
            }
            put(out, &n, .comment, start, i - start);
            continue;
        }

        if (c == '"') {
            const start = i;
            i += 1;
            var closed = false;
            while (i < line.len) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 2;
                } else if (line[i] == '"') {
                    i += 1;
                    closed = true;
                    break;
                } else {
                    i += 1;
                }
            }
            if (!closed) st.in_string = true;
            put(out, &n, .string, start, i - start);
            continue;
        }

        if (c == '\'') {
            const start = i;
            i += 1;
            while (i < line.len) {
                if (line[i] == '\\' and i + 1 < line.len) {
                    i += 2;
                } else if (line[i] == '\'') {
                    i += 1;
                    break;
                } else {
                    i += 1;
                }
            }
            put(out, &n, .string, start, i - start);
            continue;
        }

        if (c == '@') {
            const start = i;
            i += 1;
            while (i < line.len and isIdentChar(line[i])) : (i += 1) {}
            put(out, &n, .builtin, start, i - start);
            continue;
        }

        if (isDigit(c)) {
            const start = i;
            if (i + 1 < line.len and line[i] == '0' and (line[i + 1] == 'x' or line[i + 1] == 'X' or line[i + 1] == 'b' or line[i + 1] == 'B' or line[i + 1] == 'o' or line[i + 1] == 'O')) {
                i += 2;
                while (i < line.len) {
                    const d = line[i];
                    const hex = (d >= '0' and d <= '9') or (d >= 'a' and d <= 'f') or (d >= 'A' and d <= 'F') or d == '_';
                    if (!hex) break;
                    i += 1;
                }
            } else {
                while (i < line.len and isDigit(line[i])) : (i += 1) {}
                if (i + 1 < line.len and line[i] == '.' and isDigit(line[i + 1])) {
                    i += 1;
                    while (i < line.len and isDigit(line[i])) : (i += 1) {}
                }
            }
            put(out, &n, .number, start, i - start);
            continue;
        }

        if (isIdentStart(c)) {
            const start = i;
            while (i < line.len and isIdentChar(line[i])) : (i += 1) {}
            const word = line[start..i];
            const ec_end = errCodeAt(line, start);
            if (eql(word, "error") and ec_end != 0) {
                const end = ec_end;
                put(out, &n, .errcode, start, end - start);
                i = end;
                continue;
            }
            if (isKeyword(word)) {
                put(out, &n, .keyword, start, i - start);
            } else if (isTypeName(word)) {
                put(out, &n, .type_name, start, i - start);
            } else {
                put(out, &n, .ident, start, i - start);
            }
            continue;
        }

        put(out, &n, .punct, i, 1);
        i += 1;
    }
    return n;
}

pub fn lexErrCodeAt(line: []const u8, col: usize) u32 {
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        if (line[i] != 'e') continue;
        if (i + 5 >= line.len) continue;
        if (line[i + 1] != 'r' or line[i + 2] != 'r' or line[i + 3] != 'o' or line[i + 4] != 'r') continue;
        const end = errCodeAt(line, i);
        if (end == 0) continue;
        if (col >= i and col < end) return errCodeNumber(line, i, end);
    }
    return 0;
}
