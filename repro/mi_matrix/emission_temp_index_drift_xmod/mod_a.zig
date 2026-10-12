pub const SwitchCase = struct {
    value: u32,
    target_bb: u32,
};

pub const Inst = union(enum) {
    switch_br: struct { cond: u32, cases_start: u32, cases_count: u32, else_bb: u32 },
    ret: u32,
    none,
};

pub fn makeSwitchBr(cond: u32, cases_count: u32, else_bb: u32) Inst {
    return .{ .switch_br = .{ .cond = cond, .cases_start = 0, .cases_count = cases_count, .else_bb = else_bb } };
}

pub fn makeCase(value: u32, target_bb: u32) SwitchCase {
    return SwitchCase{ .value = value, .target_bb = target_bb };
}
