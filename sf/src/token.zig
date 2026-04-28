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
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, 12) * @intCast(usize, 35), @intCast(usize, 4)) catch unreachable;
    var table = @ptrCast([*]KeywordEntry, raw);
    var i: usize = 0;
    table[i] = KeywordEntry{ .name = "const",       .kind = TokenKind.kw_const };       i += 1;
    table[i] = KeywordEntry{ .name = "var",         .kind = TokenKind.kw_var };         i += 1;
    table[i] = KeywordEntry{ .name = "fn",          .kind = TokenKind.kw_fn };          i += 1;
    table[i] = KeywordEntry{ .name = "pub",         .kind = TokenKind.kw_pub };         i += 1;
    table[i] = KeywordEntry{ .name = "extern",      .kind = TokenKind.kw_extern };      i += 1;
    table[i] = KeywordEntry{ .name = "export",      .kind = TokenKind.kw_export };      i += 1;
    table[i] = KeywordEntry{ .name = "test",        .kind = TokenKind.kw_test };        i += 1;
    table[i] = KeywordEntry{ .name = "struct",      .kind = TokenKind.kw_struct };      i += 1;
    table[i] = KeywordEntry{ .name = "enum",        .kind = TokenKind.kw_enum };        i += 1;
    table[i] = KeywordEntry{ .name = "union",       .kind = TokenKind.kw_union };       i += 1;
    table[i] = KeywordEntry{ .name = "if",          .kind = TokenKind.kw_if };          i += 1;
    table[i] = KeywordEntry{ .name = "else",        .kind = TokenKind.kw_else };        i += 1;
    table[i] = KeywordEntry{ .name = "while",       .kind = TokenKind.kw_while };       i += 1;
    table[i] = KeywordEntry{ .name = "for",         .kind = TokenKind.kw_for };         i += 1;
    table[i] = KeywordEntry{ .name = "switch",      .kind = TokenKind.kw_switch };      i += 1;
    table[i] = KeywordEntry{ .name = "return",      .kind = TokenKind.kw_return };      i += 1;
    table[i] = KeywordEntry{ .name = "break",       .kind = TokenKind.kw_break };       i += 1;
    table[i] = KeywordEntry{ .name = "continue",    .kind = TokenKind.kw_continue };    i += 1;
    table[i] = KeywordEntry{ .name = "defer",       .kind = TokenKind.kw_defer };       i += 1;
    table[i] = KeywordEntry{ .name = "errdefer",    .kind = TokenKind.kw_errdefer };    i += 1;
    table[i] = KeywordEntry{ .name = "try",         .kind = TokenKind.kw_try };         i += 1;
    table[i] = KeywordEntry{ .name = "catch",       .kind = TokenKind.kw_catch };       i += 1;
    table[i] = KeywordEntry{ .name = "orelse",      .kind = TokenKind.kw_orelse };      i += 1;
    table[i] = KeywordEntry{ .name = "error",       .kind = TokenKind.kw_error };       i += 1;
    table[i] = KeywordEntry{ .name = "and",         .kind = TokenKind.kw_and };         i += 1;
    table[i] = KeywordEntry{ .name = "or",          .kind = TokenKind.kw_or };          i += 1;
    table[i] = KeywordEntry{ .name = "true",        .kind = TokenKind.kw_true };        i += 1;
    table[i] = KeywordEntry{ .name = "false",       .kind = TokenKind.kw_false };       i += 1;
    table[i] = KeywordEntry{ .name = "null",        .kind = TokenKind.kw_null };        i += 1;
    table[i] = KeywordEntry{ .name = "undefined",   .kind = TokenKind.kw_undefined };   i += 1;
    table[i] = KeywordEntry{ .name = "unreachable", .kind = TokenKind.kw_unreachable }; i += 1;
    table[i] = KeywordEntry{ .name = "void",        .kind = TokenKind.kw_void };        i += 1;
    table[i] = KeywordEntry{ .name = "bool",        .kind = TokenKind.kw_bool };        i += 1;
    table[i] = KeywordEntry{ .name = "noreturn",    .kind = TokenKind.kw_noreturn };    i += 1;
    table[i] = KeywordEntry{ .name = "c_char",      .kind = TokenKind.kw_c_char };      i += 1;

    keyword_table = table[0..35];
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
