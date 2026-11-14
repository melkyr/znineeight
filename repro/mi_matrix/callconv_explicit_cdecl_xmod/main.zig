extern "c" fn pal_abort() void;
extern "cdecl" fn pal_print_stderr(s: [*]const u8, n: u32) void;

pub fn main() void {
    var msg: []const u8 = "callconv explicit cdecl\n";
    pal_print_stderr(msg.ptr, @intCast(u32, msg.len));
}
