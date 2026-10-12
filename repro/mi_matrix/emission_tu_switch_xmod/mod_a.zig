pub const U = union(enum) {
    jump: u32,
    ret: void,
};

pub fn make_jump() U {
    return U{ .jump = @intCast(u32, 42) };
}

pub fn make_ret() U {
    return U{ .ret = {} };
}
