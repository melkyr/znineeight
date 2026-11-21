var g: i32 = 0;
pub fn main() void {
    var v: u32 = 0; v += 1;
    const y: void = switch (v) {
        0 => { g = 1; },
        else => {},
    };
    _ = y;
}
