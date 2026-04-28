extern fn write(fd: i32, buf: [*]const u8, count: i32) i32;

pub fn stderr_write(msg: []const u8) void {
    _ = write(2, msg.ptr, @intCast(i32, msg.len));
}

pub fn argCount() i32 {
    return @intCast(i32, 0);
}

pub fn argGet(i: i32) [*]const u8 {
    _ = i;
    return undefined;
}

pub fn exit(code: u8) void {
    _ = code;
    while (true) {}
}
