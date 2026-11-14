fn pick(v: u32) void {
    var x = switch (v) { 0 => 1, else => true };
    x = x;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
