fn worker(x: i32) i32 {
    var y: i32 = x;
    @asyncSuspend(null);
    y = y + 1;
    return y;
}

fn plain() i32 {
    return 7;
}

const Expected = struct {
    ctx: *void,
    state: u8,
    x: i32,
    y: i32,
};

pub fn main() void {
    var got: u32 = @asyncFrameSize(worker);
    var want: u32 = @sizeOf(Expected);
    if (got != want) {
        @panic("frame size mismatch");
    }
}
