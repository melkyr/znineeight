extern fn stderr_write(s: []const u8) void;

pub fn main() void {
    var msg: []const u8 = undefined;
    msg = "something went wrong";
    // @panic with variable fails; only @panic("literal") works
    @panic(msg);
}
