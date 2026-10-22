// const_rodata_gate/value_shapes.zig — M2 T1C-F nm-gate probe (value shapes).
//
// Every `const` here must land in read-only data (`nm` `R`/`r`) — never
// `B`/`b`/`C` — and must not be stored from `__module_init`. Address-bearing
// consts (slices/pointers) may sit in a relocation section (`R`/`r`/`D`/`d`)
// but never `.bss`. Consumed by scripts/compiler/gate_const_rodata.sh.
const std = @import("std");

const Pair = struct { a: i32, b: i32 };
const U1 = union { a: u32, b: u8 };
const Nested = struct { t: [2]u32 };

const vs_scalar: u32 = 7;
const vs_neg: i32 = -3;
const vs_expr: u32 = 3 + 4;
const vs_float: f64 = 1.5;
const vs_bool: bool = true;
const vs_arr1d = [4]u32{ 1, 2, 3, 4 };
const vs_arr2d = [2][2]u32{ [2]u32{ 1, 2 }, [2]u32{ 3, 4 } };
const vs_struc = Pair{ .a = 1, .b = 2 };
const vs_tup: struct { u32, u32 } = .{ 5, 6 };
const vs_union = U1{ .a = 9 };
const vs_nested = Nested{ .t = [2]u32{ 8, 9 } };
const vs_slice: []const u8 = "xy";
const vs_many: [*]const u8 = "zw";
const vs_parr: []const u32 = vs_arr1d;

pub fn main() void {
    var acc: u32 = vs_scalar + vs_expr + vs_arr1d[0] + vs_arr2d[1][1] + vs_struc.a + vs_tup.0 + vs_union.a + vs_nested.t[1] + @intCast(u32, -vs_neg) + @intCast(u32, vs_slice[0]) + @intCast(u32, vs_many[1]) + @intCast(u32, vs_parr[2]);
    if (vs_bool) acc += 1;
    if (vs_float == 1.5) acc += 1;
    std.io.print("{d}\n", .{acc});
}
