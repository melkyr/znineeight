pub const TypeId = u32;

pub const Inst = union(enum) {
    binary: struct { op: u8, lhs: u32, rhs: u32, result: u32 },
    call: struct { callee: u32, args_start: u32, args_count: u32, result: u32 },
    load_field: struct { base: u32, field_id: u32, result: u32, name_id: u32 },
    jump: u32,
    ret: u32,
    label: u32,
    ret_void: void,
    none,
};

pub fn makeJump(target: u32) Inst {
    return .{ .jump = target };
}
