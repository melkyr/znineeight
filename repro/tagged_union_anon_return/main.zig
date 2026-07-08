extern fn __bootstrap_print_int(x: i32) void;

const Command = union(enum) {
    Quit: void,
    Go: i32,
};

fn parse(n: i32) Command {
    return .{ .Go = n };
}

pub fn main() void {
    var c: Command = parse(@intCast(i32, 5));
    var r: i32 = @intCast(i32, 0);
    switch (c) {
        .Quit => r = @intCast(i32, 0),
        .Go => |d| r = d,
    }
    __bootstrap_print_int(r);
}
