// stdlib_net_resolve_xmod — STDLIB std_net (M0 §4.1) resolve() contract.
//
// resolve(host) wraps gethostbyname behind a Z98 API and returns the resolved
// IPv4 address in NETWORK byte order (ready for sockaddr_in.sin_addr). This
// fixture resolves the literal "localhost", which /etc/hosts maps to the
// loopback address, and prints the returned u32 in `%08x` form.
//
// Contract: `resolve ok 0100007f` on a little-endian host (the network-order
// bytes 7f 00 00 01 read back as the native u32 0x0100007f).
//
// GREEN: deterministic byte-exact stdout `resolve ok 0100007f\n` (rc 0).
const net = @import("std_net.zig");
const io = @import("std_io.zig");

fn printHex8(v: u32) void {
    var hex: []const u8 = "0123456789abcdef";
    var i: i32 = 7;
    while (i >= 0) : (i -= 1) {
        const shift: u32 = @intCast(u32, i * 4);
        const nib: u32 = (v >> shift) & @intCast(u32, 15);
        io.writeByte(hex[@intCast(usize, nib)]);
    }
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    var host: []const u8 = "localhost";
    const ip = net.resolve(host) catch @panic("resolve");
    var pre: []const u8 = "resolve ok ";
    io.write(pre);
    printHex8(ip);
    var nl: []const u8 = "\n";
    io.write(nl);
    net.cleanup();
}
