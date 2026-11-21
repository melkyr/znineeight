var g: i32 = 0;
fn f(v: u32) void {
    switch (v) { 0 => g = 1, else => 2 }
}
pub fn main() void { var v: u32 = 0; v += 1; f(v); }
