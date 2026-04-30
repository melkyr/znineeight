const pal = @import("pal.zig");
const token_mod = @import("token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;

pub fn dumpTokens(l: *void, interner: *StringInterner) void {
    const lexer_mod = @import("lexer.zig");
    var lex = @ptrCast(*lexer_mod.Lexer, l);
    var buf32: [24]u8 = undefined;
    while (true) {
        var t = lexer_mod.lexerNextToken(lex);
        tokenKindToString(t.kind, buf32[0..]);
        pal.stdout_write(buf32[0..]);
        pal.stdout_write(" ");
        pal.stdout_write(formatU32(t.span_start, buf32[0..], 24));
        pal.stdout_write(" ");
        pal.stdout_write(formatU32(@intCast(u32, t.span_len), buf32[0..], 24));
        if (t.kind == TokenKind.integer_literal or t.kind == TokenKind.char_literal) {
            pal.stdout_write(" ");
            pal.stdout_write(formatU64(t.value.int_val, buf32[0..], 24));
        } else if (t.kind == TokenKind.float_literal) {
            pal.stdout_write(" ");
            pal.stdout_write(formatF64(t.value.float_val, buf32[0..], 24));
        } else if (t.kind == TokenKind.string_literal or t.kind == TokenKind.identifier or t.kind == TokenKind.builtin_identifier) {
            pal.stdout_write(" \"");
            pal.stdout_write(interner_mod.stringInternerGet(interner, t.value.string_id));
            pal.stdout_write("\"");
        }
        pal.stdout_write("\n");
        if (t.kind == TokenKind.eof) break;
    }
}

fn tokenKindToString(kind: TokenKind, buf: []u8) void {
    var idx: usize = 0;
    switch (kind) {
        TokenKind.integer_literal => { copyStr(buf, &idx, "integer_literal"); },
        TokenKind.float_literal => { copyStr(buf, &idx, "float_literal"); },
        TokenKind.string_literal => { copyStr(buf, &idx, "string_literal"); },
        TokenKind.char_literal => { copyStr(buf, &idx, "char_literal"); },
        TokenKind.identifier => { copyStr(buf, &idx, "identifier"); },
        TokenKind.builtin_identifier => { copyStr(buf, &idx, "builtin_identifier"); },
        TokenKind.lparen => { copyStr(buf, &idx, "lparen"); },
        TokenKind.rparen => { copyStr(buf, &idx, "rparen"); },
        TokenKind.lbracket => { copyStr(buf, &idx, "lbracket"); },
        TokenKind.rbracket => { copyStr(buf, &idx, "rbracket"); },
        TokenKind.lbrace => { copyStr(buf, &idx, "lbrace"); },
        TokenKind.rbrace => { copyStr(buf, &idx, "rbrace"); },
        TokenKind.semicolon => { copyStr(buf, &idx, "semicolon"); },
        TokenKind.colon => { copyStr(buf, &idx, "colon"); },
        TokenKind.comma => { copyStr(buf, &idx, "comma"); },
        TokenKind.dot => { copyStr(buf, &idx, "dot"); },
        TokenKind.at_sign => { copyStr(buf, &idx, "at_sign"); },
        TokenKind.underscore => { copyStr(buf, &idx, "underscore"); },
        TokenKind.question_mark => { copyStr(buf, &idx, "question_mark"); },
        TokenKind.bang => { copyStr(buf, &idx, "bang"); },
        TokenKind.plus => { copyStr(buf, &idx, "plus"); },
        TokenKind.minus => { copyStr(buf, &idx, "minus"); },
        TokenKind.star => { copyStr(buf, &idx, "star"); },
        TokenKind.slash => { copyStr(buf, &idx, "slash"); },
        TokenKind.percent => { copyStr(buf, &idx, "percent"); },
        TokenKind.ampersand => { copyStr(buf, &idx, "ampersand"); },
        TokenKind.pipe => { copyStr(buf, &idx, "pipe"); },
        TokenKind.caret => { copyStr(buf, &idx, "caret"); },
        TokenKind.tilde => { copyStr(buf, &idx, "tilde"); },
        TokenKind.shl => { copyStr(buf, &idx, "shl"); },
        TokenKind.shr => { copyStr(buf, &idx, "shr"); },
        TokenKind.eq_eq => { copyStr(buf, &idx, "eq_eq"); },
        TokenKind.bang_eq => { copyStr(buf, &idx, "bang_eq"); },
        TokenKind.less => { copyStr(buf, &idx, "less"); },
        TokenKind.less_eq => { copyStr(buf, &idx, "less_eq"); },
        TokenKind.greater => { copyStr(buf, &idx, "greater"); },
        TokenKind.greater_eq => { copyStr(buf, &idx, "greater_eq"); },
        TokenKind.eq => { copyStr(buf, &idx, "eq"); },
        TokenKind.plus_eq => { copyStr(buf, &idx, "plus_eq"); },
        TokenKind.minus_eq => { copyStr(buf, &idx, "minus_eq"); },
        TokenKind.star_eq => { copyStr(buf, &idx, "star_eq"); },
        TokenKind.slash_eq => { copyStr(buf, &idx, "slash_eq"); },
        TokenKind.percent_eq => { copyStr(buf, &idx, "percent_eq"); },
        TokenKind.ampersand_eq => { copyStr(buf, &idx, "ampersand_eq"); },
        TokenKind.pipe_eq => { copyStr(buf, &idx, "pipe_eq"); },
        TokenKind.caret_eq => { copyStr(buf, &idx, "caret_eq"); },
        TokenKind.shl_eq => { copyStr(buf, &idx, "shl_eq"); },
        TokenKind.shr_eq => { copyStr(buf, &idx, "shr_eq"); },
        TokenKind.dot_dot => { copyStr(buf, &idx, "dot_dot"); },
        TokenKind.dot_dot_dot => { copyStr(buf, &idx, "dot_dot_dot"); },
        TokenKind.dot_lbrace => { copyStr(buf, &idx, "dot_lbrace"); },
        TokenKind.dot_star => { copyStr(buf, &idx, "dot_star"); },
        TokenKind.fat_arrow => { copyStr(buf, &idx, "fat_arrow"); },
        TokenKind.kw_const => { copyStr(buf, &idx, "kw_const"); },
        TokenKind.kw_var => { copyStr(buf, &idx, "kw_var"); },
        TokenKind.kw_fn => { copyStr(buf, &idx, "kw_fn"); },
        TokenKind.kw_pub => { copyStr(buf, &idx, "kw_pub"); },
        TokenKind.kw_extern => { copyStr(buf, &idx, "kw_extern"); },
        TokenKind.kw_export => { copyStr(buf, &idx, "kw_export"); },
        TokenKind.kw_test => { copyStr(buf, &idx, "kw_test"); },
        TokenKind.kw_struct => { copyStr(buf, &idx, "kw_struct"); },
        TokenKind.kw_enum => { copyStr(buf, &idx, "kw_enum"); },
        TokenKind.kw_union => { copyStr(buf, &idx, "kw_union"); },
        TokenKind.kw_if => { copyStr(buf, &idx, "kw_if"); },
        TokenKind.kw_else => { copyStr(buf, &idx, "kw_else"); },
        TokenKind.kw_while => { copyStr(buf, &idx, "kw_while"); },
        TokenKind.kw_for => { copyStr(buf, &idx, "kw_for"); },
        TokenKind.kw_switch => { copyStr(buf, &idx, "kw_switch"); },
        TokenKind.kw_return => { copyStr(buf, &idx, "kw_return"); },
        TokenKind.kw_break => { copyStr(buf, &idx, "kw_break"); },
        TokenKind.kw_continue => { copyStr(buf, &idx, "kw_continue"); },
        TokenKind.kw_defer => { copyStr(buf, &idx, "kw_defer"); },
        TokenKind.kw_errdefer => { copyStr(buf, &idx, "kw_errdefer"); },
        TokenKind.kw_try => { copyStr(buf, &idx, "kw_try"); },
        TokenKind.kw_catch => { copyStr(buf, &idx, "kw_catch"); },
        TokenKind.kw_orelse => { copyStr(buf, &idx, "kw_orelse"); },
        TokenKind.kw_error => { copyStr(buf, &idx, "kw_error"); },
        TokenKind.kw_and => { copyStr(buf, &idx, "kw_and"); },
        TokenKind.kw_or => { copyStr(buf, &idx, "kw_or"); },
        TokenKind.kw_true => { copyStr(buf, &idx, "kw_true"); },
        TokenKind.kw_false => { copyStr(buf, &idx, "kw_false"); },
        TokenKind.kw_null => { copyStr(buf, &idx, "kw_null"); },
        TokenKind.kw_undefined => { copyStr(buf, &idx, "kw_undefined"); },
        TokenKind.kw_unreachable => { copyStr(buf, &idx, "kw_unreachable"); },
        TokenKind.kw_void => { copyStr(buf, &idx, "kw_void"); },
        TokenKind.kw_bool => { copyStr(buf, &idx, "kw_bool"); },
        TokenKind.kw_noreturn => { copyStr(buf, &idx, "kw_noreturn"); },
        TokenKind.kw_c_char => { copyStr(buf, &idx, "kw_c_char"); },
        TokenKind.eof => { copyStr(buf, &idx, "eof"); },
        TokenKind.err_token => { copyStr(buf, &idx, "err_token"); },
    }
    buf[idx] = 0;
}

fn copyStr(buf: []u8, idx: *usize, s: []const u8) void {
    var i: usize = 0;
    while (i < s.len) {
        buf[idx.*] = s[i];
        idx.* += 1;
        i += 1;
    }
}

fn formatU32(val: u32, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + v % 10);
            v = v / 10;
            idx -= 1;
        }
    }
    var start = idx + 1;
    return buf[start..buf_len];
}

