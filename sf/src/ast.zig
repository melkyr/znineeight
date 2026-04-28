pub const AstKind = enum(u8) {
    err,
    var_decl,
    fn_decl,
    struct_decl,
    enum_decl,
    union_decl,
    field_decl,
    param_decl,
    test_decl,
    int_literal,
    float_literal,
    string_literal,
    char_literal,
    bool_literal,
    null_literal,
    undefined_literal,
    unreachable_expr,
    enum_literal,
    error_literal,
    tuple_literal,
    struct_init,
    field_init,
    ident_expr,
    field_access,
    index_access,
    slice_expr,
    deref,
    address_of,
    fn_call,
    builtin_call,
    add, sub, mul, div, mod_op,
    bit_and, bit_or, bit_xor, shl, shr,
    bool_and, bool_or,
    cmp_eq, cmp_ne, cmp_lt, cmp_le, cmp_gt, cmp_ge,
    assign, add_assign, sub_assign, mul_assign, div_assign, mod_assign,
    shl_assign, shr_assign, and_assign, xor_assign, or_assign,
    negate, bool_not,
    try_expr,
    catch_expr,
    orelse_expr,
    if_stmt,
    if_expr,
    if_capture,
    while_stmt,
    while_capture,
    for_stmt,
    switch_expr,
    switch_prong,
    block,
    return_stmt,
    break_stmt,
    continue_stmt,
    defer_stmt,
    errdefer_stmt,
    ptr_type,
    many_ptr_type,
    array_type,
    slice_type,
    optional_type,
    error_union_type,
    fn_type,
    error_set_decl,
    import_expr,
    module_root,
    payload_capture,
    range_exclusive,
    range_inclusive,
    labeled_stmt,
};

pub const AstNode = packed struct {
    kind: AstKind,
    flags: u8,
    span_start: u32,
    span_end: u32,
    child_0: u32,
    child_1: u32,
    child_2: u32,
    payload: u32,
};

pub const FnProto = struct {
    name_id: u32,
    params_start: u16,
    params_count: u16,
    return_type_node: u32,
};

pub const AstStore = struct {
    nodes: std.ArrayList(AstNode),
    extra_children: std.ArrayList(u32),
    identifiers: std.ArrayList(u32),
    int_values: std.ArrayList(u64),
    float_values: std.ArrayList(f64),
    string_values: std.ArrayList(u32),
    fn_protos: std.ArrayList(FnProto),
    allocator: *Allocator,

    pub fn init(allocator: *Allocator) AstStore {}
    pub fn addNode(self: *AstStore, kind: AstKind, flags: u8, span_start: u32, span_end: u32) !u32 {}
    pub fn addExtraChildren(self: *AstStore, children: []const u32) !u32 {}
    pub fn getExtraChildren(self: *AstStore, payload: u32) []const u32 {}
    pub fn addIntLiteral(self: *AstStore, value: u64) !u32 {}
    pub fn addFloatLiteral(self: *AstStore, value: f64) !u32 {}
    pub fn addIdentifier(self: *AstStore, name_id: u32) !u32 {}
};

pub fn nodeHasExtraChildren(kind: AstKind) bool {}

const std = @import("std");
const Allocator = @import("allocator.zig").Allocator;
