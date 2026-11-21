// stdlib_net_udp_bind_xmod — STDLIB std_net (L3) udpBind GREEN fixture.
//
// Contract (blueprint §3 L3, operator m1432): udpBind(port) NetError!Socket
// creates an AF_INET/SOCK_DGRAM socket bound to INADDR_ANY:port. Socket is the
// fd alias i32 (the existing std_net convention); the caller closes it with
// std_net.close. NetError has no OutOfMemory member (no UDP path allocates).
//
// GREEN (contract): deterministic byte-exact stdout `udp bind ok\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4141;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const s = net.udpBind(PORT) catch @panic("udpBind");
    ck(s >= 0, "udpBind fd");
    net.close(s);
    net.cleanup();
    io.write("udp bind ok\n");
}
