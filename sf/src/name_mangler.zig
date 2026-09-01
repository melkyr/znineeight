pub const NameMangler = struct {
    counter: u32,
};

pub fn nameManglerInit() NameMangler {
    return NameMangler{ .counter = @intCast(u32, 0) };
}
