extern fn __bootstrap_print(s: *const u8) void;

const Writer = struct {
    write_fn: fn(s: []const u8) void,
};

fn stdoutWrite(s: []const u8) void {
    __bootstrap_print(s.ptr);
}

pub fn main() void {
    var w: Writer = undefined;
    w.write_fn = stdoutWrite;
    _ = w;
}
