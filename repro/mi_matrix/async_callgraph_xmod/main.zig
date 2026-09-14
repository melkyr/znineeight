const lib = @import("lib.zig");

fn use_sizes() void {
    var a: u32 = @asyncFrameSize(lib.top);
    var b: u32 = @asyncFrameSize(lib.explicit_only);
    var c: u32 = @asyncFrameSize(lib.mid);
    _ = a; _ = b; _ = c;
}

pub fn main() void {
    use_sizes();
}
