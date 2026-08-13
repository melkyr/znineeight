pub fn doConsole() void {
    if (@isWindows()) {
        @putChar('X');
    }
}
