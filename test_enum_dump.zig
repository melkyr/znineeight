const AK = enum(u8) {
    err, var_decl, fn_decl, struct_decl, enum_decl, union_decl,
    field_decl, param_decl, test_decl, error_set_decl,
    int_literal, float_literal, string_literal, char_literal, bool_literal,
    null_literal, undefined_literal, unreachable_expr, enum_literal, error_literal,
    tuple_literal, struct_init, array_init, field_init, ident_expr, field_access,
    index_access, slice_expr, deref, address_of, fn_call, builtin_call,
    paren_expr, add, sub, mul, div, mod_op, bit_and, bit_or, bit_xor,
    shl, shr,
    bool_and, bool_or,
    cmp_eq, cmp_ne, cmp_lt, cmp_le, cmp_gt, cmp_ge,
    assign, add_assign, sub_assign, mul_assign, div_assign, mod_assign,
    shl_assign, shr_assign, and_assign, xor_assign, or_assign,
    negate, bool_not, bit_not, try_expr, catch_expr, orelse_expr,
    if_stmt, if_expr, if_capture, while_stmt, while_capture, for_stmt,
    switch_expr, switch_prong, block, return_stmt, break_stmt, continue_stmt,
    defer_stmt, errdefer_stmt, labeled_stmt, expr_stmt, ptr_type, many_ptr_type,
    array_type, slice_type, optional_type, error_union_type, fn_type,
    import_expr, module_root, payload_capture, range_exclusive, range_inclusive,
};

fn main() u8 {
    var r: u8 = @enumToInt(AK.bool_and);
    r = @enumToInt(AK.bool_or);
    r = @enumToInt(AK.cmp_eq);
    r = @enumToInt(AK.cmp_ne);
    r = @enumToInt(AK.cmp_lt);
    r = @enumToInt(AK.cmp_le);
    r = @enumToInt(AK.cmp_gt);
    r = @enumToInt(AK.cmp_ge);
    return r;
}
