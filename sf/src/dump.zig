const pal = @import("pal.zig");
const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const TokenKind = @import("token.zig").TokenKind;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;

pub fn dumpTokens(lex: *Lexer, interner: *StringInterner) void {
    var kind_buf: [24]u8 = undefined;
    var fmt_buf: [24]u8 = undefined;
    var sp: []const u8 = " ";
    var nl: []const u8 = "\n";
    var qq: []const u8 = " \"";
    var q: []const u8 = "\"";
    while (true) {
        var t = lexer_mod.lexerNextToken(lex);
        var kind_slice = tokenKindToString(t.kind, kind_buf[0..]);
        pal.stdout_write(kind_slice);
        pal.stdout_write(sp);
        pal.stdout_write(formatU32(t.span_start, fmt_buf[0..], 24));
        pal.stdout_write(sp);
        pal.stdout_write(formatU32(@intCast(u32, t.span_len), fmt_buf[0..], 24));
        if (t.kind == TokenKind.integer_literal or t.kind == TokenKind.char_literal) {
            pal.stdout_write(sp);
            pal.stdout_write(formatU64(t.value.int_val, fmt_buf[0..], 24));
        } else if (t.kind == TokenKind.float_literal) {
            pal.stdout_write(sp);
            pal.stdout_write(formatF64(t.value.float_val, fmt_buf[0..], 24));
        } else if (t.kind == TokenKind.string_literal or t.kind == TokenKind.identifier or t.kind == TokenKind.builtin_identifier) {
            pal.stdout_write(qq);
            var s = interner_mod.stringInternerGet(interner, t.value.string_id);
            pal.stdout_write(s);
            pal.stdout_write(q);
        }
        pal.stdout_write(nl);
        if (t.kind == TokenKind.eof) break;
    }
}

