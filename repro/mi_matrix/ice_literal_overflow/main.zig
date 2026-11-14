@cInclude("<stdio.h>");
extern fn printf(fmt: [*]const u8, a: i32, b: i32, c: i32, d: i32, e: i32, f: i32, g: i32, h: i32, i: i32, j: i32, k: i32, l: i32) i32;

pub const X: u64 = 5000000000;
pub const Y: u64 = 4294967296;

pub fn main() void {
    var sink: u64 = 5000000000;
    var fmt: [*]const u8 = "%u:%u %u:%u\n";
    var x_hi: i32 = @intCast(i32, @intCast(u64, X) >> 32);
    var x_lo: i32 = @intCast(i32, @intCast(u64, X) & @intCast(u64, 4294967295));
    var y_hi: i32 = @intCast(i32, @intCast(u64, Y) >> 32);
    var y_lo: i32 = @intCast(i32, @intCast(u64, Y) & @intCast(u64, 4294967295));
    _ = printf(fmt, x_hi, x_lo, y_hi, y_lo);
    _ = sink;
}
