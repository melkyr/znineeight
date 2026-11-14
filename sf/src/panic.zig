const pal = @import("pal.zig");
const itoa_mod = @import("util/itoa.zig");

pub fn panicHandler(msg: []const u8, file: []const u8, line: u32) void {
    var ice: []const u8 = "ICE: ";
    pal.stderr_write(ice);
    pal.stderr_write(msg);
    var at: []const u8 = " at ";
    pal.stderr_write(at);
    pal.stderr_write(file);
    var colon: []const u8 = ":";
    pal.stderr_write(colon);
    var buf: [16]u8 = undefined;
    var len = itoa_mod.itoa(line, buf[0..]);
    var start: usize = @intCast(usize, 15) - @intCast(usize, len);
    var end: usize = @intCast(usize, 15);
    pal.stderr_write(buf[start..end]);
    var nl: []const u8 = "\n";
    pal.stderr_write(nl);
    pal.exit(3);
}
