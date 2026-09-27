// D6 FX3 conversion: the former f32-param residual is now the value-aware
// positive path — `takeF32(1.5)` was `error[3000]` before FX3, and a typed
// comptime-known f64 / comptime-known integer now narrows exactly like Zig
// 0.15.2. The full accept/reject matrix is pinned by
// `repro/mi_matrix/stdlib_f32_narrow_ok_xmod` (golden) and
// `repro/mi_matrix/f32_narrow_reject_xmod` (census).
const std = @import("std");

fn takeF32(x: f32) void {
    std.io.print("x={}\n", .{x});
}

pub fn main() void {
    takeF32(1.5);
    takeF32(2);
    const d: f64 = 2.5;
    takeF32(d);
    const c: i32 = 2;
    takeF32(c);
}
