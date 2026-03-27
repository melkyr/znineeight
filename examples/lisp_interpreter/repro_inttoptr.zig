pub fn main() void {
    const ptr: *void = @intToPtr(*void, 0x1234);
    _ = ptr;
}
