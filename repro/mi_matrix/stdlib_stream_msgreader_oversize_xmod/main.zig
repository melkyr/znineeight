// stdlib_stream_msgreader_oversize_xmod — Plan D hardening Task 3 probe.
//
// Single-failure-per-process probe for the MsgReader oversize boundary
// (operator framing ruling; Plan D Task 3). The u32 big-endian length prefix
// declares 17 bytes against a 16-byte reader buffer: the declared length
// exceeds the buffer capacity, so readMsgSync must reject it with
// error.FrameTooLarge — the operator-authorized std_stream framing error.
//
// The prefix is pre-sent on a blocking loopback socket, so readMsgSync reads
// the 4 prefix bytes and rejects before it ever tries to read the body (no
// block, no sleep, no executor). Any other error or a returned frame panics.
//
// GREEN contract (declared expected.rc 0): stdout `oversize ok\n`.
const net = @import("std_net.zig");
const st = @import("std_stream.zig");
const io = @import("std_io.zig");

const PORT: u16 = 4157;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

// Encode a u32 big-endian prefix into `pfx` (network byte order).
fn putPrefix(pfx: []u8, len: u32) void {
    pfx[0] = @intCast(u8, (len >> 24) & @intCast(u32, 255));
    pfx[1] = @intCast(u8, (len >> 16) & @intCast(u32, 255));
    pfx[2] = @intCast(u8, (len >> 8) & @intCast(u32, 255));
    pfx[3] = @intCast(u8, len & @intCast(u32, 255));
}

pub fn main() void {
    if (net.init() != 0) @panic("init");
    const server = net.createTcpServer(PORT);
    ck(server >= 0, "server");
    ck(net.bindListen(server, 5) >= 0, "listen");
    const client = net.createTcpClient(PORT);
    ck(client >= 0, "client");

    var conn: i32 = -1;
    var tries: usize = 0;
    while (conn < 0 and tries < 100000) : (tries += 1) {
        conn = net.accept(server);
    }
    ck(conn >= 0, "accept");

    // Declared length 17 > buffer capacity 16.
    var pfx: [4]u8 = undefined;
    putPrefix(pfx[0..4], @intCast(u32, 17));
    ck(net.send(conn, @ptrCast([*]const u8, &pfx), 4) == 4, "send prefix");

    var buf: [16]u8 = undefined;
    var mr = st.initMsgReader(&client, buf[0..]);
    const got = st.readMsgSync(&mr) catch |e| {
        ck(e == error.FrameTooLarge, "oversize -> unexpected error");
        io.write("oversize ok\n");
        net.close(conn);
        net.close(client);
        net.close(server);
        net.cleanup();
        return;
    };
    _ = got;
    @panic("oversize: readMsgSync returned a frame, not FrameTooLarge");
}
