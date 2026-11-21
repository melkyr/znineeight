// enum_init_cast_noninteger_reject_xmod — Task 11J fix round 1 (AMENDMENT 13)
// negative control: `@as`/`@intCast` to a NON-INTEGER type is a clean reject.
//
// `@as(f32, 3)` is an f32 and `@intCast(f32, 3)` yields an f32; an enum field
// value must be the backing integer type, so official Zig rejects both. The
// enum initializer fold now requires the `@as`/`@intCast` target to resolve to
// an integer type and emits the dedicated hard error otherwise. Before the fix
// each folded its operand (3) and silently compiled.
//
// Contract: dump rc=2, 0 `.c`,
//   error[3055]: enum member value is not a comptime-known integer expression.
const EAs = enum(u32) { A = @as(f32, 3) };
const ECast = enum(u32) { A = @intCast(f32, 3) };

pub fn main() void {
    _ = EAs.A;
    _ = ECast.A;
}
