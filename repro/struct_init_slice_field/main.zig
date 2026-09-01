extern fn __bootstrap_print_int(i: i32) void;

const Tokenizer = struct { input: []const u8, pos: usize };

pub fn main() void {
    var src: [8]u8 = undefined;
    var i: usize = 0;
    while (i < 8) { src[i] = @intCast(u8, i + 97); i += 1; }
    const line = src[0..4];
    var t = Tokenizer{ .input = line, .pos = @intCast(usize, 0) };
    __bootstrap_print_int(@intCast(i32, t.input.len));
    __bootstrap_print_int(@intCast(i32, t.input[0]));
    __bootstrap_print_int(@intCast(i32, t.pos));
}
