extern fn __bootstrap_print_int(n: i32) void;

pub fn main() void {
    @consoleClear();
    @consoleGotoxy(5, 3);
    @consoleSetColor(32, 40);
    if (@isWindows()) {
        @stdoutWrite("WINBRANCH", 9);
    } else {
        @stdoutWrite("POSIXBRANCH", 11);
    }
    __bootstrap_print_int(@intCast(i32, @isWindows()));
    @exit(@intCast(u8, 0));
}
