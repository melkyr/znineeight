const pal = @import("pal.zig");
const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const TokenKind = @import("token.zig").TokenKind;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const fmt = @import("util/format.zig");

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
        pal.stdout_write(fmt.formatU32(t.span_start, fmt_buf[0..], 24));
        pal.stdout_write(sp);
        pal.stdout_write(fmt.formatU32(@intCast(u32, t.span_len), fmt_buf[0..], 24));
        if (t.kind == TokenKind.integer_literal or t.kind == TokenKind.char_literal) {
            pal.stdout_write(sp);
            pal.stdout_write(fmt.formatU64(t.value.int_val, fmt_buf[0..], 24));
        } else if (t.kind == TokenKind.float_literal) {
            pal.stdout_write(sp);
            pal.stdout_write(fmt.formatF64(t.value.float_val, fmt_buf[0..], 24));
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
        TokenKind.integer_literal => { var s: []const u8 = "integer_literal"; fmt.copyStr(buf, &idx, s); },
        TokenKind.float_literal => { var s: []const u8 = "float_literal"; fmt.copyStr(buf, &idx, s); },
        TokenKind.string_literal => { var s: []const u8 = "string_literal"; fmt.copyStr(buf, &idx, s); },
        TokenKind.char_literal => { var s: []const u8 = "char_literal"; fmt.copyStr(buf, &idx, s); },
        TokenKind.identifier => { var s: []const u8 = "identifier"; fmt.copyStr(buf, &idx, s); },
        TokenKind.builtin_identifier => { var s: []const u8 = "builtin_identifier"; fmt.copyStr(buf, &idx, s); },
        TokenKind.lparen => { var s: []const u8 = "lparen"; fmt.copyStr(buf, &idx, s); },
        TokenKind.rparen => { var s: []const u8 = "rparen"; fmt.copyStr(buf, &idx, s); },
        TokenKind.lbracket => { var s: []const u8 = "lbracket"; fmt.copyStr(buf, &idx, s); },
        TokenKind.rbracket => { var s: []const u8 = "rbracket"; fmt.copyStr(buf, &idx, s); },
        TokenKind.lbrace => { var s: []const u8 = "lbrace"; fmt.copyStr(buf, &idx, s); },
        TokenKind.rbrace => { var s: []const u8 = "rbrace"; fmt.copyStr(buf, &idx, s); },
        TokenKind.semicolon => { var s: []const u8 = "semicolon"; fmt.copyStr(buf, &idx, s); },
        TokenKind.colon => { var s: []const u8 = "colon"; fmt.copyStr(buf, &idx, s); },
        TokenKind.comma => { var s: []const u8 = "comma"; fmt.copyStr(buf, &idx, s); },
        TokenKind.dot => { var s: []const u8 = "dot"; fmt.copyStr(buf, &idx, s); },
        TokenKind.at_sign => { var s: []const u8 = "at_sign"; fmt.copyStr(buf, &idx, s); },
        TokenKind.underscore => { var s: []const u8 = "underscore"; fmt.copyStr(buf, &idx, s); },
        TokenKind.question_mark => { var s: []const u8 = "question_mark"; fmt.copyStr(buf, &idx, s); },
        TokenKind.bang => { var s: []const u8 = "bang"; fmt.copyStr(buf, &idx, s); },
        TokenKind.plus => { var s: []const u8 = "plus"; fmt.copyStr(buf, &idx, s); },
        TokenKind.minus => { var s: []const u8 = "minus"; fmt.copyStr(buf, &idx, s); },
        TokenKind.star => { var s: []const u8 = "star"; fmt.copyStr(buf, &idx, s); },
        TokenKind.slash => { var s: []const u8 = "slash"; fmt.copyStr(buf, &idx, s); },
        TokenKind.percent => { var s: []const u8 = "percent"; fmt.copyStr(buf, &idx, s); },
        TokenKind.ampersand => { var s: []const u8 = "ampersand"; fmt.copyStr(buf, &idx, s); },
        TokenKind.pipe => { var s: []const u8 = "pipe"; fmt.copyStr(buf, &idx, s); },
        TokenKind.caret => { var s: []const u8 = "caret"; fmt.copyStr(buf, &idx, s); },
        TokenKind.tilde => { var s: []const u8 = "tilde"; fmt.copyStr(buf, &idx, s); },
        TokenKind.shl => { var s: []const u8 = "shl"; fmt.copyStr(buf, &idx, s); },
        TokenKind.shr => { var s: []const u8 = "shr"; fmt.copyStr(buf, &idx, s); },
        TokenKind.eq_eq => { var s: []const u8 = "eq_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.bang_eq => { var s: []const u8 = "bang_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.less => { var s: []const u8 = "less"; fmt.copyStr(buf, &idx, s); },
        TokenKind.less_eq => { var s: []const u8 = "less_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.greater => { var s: []const u8 = "greater"; fmt.copyStr(buf, &idx, s); },
        TokenKind.greater_eq => { var s: []const u8 = "greater_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.eq => { var s: []const u8 = "eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.plus_eq => { var s: []const u8 = "plus_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.minus_eq => { var s: []const u8 = "minus_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.star_eq => { var s: []const u8 = "star_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.slash_eq => { var s: []const u8 = "slash_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.percent_eq => { var s: []const u8 = "percent_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.ampersand_eq => { var s: []const u8 = "ampersand_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.pipe_eq => { var s: []const u8 = "pipe_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.caret_eq => { var s: []const u8 = "caret_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.shl_eq => { var s: []const u8 = "shl_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.shr_eq => { var s: []const u8 = "shr_eq"; fmt.copyStr(buf, &idx, s); },
        TokenKind.dot_dot => { var s: []const u8 = "dot_dot"; fmt.copyStr(buf, &idx, s); },
        TokenKind.dot_dot_dot => { var s: []const u8 = "dot_dot_dot"; fmt.copyStr(buf, &idx, s); },
        TokenKind.dot_lbrace => { var s: []const u8 = "dot_lbrace"; fmt.copyStr(buf, &idx, s); },
        TokenKind.dot_star => { var s: []const u8 = "dot_star"; fmt.copyStr(buf, &idx, s); },
        TokenKind.fat_arrow => { var s: []const u8 = "fat_arrow"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_const => { var s: []const u8 = "kw_const"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_var => { var s: []const u8 = "kw_var"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_fn => { var s: []const u8 = "kw_fn"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_pub => { var s: []const u8 = "kw_pub"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_extern => { var s: []const u8 = "kw_extern"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_export => { var s: []const u8 = "kw_export"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_test => { var s: []const u8 = "kw_test"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_struct => { var s: []const u8 = "kw_struct"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_enum => { var s: []const u8 = "kw_enum"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_union => { var s: []const u8 = "kw_union"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_if => { var s: []const u8 = "kw_if"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_else => { var s: []const u8 = "kw_else"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_while => { var s: []const u8 = "kw_while"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_for => { var s: []const u8 = "kw_for"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_switch => { var s: []const u8 = "kw_switch"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_return => { var s: []const u8 = "kw_return"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_break => { var s: []const u8 = "kw_break"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_continue => { var s: []const u8 = "kw_continue"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_defer => { var s: []const u8 = "kw_defer"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_errdefer => { var s: []const u8 = "kw_errdefer"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_try => { var s: []const u8 = "kw_try"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_catch => { var s: []const u8 = "kw_catch"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_orelse => { var s: []const u8 = "kw_orelse"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_error => { var s: []const u8 = "kw_error"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_and => { var s: []const u8 = "kw_and"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_or => { var s: []const u8 = "kw_or"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_true => { var s: []const u8 = "kw_true"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_false => { var s: []const u8 = "kw_false"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_null => { var s: []const u8 = "kw_null"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_undefined => { var s: []const u8 = "kw_undefined"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_unreachable => { var s: []const u8 = "kw_unreachable"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_void => { var s: []const u8 = "kw_void"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_bool => { var s: []const u8 = "kw_bool"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_noreturn => { var s: []const u8 = "kw_noreturn"; fmt.copyStr(buf, &idx, s); },
        TokenKind.kw_c_char => { var s: []const u8 = "kw_c_char"; fmt.copyStr(buf, &idx, s); },
        TokenKind.eof => { var s: []const u8 = "eof"; fmt.copyStr(buf, &idx, s); },
        TokenKind.err_token => { var s: []const u8 = "err_token"; fmt.copyStr(buf, &idx, s); },
    }
    buf[idx] = 0;
    return buf[0..idx];
}
