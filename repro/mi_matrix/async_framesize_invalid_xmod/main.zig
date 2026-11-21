fn plain() void {
}

pub fn main() void {
    var s: u32 = @asyncFrameSize(plain);
    _ = s;
}
