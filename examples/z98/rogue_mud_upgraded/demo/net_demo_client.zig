const std = @import("std");
const std_net = @import("std_net");

pub fn main() void {
    const PORT: u16 = 4000;
    if (std_net.init() != 0) @exit(@intCast(u8, 1));
    const client = std_net.createTcpClient(@intCast(u16, PORT));
    if (client < 0) @exit(@intCast(u8, 2));
    const msg: []const u8 = "i";
    _ = std_net.send(client, msg.ptr, @intCast(i32, msg.len));
    // Read whatever the server streams until it closes or a short timeout elapses.
    var buf: [4096]u8 = undefined;
    var i: i32 = 0;
    while (i < 2000) : (i += 1) {
        const n = std_net.recv(client, &buf[0], 4096);
        if (n <= 0) break;
    }
    std_net.close(client);
    std_net.cleanup();
    @exit(@intCast(u8, 0));
}
