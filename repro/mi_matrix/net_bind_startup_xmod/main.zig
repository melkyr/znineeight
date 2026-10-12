const std = @import("std");
const std_net = @import("std_net");

// S2 net-bind startup fixture: exercises init() plumbing + one socket-call
// shape. RED on the pre-S2 win target (init() was a no-op returning 0, so
// socket() fails WSANOTINITIALISED 10093 and createTcpServer(0) returns -1 ->
// exit 2). GREEN post-S2 both targets: linux rc0, win rc0 (WSAStartup runs).
pub fn main() void {
    if (std_net.init() != 0) @exit(@intCast(u8, 1));
    const s = std_net.createTcpServer(0);
    if (s < 0) @exit(@intCast(u8, 2));
    std.io.printInt(7);
    std.io.print("\n");
    std_net.close(s);
    std_net.cleanup();
}
