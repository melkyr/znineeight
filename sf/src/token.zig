const mem_mod = @import("util/mem.zig");
const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");

pub const TokenKind = enum(u16) {
    integer_literal,
    float_literal,
    string_literal,
    char_literal,
    identifier,
    builtin_identifier,
    lparen,
    rparen,
    lbracket,
    rbracket,
    lbrace,
    rbrace,
    semicolon,
    colon,
    comma,
    dot,
    at_sign,
    underscore,
    question_mark,
    bang,
    plus,
    minus,
    star,
    slash,
    percent,
    ampersand,
    pipe,
    caret,
    tilde,
    shl,
    shr,
    eq_eq,
    bang_eq,
    less,
    less_eq,
    greater,
    greater_eq,
    eq,
    plus_eq,
    minus_eq,
    star_eq,
    slash_eq,
    percent_eq,
    ampersand_eq,
    pipe_eq,
    caret_eq,
    shl_eq,
    shr_eq,
    dot_dot,
    dot_dot_dot,
    dot_lbrace,
    dot_star,
    fat_arrow,
    kw_const,
    kw_var,
    kw_fn,
    kw_pub,
    kw_extern,
    kw_export,
    kw_test,
    kw_struct,
    kw_enum,
    kw_union,
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
    kw_try,
    kw_catch,
    kw_orelse,
    kw_error,
    kw_and,
    kw_or,
    kw_true,
    kw_false,
    kw_null,
    kw_undefined,
    kw_unreachable,
    kw_void,
    kw_bool,
    kw_noreturn,
    kw_c_char,
    kw_anytype,
    eof,
    err_token,            // unrecognized character (error recovery)
};

pub const SyncContext = enum(u8) {
    stmt_list,      // ;, }, kw_fn, kw_const, kw_var, kw_pub, eof
    expression,     // ), ], }, ,, ;, eof
    switch_prong,   // =>, ,, }, else, eof
    fn_body,        // }, eof
    module_root,    // kw_fn, kw_const, kw_var, kw_test, eof
};

pub const TokenValue = union {
    int_val: u64,
    float_val: f64,
    string_id: u32,
    none: void,
};

// FIXME: Desired packed layout (16 bytes) rejected by zig0 for structs with union fields.
// Actual size: 24 bytes (TokenValue union forces 8-byte alignment).
// Restore packed struct once zig1 can self-host.
pub const Token = struct {
    kind: TokenKind,
    span_start: u32,
    span_len: u16,
    value: TokenValue,
};

pub const KeywordEntry = struct {
    name: []const u8,
    kind: TokenKind,
};

pub var keyword_table: []KeywordEntry = undefined;
pub var keyword_count: usize = 0;