fn tokenKindToString(kind: TokenKind, buf: []u8) []u8 {
    var idx: usize = 0;
    switch (kind) {
        TokenKind.integer_literal => { var s: []const u8 = "integer_literal"; copyStr(buf, &idx, s); },
        TokenKind.float_literal => { var s: []const u8 = "float_literal"; copyStr(buf, &idx, s); },
        TokenKind.string_literal => { var s: []const u8 = "string_literal"; copyStr(buf, &idx, s); },
        TokenKind.char_literal => { var s: []const u8 = "char_literal"; copyStr(buf, &idx, s); },
        TokenKind.identifier => { var s: []const u8 = "identifier"; copyStr(buf, &idx, s); },
        TokenKind.builtin_identifier => { var s: []const u8 = "builtin_identifier"; copyStr(buf, &idx, s); },
        TokenKind.lparen => { var s: []const u8 = "lparen"; copyStr(buf, &idx, s); },
        TokenKind.rparen => { var s: []const u8 = "rparen"; copyStr(buf, &idx, s); },
        TokenKind.lbracket => { var s: []const u8 = "lbracket"; copyStr(buf, &idx, s); },
        TokenKind.rbracket => { var s: []const u8 = "rbracket"; copyStr(buf, &idx, s); },
        TokenKind.lbrace => { var s: []const u8 = "lbrace"; copyStr(buf, &idx, s); },
        TokenKind.rbrace => { var s: []const u8 = "rbrace"; copyStr(buf, &idx, s); },
        TokenKind.semicolon => { var s: []const u8 = "semicolon"; copyStr(buf, &idx, s); },
        TokenKind.colon => { var s: []const u8 = "colon"; copyStr(buf, &idx, s); },
        TokenKind.comma => { var s: []const u8 = "comma"; copyStr(buf, &idx, s); },
        TokenKind.dot => { var s: []const u8 = "dot"; copyStr(buf, &idx, s); },
        TokenKind.at_sign => { var s: []const u8 = "at_sign"; copyStr(buf, &idx, s); },
        TokenKind.underscore => { var s: []const u8 = "underscore"; copyStr(buf, &idx, s); },
        TokenKind.question_mark => { var s: []const u8 = "question_mark"; copyStr(buf, &idx, s); },
        TokenKind.bang => { var s: []const u8 = "bang"; copyStr(buf, &idx, s); },
        TokenKind.plus => { var s: []const u8 = "plus"; copyStr(buf, &idx, s); },
        TokenKind.minus => { var s: []const u8 = "minus"; copyStr(buf, &idx, s); },
        TokenKind.star => { var s: []const u8 = "star"; copyStr(buf, &idx, s); },
        TokenKind.slash => { var s: []const u8 = "slash"; copyStr(buf, &idx, s); },
        TokenKind.percent => { var s: []const u8 = "percent"; copyStr(buf, &idx, s); },
        TokenKind.ampersand => { var s: []const u8 = "ampersand"; copyStr(buf, &idx, s); },
        TokenKind.pipe => { var s: []const u8 = "pipe"; copyStr(buf, &idx, s); },
        TokenKind.caret => { var s: []const u8 = "caret"; copyStr(buf, &idx, s); },
        TokenKind.tilde => { var s: []const u8 = "tilde"; copyStr(buf, &idx, s); },
        TokenKind.shl => { var s: []const u8 = "shl"; copyStr(buf, &idx, s); },
        TokenKind.shr => { var s: []const u8 = "shr"; copyStr(buf, &idx, s); },
        TokenKind.eq_eq => { var s: []const u8 = "eq_eq"; copyStr(buf, &idx, s); },
        TokenKind.bang_eq => { var s: []const u8 = "bang_eq"; copyStr(buf, &idx, s); },
        TokenKind.less => { var s: []const u8 = "less"; copyStr(buf, &idx, s); },
        TokenKind.less_eq => { var s: []const u8 = "less_eq"; copyStr(buf, &idx, s); },
        TokenKind.greater => { var s: []const u8 = "greater"; copyStr(buf, &idx, s); },
        TokenKind.greater_eq => { var s: []const u8 = "greater_eq"; copyStr(buf, &idx, s); },
        TokenKind.eq => { var s: []const u8 = "eq"; copyStr(buf, &idx, s); },
        TokenKind.plus_eq => { var s: []const u8 = "plus_eq"; copyStr(buf, &idx, s); },
        TokenKind.minus_eq => { var s: []const u8 = "minus_eq"; copyStr(buf, &idx, s); },
        TokenKind.star_eq => { var s: []const u8 = "star_eq"; copyStr(buf, &idx, s); },
        TokenKind.slash_eq => { var s: []const u8 = "slash_eq"; copyStr(buf, &idx, s); },
        TokenKind.percent_eq => { var s: []const u8 = "percent_eq"; copyStr(buf, &idx, s); },
        TokenKind.ampersand_eq => { var s: []const u8 = "ampersand_eq"; copyStr(buf, &idx, s); },
        TokenKind.pipe_eq => { var s: []const u8 = "pipe_eq"; copyStr(buf, &idx, s); },
        TokenKind.caret_eq => { var s: []const u8 = "caret_eq"; copyStr(buf, &idx, s); },
        TokenKind.shl_eq => { var s: []const u8 = "shl_eq"; copyStr(buf, &idx, s); },
        TokenKind.shr_eq => { var s: []const u8 = "shr_eq"; copyStr(buf, &idx, s); },
        TokenKind.dot_dot => { var s: []const u8 = "dot_dot"; copyStr(buf, &idx, s); },
        TokenKind.dot_dot_dot => { var s: []const u8 = "dot_dot_dot"; copyStr(buf, &idx, s); },
        TokenKind.dot_lbrace => { var s: []const u8 = "dot_lbrace"; copyStr(buf, &idx, s); },
        TokenKind.dot_star => { var s: []const u8 = "dot_star"; copyStr(buf, &idx, s); },
        TokenKind.fat_arrow => { var s: []const u8 = "fat_arrow"; copyStr(buf, &idx, s); },
        TokenKind.kw_const => { var s: []const u8 = "kw_const"; copyStr(buf, &idx, s); },
        TokenKind.kw_var => { var s: []const u8 = "kw_var"; copyStr(buf, &idx, s); },
        TokenKind.kw_fn => { var s: []const u8 = "kw_fn"; copyStr(buf, &idx, s); },
        TokenKind.kw_pub => { var s: []const u8 = "kw_pub"; copyStr(buf, &idx, s); },
        TokenKind.kw_extern => { var s: []const u8 = "kw_extern"; copyStr(buf, &idx, s); },
        TokenKind.kw_export => { var s: []const u8 = "kw_export"; copyStr(buf, &idx, s); },
        TokenKind.kw_test => { var s: []const u8 = "kw_test"; copyStr(buf, &idx, s); },
        TokenKind.kw_struct => { var s: []const u8 = "kw_struct"; copyStr(buf, &idx, s); },
        TokenKind.kw_enum => { var s: []const u8 = "kw_enum"; copyStr(buf, &idx, s); },
        TokenKind.kw_union => { var s: []const u8 = "kw_union"; copyStr(buf, &idx, s); },
        TokenKind.kw_if => { var s: []const u8 = "kw_if"; copyStr(buf, &idx, s); },
        TokenKind.kw_else => { var s: []const u8 = "kw_else"; copyStr(buf, &idx, s); },
        TokenKind.kw_while => { var s: []const u8 = "kw_while"; copyStr(buf, &idx, s); },
        TokenKind.kw_for => { var s: []const u8 = "kw_for"; copyStr(buf, &idx, s); },
        TokenKind.kw_switch => { var s: []const u8 = "kw_switch"; copyStr(buf, &idx, s); },
        TokenKind.kw_return => { var s: []const u8 = "kw_return"; copyStr(buf, &idx, s); },
        TokenKind.kw_break => { var s: []const u8 = "kw_break"; copyStr(buf, &idx, s); },
        TokenKind.kw_continue => { var s: []const u8 = "kw_continue"; copyStr(buf, &idx, s); },
        TokenKind.kw_defer => { var s: []const u8 = "kw_defer"; copyStr(buf, &idx, s); },
        TokenKind.kw_errdefer => { var s: []const u8 = "kw_errdefer"; copyStr(buf, &idx, s); },
        TokenKind.kw_try => { var s: []const u8 = "kw_try"; copyStr(buf, &idx, s); },
        TokenKind.kw_catch => { var s: []const u8 = "kw_catch"; copyStr(buf, &idx, s); },
        TokenKind.kw_orelse => { var s: []const u8 = "kw_orelse"; copyStr(buf, &idx, s); },
        TokenKind.kw_error => { var s: []const u8 = "kw_error"; copyStr(buf, &idx, s); },
        TokenKind.kw_and => { var s: []const u8 = "kw_and"; copyStr(buf, &idx, s); },
        TokenKind.kw_or => { var s: []const u8 = "kw_or"; copyStr(buf, &idx, s); },
        TokenKind.kw_true => { var s: []const u8 = "kw_true"; copyStr(buf, &idx, s); },
        TokenKind.kw_false => { var s: []const u8 = "kw_false"; copyStr(buf, &idx, s); },
        TokenKind.kw_null => { var s: []const u8 = "kw_null"; copyStr(buf, &idx, s); },
        TokenKind.kw_undefined => { var s: []const u8 = "kw_undefined"; copyStr(buf, &idx, s); },
        TokenKind.kw_unreachable => { var s: []const u8 = "kw_unreachable"; copyStr(buf, &idx, s); },
        TokenKind.kw_void => { var s: []const u8 = "kw_void"; copyStr(buf, &idx, s); },
        TokenKind.kw_bool => { var s: []const u8 = "kw_bool"; copyStr(buf, &idx, s); },
        TokenKind.kw_noreturn => { var s: []const u8 = "kw_noreturn"; copyStr(buf, &idx, s); },
        TokenKind.kw_c_char => { var s: []const u8 = "kw_c_char"; copyStr(buf, &idx, s); },
        TokenKind.eof => { var s: []const u8 = "eof"; copyStr(buf, &idx, s); },
        TokenKind.err_token => { var s: []const u8 = "err_token"; copyStr(buf, &idx, s); },
    }
    buf[idx] = 0;
    return buf[0..idx];
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
    return buf[start..buf_len - 1];
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
    return buf[start..buf_len - 1];
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
        fmt_buf[@intCast(usize, fi)] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, digit));
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
            exp_buf[@intCast(usize, ei)] = @intCast(u8, @intCast(u32, '0') + @intCast(u32, expv % 10));
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
