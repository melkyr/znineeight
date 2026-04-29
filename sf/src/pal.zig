extern fn write(fd: i32, buf: [*]const u8, count: i32) i32;

var saved_argc: i32 = 0;
var saved_argv: [*]*const u8 = undefined;

pub fn initArgs(argc: i32, argv: [*]*const u8) void {
    saved_argc = argc;
    saved_argv = argv;
}

pub fn stderr_write(msg: []const u8) void {
    _ = write(2, msg.ptr, @intCast(i32, msg.len));
}

pub fn argCount() i32 {
    return saved_argc;
}

pub fn argGet(i: i32) [*]const u8 {
    return saved_argv[@intCast(usize, i)];
}

pub fn exit(code: u8) void {
    _ = code;
    while (true) {}
}
