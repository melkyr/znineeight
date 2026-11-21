// Helper module for stdlib_const_field_decay_ok_xmod (FX11, Volume II).
//
// Cross-module const-adding directions for an aggregate's array field: the
// exported `gs` is a module-level `const S`, and every consumer takes the
// const forms (`[]const`/`[*]const`/`*const [3]`) or a mutable slice/many for
// the mutable case. A const-adding call argument is `gs.a[0..]` / `&gs.a`.
const S = struct { a: [3]i32 };
const garr = [3]i32{ 4, 5, 6 };
pub const gs: S = .{ .a = garr };

pub fn sumConst(s: []const i32) i32 {
    return s[0] + s[1] + s[2];
}

pub fn sumConstMany(p: [*]const i32) i32 {
    return p[0] + p[1] + p[2];
}

pub fn retConstField(p: *const [3]i32) []const i32 {
    return p[0..];
}

pub fn bumpMut(s: []i32) void {
    s[0] = s[0] + 1;
}
