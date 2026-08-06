@cInclude("<stdio.h>");
extern fn printf(fmt: [*]const u8, a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32, j: i32, k: i32, l: i32) i32;

const X: u64 = 3000000000 * 2;
const Y: u32 = 3000000000;
const Z: u64 = 4294967295 + 1;

pub fn main() void {
    var fmt: [*]const u8 = "%u:%u %u %u:%u\n";
    var x_hi: i32 = @intCast(i32, @intCast(u64, X) >> 32);
    var x_lo: i32 = @intCast(i32, @intCast(u64, X) & @intCast(u64, 4294967295));
    var z_hi: i32 = @intCast(i32, @intCast(u64, Z) >> 32);
    var z_lo: i32 = @intCast(i32, @intCast(u64, Z) & @intCast(u64, 4294967295));
    _ = printf(fmt, x_hi, x_lo, Y, z_hi, z_lo);
}
