extern "c" fn plat_is_windows() bool;
extern "c" fn plat_console_putchar(c: i32) void;

pub fn doConsole() void {
    if (plat_is_windows()) {
        plat_console_putchar('X');
    }
}
