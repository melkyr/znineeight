pub fn markerWrite(msg: []const u8) void {
    var i: usize = 0;
    while (i < msg.len) : (i += 1) {
        _ = msg[i];
    }
}

pub fn markerWriteInt(prefix: []const u8, value: u32) void {
    _ = prefix;
    _ = value;
}
