pub const Inst = union(enum) {
    store: struct { ptr: u32, value: u32 },
    load: struct { ptr: u32, result: u32 },
};

pub fn makeInst() Inst {
    return .{ .store = .{ .ptr = 0, .value = 0 } };
}
