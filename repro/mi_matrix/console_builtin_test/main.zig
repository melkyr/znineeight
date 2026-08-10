const std = @import("std.zig");

pub fn main() void {
    @consoleClear();
    @consoleGotoxy(5, 3);
    @consoleSetColor(32, 40);
    if (@isWindows()) {
        @stdoutWrite("WINBRANCH", 9);
    } else {
        @stdoutWrite("POSIXBRANCH", 11);
    }
    std.io.printInt(@intCast(i32, @isWindows()));
    @exit(@intCast(u8, 0));
}
