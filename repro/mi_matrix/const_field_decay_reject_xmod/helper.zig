// Helper module for const_field_decay_reject_xmod (FX11, Volume II).
//
// Cross-module materialisation targets for a const aggregate's array field:
// every parameter is MUTABLE, so passing the field's slice / many-pointer /
// element pointer is the field-bound const discard.
const S = struct { a: [3]i32 };
const garr = [3]i32{ 4, 5, 6 };
pub const gs: S = .{ .a = garr };

pub fn takeSlice(s: []i32) void {
    s[0] = 9;
}

pub fn takeMany(p: [*]i32) void {
    p[0] = 9;
}

pub fn takeElemPtr(p: *i32) void {
    p.* = 9;
}
