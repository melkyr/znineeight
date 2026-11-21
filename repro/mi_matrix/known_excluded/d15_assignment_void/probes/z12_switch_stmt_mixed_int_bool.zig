fn f(v: u32) void {
    switch (v) { 0 => 1, else => true }
}
pub fn main() void { var v: u32 = 0; v += 1; f(v); }