fn formatU64(val: u64, buf: []u8, buf_len: usize) []u8 {
    var idx: usize = buf_len - 1;
    var v = val;
    buf[idx] = 0;
    idx -= 1;
    if (v == 0) {
        buf[idx] = '0';
        idx -= 1;
    } else {
        while (v > 0) {
            buf[idx] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, v % 10));
            v = v / 10;
            idx -= 1;
        }
    }
    var start = idx + 1;
    return buf[start..buf_len];
}

fn extractDigit(v: f64) i32 {
    if (v >= 9.0) return 9;
    if (v >= 8.0) return 8;
    if (v >= 7.0) return 7;
    if (v >= 6.0) return 6;
    if (v >= 5.0) return 5;
    if (v >= 4.0) return 4;
    if (v >= 3.0) return 3;
    if (v >= 2.0) return 2;
    if (v >= 1.0) return 1;
    return 0;
}

fn formatF64(val: f64, buf: []u8, buf_len: usize) []u8 {
    var is_neg: u8 = 0;
    var v = val;
    if (v < 0) {
        is_neg = 1;
        v = -v;
    }
    var exp: i32 = 0;
    if (v >= 10.0 or v < 1.0) {
        while (v >= 10.0) {
            v = v / 10.0;
            exp += 1;
        }
        while (v < 1.0 and v != 0.0) {
            v = v * 10.0;
            exp -= 1;
        }
    }
    var fmt_buf: [64]u8 = undefined;
    var fi: i32 = 0;
    var rem = v;
    while (fi < 6) {
        var digit = extractDigit(rem);
        fmt_buf[@intCast(usize, fi)] = @intCast(u8, '0' + @intCast(u32, digit));
        fi += 1;
        rem = (rem - @intToFloat(f64, digit)) * 10.0;
    }
    var bi: i32 = 0;
    if (is_neg != 0) {
        buf[@intCast(usize, bi)] = '-';
        bi += 1;
    }
    var di: i32 = 0;
    buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
    bi += 1;
    di += 1;
    var has_frac: u8 = 0;
    while (di < 6) {
        if (fmt_buf[@intCast(usize, di)] != '0') {
            has_frac = 1;
        }
        di += 1;
    }
    if (has_frac != 0) {
        buf[@intCast(usize, bi)] = '.';
        bi += 1;
        di = 1;
        while (di < 6) {
            buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
            bi += 1;
            di += 1;
        }
    } else if (exp != 0) {
        di = 0;
        buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
        bi += 1;
        buf[@intCast(usize, bi)] = '.';
        bi += 1;
        di = 1;
        while (di < 6) {
            buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, di)];
            bi += 1;
            di += 1;
        }
    } else {
        buf[@intCast(usize, bi)] = fmt_buf[@intCast(usize, 0)];
        bi += 1;
    }
    if (exp != 0) {
        buf[@intCast(usize, bi)] = 'e';
        bi += 1;
        if (exp < 0) {
            buf[@intCast(usize, bi)] = '-';
            bi += 1;
            exp = -exp;
        } else {
            buf[@intCast(usize, bi)] = '+';
            bi += 1;
        }
        var exp_buf: [8]u8 = undefined;
        var ei: i32 = 7;
        exp_buf[@intCast(usize, ei)] = 0;
        ei -= 1;
        var expv = exp;
        while (expv > 0) {
            exp_buf[@intCast(usize, ei)] = @intCast(u8, '0' + @intCast(u32, expv % 10));
            expv = expv / 10;
            ei -= 1;
        }
        ei += 1;
        while (@intCast(usize, ei) < 7) {
            buf[@intCast(usize, bi)] = exp_buf[@intCast(usize, ei)];
            bi += 1;
            ei += 1;
        }
    }
    buf[@intCast(usize, bi)] = 0;
    return buf[0..@intCast(usize, bi)];
}
