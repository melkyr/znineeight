// enum_init_cast_range_reject_xmod — Task 11J fix round 1 (AMENDMENT 13)
// negative control: an out-of-range `@as`/`@intCast` value is a clean reject.
//
// `@as(u8, 300)` does not fit u8 (official Zig rejects it), and `@intCast(u8,
// 300)` is likewise out of range. The enum initializer fold now range-checks
// the folded value against the target integer type's width/signedness and emits
// the dedicated hard error otherwise. Before the fix each folded 300 and, in a
// `u32`-backed enum, silently compiled (`A = 300`).
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: enum member value is not a comptime-known integer expression.
const EAs = enum(u32) { A = @as(u8, 300) };
const ECast = enum(u32) { A = @intCast(u8, 300) };
const ENeg = enum(u32) { A = @intCast(u32, -1) };

pub fn main() void {
    _ = EAs.A;
    _ = ECast.A;
    _ = ENeg.A;
}
