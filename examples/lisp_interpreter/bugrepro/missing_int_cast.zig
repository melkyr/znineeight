pub fn main() void {
    const x: u8 = 100;
    const y: i32 = @intCast(i32, x);
    _ = y;
}
