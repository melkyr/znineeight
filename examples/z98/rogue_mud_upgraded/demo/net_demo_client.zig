const std = @import("std");
const std_net = @import("std_net");

pub fn main() void {
    const PORT: u16 = 4000;
    const client = @socketCreate(0);
    if (client < 0) @exit(@intCast(u8, 1));
    if (@socketConnect(client, PORT) < 0) @exit(@intCast(u8, 2));
    const msg: []const u8 = "i";
    _ = @socketSend(client, msg.ptr, @intCast(i32, msg.len));
    // Read whatever the server streams until it closes or a short timeout elapses.
    var buf: [4096]u8 = undefined;
    var i: i32 = 0;
    while (i < 2000) : (i += 1) {
        const n = @socketRecv(client, &buf[0], 4096);
        if (n <= 0) break;
    }
    @socketClose(client);
    @exit(@intCast(u8, 0));
}
