pub fn stderr_write(msg: []const u8) void {
    @stderrWrite(msg.ptr, msg.len);
}
