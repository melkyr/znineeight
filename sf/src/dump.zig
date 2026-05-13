const pal = @import("pal.zig");
const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const TokenKind = @import("token.zig").TokenKind;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const ast_mod = @import("ast.zig");
const AstKind = ast_mod.AstKind;
const AstNode = ast_mod.AstNode;
const AstStore = ast_mod.AstStore;
const FnProto = ast_mod.FnProto;

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

fn astKindToString(kind: AstKind, buf: []u8) []u8 {
    var idx: usize = 0;
    switch (kind) {
        AstKind.err => { var s: []const u8 = "err"; copyStr(buf, &idx, s); },
        AstKind.var_decl => { var s: []const u8 = "var_decl"; copyStr(buf, &idx, s); },
        AstKind.fn_decl => { var s: []const u8 = "fn_decl"; copyStr(buf, &idx, s); },
        AstKind.struct_decl => { var s: []const u8 = "struct_decl"; copyStr(buf, &idx, s); },
        AstKind.enum_decl => { var s: []const u8 = "enum_decl"; copyStr(buf, &idx, s); },
        AstKind.union_decl => { var s: []const u8 = "union_decl"; copyStr(buf, &idx, s); },
        AstKind.field_decl => { var s: []const u8 = "field_decl"; copyStr(buf, &idx, s); },
        AstKind.param_decl => { var s: []const u8 = "param_decl"; copyStr(buf, &idx, s); },
        AstKind.test_decl => { var s: []const u8 = "test_decl"; copyStr(buf, &idx, s); },
        AstKind.error_set_decl => { var s: []const u8 = "error_set_decl"; copyStr(buf, &idx, s); },
        AstKind.int_literal => { var s: []const u8 = "int_literal"; copyStr(buf, &idx, s); },
        AstKind.float_literal => { var s: []const u8 = "float_literal"; copyStr(buf, &idx, s); },
        AstKind.string_literal => { var s: []const u8 = "string_literal"; copyStr(buf, &idx, s); },
        AstKind.char_literal => { var s: []const u8 = "char_literal"; copyStr(buf, &idx, s); },
        AstKind.bool_literal => { var s: []const u8 = "bool_literal"; copyStr(buf, &idx, s); },
        AstKind.null_literal => { var s: []const u8 = "null_literal"; copyStr(buf, &idx, s); },
        AstKind.undefined_literal => { var s: []const u8 = "undefined_literal"; copyStr(buf, &idx, s); },
        AstKind.unreachable_expr => { var s: []const u8 = "unreachable_expr"; copyStr(buf, &idx, s); },
        AstKind.enum_literal => { var s: []const u8 = "enum_literal"; copyStr(buf, &idx, s); },
        AstKind.error_literal => { var s: []const u8 = "error_literal"; copyStr(buf, &idx, s); },
        AstKind.tuple_literal => { var s: []const u8 = "tuple_literal"; copyStr(buf, &idx, s); },
        AstKind.struct_init => { var s: []const u8 = "struct_init"; copyStr(buf, &idx, s); },
        AstKind.array_init => { var s: []const u8 = "array_init"; copyStr(buf, &idx, s); },
        AstKind.field_init => { var s: []const u8 = "field_init"; copyStr(buf, &idx, s); },
        AstKind.ident_expr => { var s: []const u8 = "ident_expr"; copyStr(buf, &idx, s); },
        AstKind.field_access => { var s: []const u8 = "field_access"; copyStr(buf, &idx, s); },
        AstKind.index_access => { var s: []const u8 = "index_access"; copyStr(buf, &idx, s); },
        AstKind.slice_expr => { var s: []const u8 = "slice_expr"; copyStr(buf, &idx, s); },
        AstKind.deref => { var s: []const u8 = "deref"; copyStr(buf, &idx, s); },
        AstKind.address_of => { var s: []const u8 = "address_of"; copyStr(buf, &idx, s); },
        AstKind.fn_call => { var s: []const u8 = "fn_call"; copyStr(buf, &idx, s); },
        AstKind.builtin_call => { var s: []const u8 = "builtin_call"; copyStr(buf, &idx, s); },
        AstKind.paren_expr => { var s: []const u8 = "paren_expr"; copyStr(buf, &idx, s); },
        AstKind.add => { var s: []const u8 = "add"; copyStr(buf, &idx, s); },
        AstKind.sub => { var s: []const u8 = "sub"; copyStr(buf, &idx, s); },
        AstKind.mul => { var s: []const u8 = "mul"; copyStr(buf, &idx, s); },
        AstKind.div => { var s: []const u8 = "div"; copyStr(buf, &idx, s); },
        AstKind.mod_op => { var s: []const u8 = "mod_op"; copyStr(buf, &idx, s); },
        AstKind.bit_and => { var s: []const u8 = "bit_and"; copyStr(buf, &idx, s); },
        AstKind.bit_or => { var s: []const u8 = "bit_or"; copyStr(buf, &idx, s); },
        AstKind.bit_xor => { var s: []const u8 = "bit_xor"; copyStr(buf, &idx, s); },
        AstKind.shl => { var s: []const u8 = "shl"; copyStr(buf, &idx, s); },
        AstKind.shr => { var s: []const u8 = "shr"; copyStr(buf, &idx, s); },
        AstKind.bool_and => { var s: []const u8 = "bool_and"; copyStr(buf, &idx, s); },
        AstKind.bool_or => { var s: []const u8 = "bool_or"; copyStr(buf, &idx, s); },
        AstKind.cmp_eq => { var s: []const u8 = "cmp_eq"; copyStr(buf, &idx, s); },
        AstKind.cmp_ne => { var s: []const u8 = "cmp_ne"; copyStr(buf, &idx, s); },
        AstKind.cmp_lt => { var s: []const u8 = "cmp_lt"; copyStr(buf, &idx, s); },
        AstKind.cmp_le => { var s: []const u8 = "cmp_le"; copyStr(buf, &idx, s); },
        AstKind.cmp_gt => { var s: []const u8 = "cmp_gt"; copyStr(buf, &idx, s); },
        AstKind.cmp_ge => { var s: []const u8 = "cmp_ge"; copyStr(buf, &idx, s); },
        AstKind.assign => { var s: []const u8 = "assign"; copyStr(buf, &idx, s); },
        AstKind.add_assign => { var s: []const u8 = "add_assign"; copyStr(buf, &idx, s); },
        AstKind.sub_assign => { var s: []const u8 = "sub_assign"; copyStr(buf, &idx, s); },
        AstKind.mul_assign => { var s: []const u8 = "mul_assign"; copyStr(buf, &idx, s); },
        AstKind.div_assign => { var s: []const u8 = "div_assign"; copyStr(buf, &idx, s); },
        AstKind.mod_assign => { var s: []const u8 = "mod_assign"; copyStr(buf, &idx, s); },
        AstKind.shl_assign => { var s: []const u8 = "shl_assign"; copyStr(buf, &idx, s); },
        AstKind.shr_assign => { var s: []const u8 = "shr_assign"; copyStr(buf, &idx, s); },
        AstKind.and_assign => { var s: []const u8 = "and_assign"; copyStr(buf, &idx, s); },
        AstKind.xor_assign => { var s: []const u8 = "xor_assign"; copyStr(buf, &idx, s); },
        AstKind.or_assign => { var s: []const u8 = "or_assign"; copyStr(buf, &idx, s); },
        AstKind.negate => { var s: []const u8 = "negate"; copyStr(buf, &idx, s); },
        AstKind.bool_not => { var s: []const u8 = "bool_not"; copyStr(buf, &idx, s); },
        AstKind.bit_not => { var s: []const u8 = "bit_not"; copyStr(buf, &idx, s); },
        AstKind.try_expr => { var s: []const u8 = "try_expr"; copyStr(buf, &idx, s); },
        AstKind.catch_expr => { var s: []const u8 = "catch_expr"; copyStr(buf, &idx, s); },
        AstKind.orelse_expr => { var s: []const u8 = "orelse_expr"; copyStr(buf, &idx, s); },
        AstKind.if_stmt => { var s: []const u8 = "if_stmt"; copyStr(buf, &idx, s); },
        AstKind.if_expr => { var s: []const u8 = "if_expr"; copyStr(buf, &idx, s); },
        AstKind.if_capture => { var s: []const u8 = "if_capture"; copyStr(buf, &idx, s); },
        AstKind.while_stmt => { var s: []const u8 = "while_stmt"; copyStr(buf, &idx, s); },
        AstKind.while_capture => { var s: []const u8 = "while_capture"; copyStr(buf, &idx, s); },
        AstKind.for_stmt => { var s: []const u8 = "for_stmt"; copyStr(buf, &idx, s); },
        AstKind.switch_expr => { var s: []const u8 = "switch_expr"; copyStr(buf, &idx, s); },
        AstKind.switch_prong => { var s: []const u8 = "switch_prong"; copyStr(buf, &idx, s); },
        AstKind.block => { var s: []const u8 = "block"; copyStr(buf, &idx, s); },
        AstKind.return_stmt => { var s: []const u8 = "return_stmt"; copyStr(buf, &idx, s); },
        AstKind.break_stmt => { var s: []const u8 = "break_stmt"; copyStr(buf, &idx, s); },
        AstKind.continue_stmt => { var s: []const u8 = "continue_stmt"; copyStr(buf, &idx, s); },
        AstKind.defer_stmt => { var s: []const u8 = "defer_stmt"; copyStr(buf, &idx, s); },
        AstKind.errdefer_stmt => { var s: []const u8 = "errdefer_stmt"; copyStr(buf, &idx, s); },
        AstKind.labeled_stmt => { var s: []const u8 = "labeled_stmt"; copyStr(buf, &idx, s); },
        AstKind.expr_stmt => { var s: []const u8 = "expr_stmt"; copyStr(buf, &idx, s); },
        AstKind.ptr_type => { var s: []const u8 = "ptr_type"; copyStr(buf, &idx, s); },
        AstKind.many_ptr_type => { var s: []const u8 = "many_ptr_type"; copyStr(buf, &idx, s); },
        AstKind.array_type => { var s: []const u8 = "array_type"; copyStr(buf, &idx, s); },
        AstKind.slice_type => { var s: []const u8 = "slice_type"; copyStr(buf, &idx, s); },
        AstKind.optional_type => { var s: []const u8 = "optional_type"; copyStr(buf, &idx, s); },
        AstKind.error_union_type => { var s: []const u8 = "error_union_type"; copyStr(buf, &idx, s); },
        AstKind.fn_type => { var s: []const u8 = "fn_type"; copyStr(buf, &idx, s); },
        AstKind.import_expr => { var s: []const u8 = "import_expr"; copyStr(buf, &idx, s); },
        AstKind.module_root => { var s: []const u8 = "module_root"; copyStr(buf, &idx, s); },
        AstKind.payload_capture => { var s: []const u8 = "payload_capture"; copyStr(buf, &idx, s); },
        AstKind.range_exclusive => { var s: []const u8 = "range_exclusive"; copyStr(buf, &idx, s); },
        AstKind.range_inclusive => { var s: []const u8 = "range_inclusive"; copyStr(buf, &idx, s); },
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

fn nodeGetNameId(store: *AstStore, node: AstNode) u32 {
    switch (node.kind) {
        AstKind.var_decl => { return node.payload; },
        AstKind.field_decl => { return node.payload; },
        AstKind.param_decl => { return node.payload; },
        AstKind.field_access => { return node.payload; },
        AstKind.enum_literal => { return node.payload; },
        AstKind.error_literal => { return node.payload; },
        AstKind.labeled_stmt => { return node.payload; },
        AstKind.break_stmt => { return node.payload; },
        AstKind.continue_stmt => { return node.payload; },
        AstKind.if_capture => { return node.payload; },
        AstKind.while_capture => { return node.payload; },
        AstKind.builtin_call => { return node.payload; },
        AstKind.import_expr => { return node.payload; },
        AstKind.fn_decl => {
            if (@intCast(usize, node.payload) < store.fn_protos.len) {
                return store.fn_protos.items[node.payload].name_id;
            }
            return @intCast(u32, 0);
        },
        else => { return @intCast(u32, 0); },
    }
}

pub fn dumpAst(store: *AstStore, root: u32, interner: *StringInterner) void {
    var st_idx: [512]u32 = undefined;
    var st_indent: [512]u32 = undefined;
    var st_state: [512]u8 = undefined;
    var sp: usize = 0;
    var s2: []const u8 = "  ";
    var spc: []const u8 = " ";
    var nl: []const u8 = "\n";
    var q: []const u8 = "\"";
    var op: []const u8 = "(";
    var cp: []const u8 = ")";
    var kind_buf: [32]u8 = undefined;
    var fmt_buf: [32]u8 = undefined;

    st_idx[sp] = root; st_indent[sp] = 0; st_state[sp] = 0; sp += 1;

    while (sp > 0) {
        sp -= 1;
        var idx = st_idx[sp];
        var indent = st_indent[sp];
        var is_post = st_state[sp];
        var node = store.nodes.items[idx];

        if (is_post != 0) {
            var ii: u32 = 0;
            while (ii < indent) { pal.stdout_write(s2); ii += 1; }
            pal.stdout_write(cp);
            pal.stdout_write(nl);
        } else {
            var ii: u32 = 0;
            while (ii < indent) { pal.stdout_write(s2); ii += 1; }
            var ks = astKindToString(node.kind, kind_buf[0..]);
            pal.stdout_write(op);
            pal.stdout_write(ks);

            var name_id = nodeGetNameId(store, node);
            if (name_id != 0) {
                pal.stdout_write(spc);
                pal.stdout_write(q);
                var name = interner_mod.stringInternerGet(interner, name_id);
                pal.stdout_write(name);
                pal.stdout_write(q);
            } else if (node.kind == AstKind.int_literal or node.kind == AstKind.char_literal) {
                if (@intCast(usize, node.payload) < store.int_values.len) {
                    var val = store.int_values.items[node.payload];
                    pal.stdout_write(spc);
                    var fs = formatU64(val, fmt_buf[0..], 32);
                    pal.stdout_write(fs);
                }
            } else if (node.kind == AstKind.float_literal) {
                if (@intCast(usize, node.payload) < store.float_values.len) {
                    var val = store.float_values.items[node.payload];
                    pal.stdout_write(spc);
                    var fs = formatF64(val, fmt_buf[0..], 32);
                    pal.stdout_write(fs);
                }
            } else if (node.kind == AstKind.string_literal) {
                if (@intCast(usize, node.payload) < store.string_values.len) {
                    var str_id = store.string_values.items[node.payload];
                    pal.stdout_write(spc);
                    pal.stdout_write(q);
                    var str_val = interner_mod.stringInternerGet(interner, str_id);
                    pal.stdout_write(str_val);
                    pal.stdout_write(q);
                }
            } else if (node.kind == AstKind.ident_expr) {
                if (@intCast(usize, node.payload) < store.identifiers.len) {
                    var id_val = store.identifiers.items[@intCast(usize, node.payload)];
                    pal.stdout_write(spc);
                    pal.stdout_write(q);
                    var id_str = interner_mod.stringInternerGet(interner, id_val);
                    pal.stdout_write(id_str);
                    pal.stdout_write(q);
                }
            } else if (node.kind == AstKind.bool_literal) {
                pal.stdout_write(spc);
                if (node.child_0 != 0) {
                    var ts: []const u8 = "true";
                    pal.stdout_write(ts);
                } else {
                    var fs: []const u8 = "false";
                    pal.stdout_write(fs);
                }
            } else if (node.kind == AstKind.null_literal) {
                pal.stdout_write(spc);
                var ns: []const u8 = "null";
                pal.stdout_write(ns);
            } else if (node.kind == AstKind.undefined_literal) {
                pal.stdout_write(spc);
                var us: []const u8 = "undefined";
                pal.stdout_write(us);
            } else if (node.kind == AstKind.unreachable_expr) {
                pal.stdout_write(spc);
                var us: []const u8 = "unreachable";
                pal.stdout_write(us);
            }

            if (node.flags != 0) {
                if ((node.flags & @intCast(u8, 0x02)) != 0) {
                    var ps: []const u8 = " pub=true";
                    pal.stdout_write(ps);
                }
                if ((node.flags & @intCast(u8, 0x01)) != 0) {
                    var cs: []const u8 = " const=true";
                    pal.stdout_write(cs);
                }
                if ((node.flags & @intCast(u8, 0x04)) != 0) {
                    var es: []const u8 = " extern=true";
                    pal.stdout_write(es);
                }
                if ((node.flags & @intCast(u8, 0x80)) != 0) {
                    var ms: []const u8 = " mutable=true";
                    pal.stdout_write(ms);
                }
                if ((node.flags & @intCast(u8, 0x08)) != 0) {
                    var es2: []const u8 = " export=true";
                    pal.stdout_write(es2);
                }
            }

            var has_children: u8 = 0;
            if (node.child_0 != 0 or node.child_1 != 0 or node.child_2 != 0) {
                has_children = 1;
            } else if (ast_mod.nodeHasExtraChildren(node.kind) and node.payload != 0) {
                var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
                if (ec.len > 0) has_children = 1;
            }

            if (has_children == 0) {
                pal.stdout_write(cp);
                pal.stdout_write(nl);
            } else {
                pal.stdout_write(nl);
                st_idx[sp] = idx; st_indent[sp] = indent; st_state[sp] = 1; sp += 1;
                if (node.child_2 != 0) { st_idx[sp] = node.child_2; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                if (node.child_1 != 0) { st_idx[sp] = node.child_1; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                if (node.child_0 != 0) { st_idx[sp] = node.child_0; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                if (ast_mod.nodeHasExtraChildren(node.kind) and node.payload != 0) {
                    var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
                    var ei: usize = 0;
                    while (ei < ec.len) {
                        var c = ec[ec.len - 1 - ei];
                        if (c != 0) { st_idx[sp] = c; st_indent[sp] = indent + 1; st_state[sp] = 0; sp += 1; }
                        ei += 1;
                    }
                }
            }
        }
    }
}
