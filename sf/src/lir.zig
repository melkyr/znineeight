pub const SwitchCase = struct {
    value: i64,
    target_bb: u32,
};

pub const LirParam = struct {
    name_id: u32,
    type_id: TypeId,
};

pub const TempDecl = struct {
    temp_id: u32,
    type_id: TypeId,
};

pub const BasicBlock = struct {
    id: u32,
    insts: std.ArrayList(LirInst),
    is_terminated: bool,
};

pub const LirInst = union(enum) {
    decl_temp: struct { temp: u32, type_id: TypeId },
    decl_local: struct { name_id: u32, type_id: TypeId, temp: u32 },
    assign: struct { dst: u32, src: u32 },
    assign_field: struct { base: u32, field_id: u32, src: u32 },
    assign_index: struct { base: u32, index: u32, src: u32 },
    jump: u32,
    branch: struct { cond: u32, then_bb: u32, else_bb: u32 },
    switch_br: struct { cond: u32, cases_start: u32, cases_count: u32, else_bb: u32 },
    loop_header: u32,
    ret: u32,
    ret_void: void,
    label: u32,
    binary: struct { op: u8, lhs: u32, rhs: u32, result: u32 },
    unary: struct { op: u8, operand: u32, result: u32 },
    call: struct { callee: u32, args_start: u32, args_count: u32, result: u32 },
    load_field: struct { base: u32, field_id: u32, result: u32 },
    store_field: struct { base: u32, field_id: u32, value: u32 },
    load_index: struct { base: u32, index: u32, result: u32 },
    load: struct { ptr: u32, result: u32 },
    store: struct { ptr: u32, value: u32 },
    addr_of: struct { operand: u32, result: u32 },
    wrap_optional: struct { value: u32, result: u32, type_id: TypeId },
    unwrap_optional: struct { value: u32, result: u32 },
    check_optional: struct { value: u32, result: u32 },
    wrap_error_ok: struct { value: u32, result: u32, type_id: TypeId },
    wrap_error_err: struct { value: u32, result: u32, type_id: TypeId },
    unwrap_error_payload: struct { value: u32, result: u32 },
    unwrap_error_code: struct { value: u32, result: u32 },
    check_error: struct { value: u32, result: u32 },
    make_slice: struct { ptr: u32, len: u32, result: u32, type_id: TypeId },
    int_cast: struct { value: u32, target: TypeId, result: u32, is_checked: bool },
    float_cast: struct { value: u32, target: TypeId, result: u32 },
    ptr_cast: struct { value: u32, target: TypeId, result: u32 },
    int_to_float: struct { value: u32, target: TypeId, result: u32 },
    ptr_to_int: struct { value: u32, result: u32 },
    int_to_ptr: struct { value: u32, target: TypeId, result: u32 },
    int_const: struct { value: u64, result: u32 },
    float_const: struct { value: f64, result: u32 },
    string_const: struct { string_id: u32, result: u32 },
    null_const: struct { result: u32 },
    bool_const: struct { value: u8, result: u32 },
    undefined_const: struct { result: u32, type_id: TypeId },
    load_local: struct { name_id: u32, result: u32 },
    store_local: struct { name_id: u32, value: u32 },
    load_global: struct { name_id: u32, result: u32 },
    store_global: struct { name_id: u32, value: u32 },
    print_str: struct { string_id: u32 },
    print_val: struct { value: u32, type_id: TypeId, fmt: u8 },
    nop: void,
};

pub const LirFunction = struct {
    name_id: u32,
    return_type: TypeId,
    params: std.ArrayList(LirParam),
    blocks: std.ArrayList(BasicBlock),
    hoisted_temps: std.ArrayList(TempDecl),
    switch_cases: std.ArrayList(SwitchCase),
    is_extern: bool,
    is_pub: bool,
};

const std = @import("std");
const TypeId = @import("type_registry.zig").TypeId;
