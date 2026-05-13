const pal = @import("pal.zig");
const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const TokenKind = @import("token.zig").TokenKind;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const dh = @import("dump_helpers.zig");

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
        pal.stdout_write(dh.formatU32(t.span_start, fmt_buf[0..], 24));
        pal.stdout_write(sp);
        pal.stdout_write(dh.formatU32(@intCast(u32, t.span_len), fmt_buf[0..], 24));
        if (t.kind == TokenKind.integer_literal or t.kind == TokenKind.char_literal) {
            pal.stdout_write(sp);
            pal.stdout_write(dh.formatU64(t.value.int_val, fmt_buf[0..], 24));
        } else if (t.kind == TokenKind.float_literal) {
            pal.stdout_write(sp);
            pal.stdout_write(dh.formatF64(t.value.float_val, fmt_buf[0..], 24));
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
        TokenKind.integer_literal => { var s: []const u8 = "integer_literal"; dh.copyStr(buf, &idx, s); },
        TokenKind.float_literal => { var s: []const u8 = "float_literal"; dh.copyStr(buf, &idx, s); },
        TokenKind.string_literal => { var s: []const u8 = "string_literal"; dh.copyStr(buf, &idx, s); },
        TokenKind.char_literal => { var s: []const u8 = "char_literal"; dh.copyStr(buf, &idx, s); },
        TokenKind.identifier => { var s: []const u8 = "identifier"; dh.copyStr(buf, &idx, s); },
        TokenKind.builtin_identifier => { var s: []const u8 = "builtin_identifier"; dh.copyStr(buf, &idx, s); },
        TokenKind.lparen => { var s: []const u8 = "lparen"; dh.copyStr(buf, &idx, s); },
        TokenKind.rparen => { var s: []const u8 = "rparen"; dh.copyStr(buf, &idx, s); },
        TokenKind.lbracket => { var s: []const u8 = "lbracket"; dh.copyStr(buf, &idx, s); },
        TokenKind.rbracket => { var s: []const u8 = "rbracket"; dh.copyStr(buf, &idx, s); },
        TokenKind.lbrace => { var s: []const u8 = "lbrace"; dh.copyStr(buf, &idx, s); },
        TokenKind.rbrace => { var s: []const u8 = "rbrace"; dh.copyStr(buf, &idx, s); },
        TokenKind.semicolon => { var s: []const u8 = "semicolon"; dh.copyStr(buf, &idx, s); },
        TokenKind.colon => { var s: []const u8 = "colon"; dh.copyStr(buf, &idx, s); },
        TokenKind.comma => { var s: []const u8 = "comma"; dh.copyStr(buf, &idx, s); },
        TokenKind.dot => { var s: []const u8 = "dot"; dh.copyStr(buf, &idx, s); },
        TokenKind.at_sign => { var s: []const u8 = "at_sign"; dh.copyStr(buf, &idx, s); },
        TokenKind.underscore => { var s: []const u8 = "underscore"; dh.copyStr(buf, &idx, s); },
        TokenKind.question_mark => { var s: []const u8 = "question_mark"; dh.copyStr(buf, &idx, s); },
        TokenKind.bang => { var s: []const u8 = "bang"; dh.copyStr(buf, &idx, s); },
        TokenKind.plus => { var s: []const u8 = "plus"; dh.copyStr(buf, &idx, s); },
        TokenKind.minus => { var s: []const u8 = "minus"; dh.copyStr(buf, &idx, s); },
        TokenKind.star => { var s: []const u8 = "star"; dh.copyStr(buf, &idx, s); },
        TokenKind.slash => { var s: []const u8 = "slash"; dh.copyStr(buf, &idx, s); },
        TokenKind.percent => { var s: []const u8 = "percent"; dh.copyStr(buf, &idx, s); },
        TokenKind.ampersand => { var s: []const u8 = "ampersand"; dh.copyStr(buf, &idx, s); },
        TokenKind.pipe => { var s: []const u8 = "pipe"; dh.copyStr(buf, &idx, s); },
        TokenKind.caret => { var s: []const u8 = "caret"; dh.copyStr(buf, &idx, s); },
        TokenKind.tilde => { var s: []const u8 = "tilde"; dh.copyStr(buf, &idx, s); },
        TokenKind.shl => { var s: []const u8 = "shl"; dh.copyStr(buf, &idx, s); },
        TokenKind.shr => { var s: []const u8 = "shr"; dh.copyStr(buf, &idx, s); },
        TokenKind.eq_eq => { var s: []const u8 = "eq_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.bang_eq => { var s: []const u8 = "bang_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.less => { var s: []const u8 = "less"; dh.copyStr(buf, &idx, s); },
        TokenKind.less_eq => { var s: []const u8 = "less_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.greater => { var s: []const u8 = "greater"; dh.copyStr(buf, &idx, s); },
        TokenKind.greater_eq => { var s: []const u8 = "greater_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.eq => { var s: []const u8 = "eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.plus_eq => { var s: []const u8 = "plus_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.minus_eq => { var s: []const u8 = "minus_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.star_eq => { var s: []const u8 = "star_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.slash_eq => { var s: []const u8 = "slash_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.percent_eq => { var s: []const u8 = "percent_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.ampersand_eq => { var s: []const u8 = "ampersand_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.pipe_eq => { var s: []const u8 = "pipe_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.caret_eq => { var s: []const u8 = "caret_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.shl_eq => { var s: []const u8 = "shl_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.shr_eq => { var s: []const u8 = "shr_eq"; dh.copyStr(buf, &idx, s); },
        TokenKind.dot_dot => { var s: []const u8 = "dot_dot"; dh.copyStr(buf, &idx, s); },
        TokenKind.dot_dot_dot => { var s: []const u8 = "dot_dot_dot"; dh.copyStr(buf, &idx, s); },
        TokenKind.dot_lbrace => { var s: []const u8 = "dot_lbrace"; dh.copyStr(buf, &idx, s); },
        TokenKind.dot_star => { var s: []const u8 = "dot_star"; dh.copyStr(buf, &idx, s); },
        TokenKind.fat_arrow => { var s: []const u8 = "fat_arrow"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_const => { var s: []const u8 = "kw_const"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_var => { var s: []const u8 = "kw_var"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_fn => { var s: []const u8 = "kw_fn"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_pub => { var s: []const u8 = "kw_pub"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_extern => { var s: []const u8 = "kw_extern"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_export => { var s: []const u8 = "kw_export"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_test => { var s: []const u8 = "kw_test"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_struct => { var s: []const u8 = "kw_struct"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_enum => { var s: []const u8 = "kw_enum"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_union => { var s: []const u8 = "kw_union"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_if => { var s: []const u8 = "kw_if"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_else => { var s: []const u8 = "kw_else"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_while => { var s: []const u8 = "kw_while"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_for => { var s: []const u8 = "kw_for"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_switch => { var s: []const u8 = "kw_switch"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_return => { var s: []const u8 = "kw_return"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_break => { var s: []const u8 = "kw_break"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_continue => { var s: []const u8 = "kw_continue"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_defer => { var s: []const u8 = "kw_defer"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_errdefer => { var s: []const u8 = "kw_errdefer"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_try => { var s: []const u8 = "kw_try"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_catch => { var s: []const u8 = "kw_catch"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_orelse => { var s: []const u8 = "kw_orelse"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_error => { var s: []const u8 = "kw_error"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_and => { var s: []const u8 = "kw_and"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_or => { var s: []const u8 = "kw_or"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_true => { var s: []const u8 = "kw_true"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_false => { var s: []const u8 = "kw_false"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_null => { var s: []const u8 = "kw_null"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_undefined => { var s: []const u8 = "kw_undefined"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_unreachable => { var s: []const u8 = "kw_unreachable"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_void => { var s: []const u8 = "kw_void"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_bool => { var s: []const u8 = "kw_bool"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_noreturn => { var s: []const u8 = "kw_noreturn"; dh.copyStr(buf, &idx, s); },
        TokenKind.kw_c_char => { var s: []const u8 = "kw_c_char"; dh.copyStr(buf, &idx, s); },
        TokenKind.eof => { var s: []const u8 = "eof"; dh.copyStr(buf, &idx, s); },
        TokenKind.err_token => { var s: []const u8 = "err_token"; dh.copyStr(buf, &idx, s); },
    }
    buf[idx] = 0;
    return buf[0..idx];
}