pub fn initKeywordTable(alloc: *Sand) void {
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, 12) * @intCast(usize, 36), @intCast(usize, 4)) catch unreachable;
    var table = @ptrCast([*]KeywordEntry, raw);
    var i: usize = 0;
    var s_const: []const u8 = "const"; table[i] = KeywordEntry{ .name = s_const, .kind = TokenKind.kw_const }; i += 1;
    var s_var: []const u8 = "var"; table[i] = KeywordEntry{ .name = s_var, .kind = TokenKind.kw_var }; i += 1;
    var s_fn: []const u8 = "fn"; table[i] = KeywordEntry{ .name = s_fn, .kind = TokenKind.kw_fn }; i += 1;
    var s_pub: []const u8 = "pub"; table[i] = KeywordEntry{ .name = s_pub, .kind = TokenKind.kw_pub }; i += 1;
    var s_extern: []const u8 = "extern"; table[i] = KeywordEntry{ .name = s_extern, .kind = TokenKind.kw_extern }; i += 1;
    var s_export: []const u8 = "export"; table[i] = KeywordEntry{ .name = s_export, .kind = TokenKind.kw_export }; i += 1;
    var s_test: []const u8 = "test"; table[i] = KeywordEntry{ .name = s_test, .kind = TokenKind.kw_test }; i += 1;
    var s_struct: []const u8 = "struct"; table[i] = KeywordEntry{ .name = s_struct, .kind = TokenKind.kw_struct }; i += 1;
    var s_enum: []const u8 = "enum"; table[i] = KeywordEntry{ .name = s_enum, .kind = TokenKind.kw_enum }; i += 1;
    var s_union: []const u8 = "union"; table[i] = KeywordEntry{ .name = s_union, .kind = TokenKind.kw_union }; i += 1;
    var s_if: []const u8 = "if"; table[i] = KeywordEntry{ .name = s_if, .kind = TokenKind.kw_if }; i += 1;
    var s_else: []const u8 = "else"; table[i] = KeywordEntry{ .name = s_else, .kind = TokenKind.kw_else }; i += 1;
    var s_while: []const u8 = "while"; table[i] = KeywordEntry{ .name = s_while, .kind = TokenKind.kw_while }; i += 1;
    var s_for: []const u8 = "for"; table[i] = KeywordEntry{ .name = s_for, .kind = TokenKind.kw_for }; i += 1;
    var s_switch: []const u8 = "switch"; table[i] = KeywordEntry{ .name = s_switch, .kind = TokenKind.kw_switch }; i += 1;
    var s_return: []const u8 = "return"; table[i] = KeywordEntry{ .name = s_return, .kind = TokenKind.kw_return }; i += 1;
    var s_break: []const u8 = "break"; table[i] = KeywordEntry{ .name = s_break, .kind = TokenKind.kw_break }; i += 1;
    var s_continue: []const u8 = "continue"; table[i] = KeywordEntry{ .name = s_continue, .kind = TokenKind.kw_continue }; i += 1;
    var s_defer: []const u8 = "defer"; table[i] = KeywordEntry{ .name = s_defer, .kind = TokenKind.kw_defer }; i += 1;
    var s_errdefer: []const u8 = "errdefer"; table[i] = KeywordEntry{ .name = s_errdefer, .kind = TokenKind.kw_errdefer }; i += 1;
    var s_try: []const u8 = "try"; table[i] = KeywordEntry{ .name = s_try, .kind = TokenKind.kw_try }; i += 1;
    var s_catch: []const u8 = "catch"; table[i] = KeywordEntry{ .name = s_catch, .kind = TokenKind.kw_catch }; i += 1;
    var s_orelse: []const u8 = "orelse"; table[i] = KeywordEntry{ .name = s_orelse, .kind = TokenKind.kw_orelse }; i += 1;
    var s_error: []const u8 = "error"; table[i] = KeywordEntry{ .name = s_error, .kind = TokenKind.kw_error }; i += 1;
    var s_and: []const u8 = "and"; table[i] = KeywordEntry{ .name = s_and, .kind = TokenKind.kw_and }; i += 1;
    var s_or: []const u8 = "or"; table[i] = KeywordEntry{ .name = s_or, .kind = TokenKind.kw_or }; i += 1;
    var s_true: []const u8 = "true"; table[i] = KeywordEntry{ .name = s_true, .kind = TokenKind.kw_true }; i += 1;
    var s_false: []const u8 = "false"; table[i] = KeywordEntry{ .name = s_false, .kind = TokenKind.kw_false }; i += 1;
    var s_null: []const u8 = "null"; table[i] = KeywordEntry{ .name = s_null, .kind = TokenKind.kw_null }; i += 1;
    var s_undefined: []const u8 = "undefined"; table[i] = KeywordEntry{ .name = s_undefined, .kind = TokenKind.kw_undefined }; i += 1;
    var s_unreachable: []const u8 = "unreachable"; table[i] = KeywordEntry{ .name = s_unreachable, .kind = TokenKind.kw_unreachable }; i += 1;
    var s_void: []const u8 = "void"; table[i] = KeywordEntry{ .name = s_void, .kind = TokenKind.kw_void }; i += 1;
    var s_bool: []const u8 = "bool"; table[i] = KeywordEntry{ .name = s_bool, .kind = TokenKind.kw_bool }; i += 1;
    var s_noreturn: []const u8 = "noreturn"; table[i] = KeywordEntry{ .name = s_noreturn, .kind = TokenKind.kw_noreturn }; i += 1;
    var s_c_char: []const u8 = "c_char"; table[i] = KeywordEntry{ .name = s_c_char, .kind = TokenKind.kw_c_char }; i += 1;
    var s_anytype: []const u8 = "anytype"; table[i] = KeywordEntry{ .name = s_anytype, .kind = TokenKind.kw_anytype }; i += 1;

    keyword_table = table[0..36];
    keyword_count = i;
}

pub fn lookupKeyword(text: []const u8) ?TokenKind {
    var i: usize = 0;
    while (i < keyword_count) {
        if (mem_mod.mem_eql(keyword_table[i].name, text)) return keyword_table[i].kind;
        i += 1;
    }
    return null;
}
