const std = @import("std.zig");
const std_net = @import("std_net.zig");

// Exercise all 11 socket builtins in one process (client + server):
// 1. @socketCreate(4001)   -> server socket (socket+bind)
// 2. @socketBindListen     -> listen
// 3. @socketCreate(0)      -> client socket (bind ephemeral port 0)
// 4. @socketConnect        -> client connects to 127.0.0.1:4001 (INADDR_ANY)
// 5. @socketSelect         -> wait for server readability
// 6. @socketFdZero/Set/Isset -> build + check the read set
// 7. @socketAccept         -> accept the client
// 8. @socketSend / @socketRecv -> echo a 5-byte message
// 9. @socketClose          -> close all sockets
// Also tests the failing-connect path (@socketConnect to a closed port -> -1).

fn fail(m: []const u8) void {
    @stdoutWrite(m.ptr, m.len);
    @exit(@intCast(u8, 1));
}

pub fn main() void {
    const PORT: u16 = 4001;

    // Server socket.
    const server = @socketCreate(PORT);
    if (server < 0) fail("server create failed\n");
    if (@socketBindListen(server, 5) < 0) fail("listen failed\n");

    // Client socket (bind ephemeral port 0), then connect to the server.
    const client = @socketCreate(0);
    if (client < 0) fail("client create failed\n");
    if (@socketConnect(client, PORT) < 0) fail("connect failed\n");

    // Negative test: connect to a closed port must return -1 (refused).
    const bad = @socketCreate(0);
    const bad_cr = @socketConnect(bad, 9999);
    if (bad_cr >= 0) fail("connect to closed port should fail\n");
    @socketClose(bad);

    // Select on the server socket for readability.
    var fds: std_net.fd_set = undefined;
    @socketFdZero(@ptrCast(*u8, &fds));
    @socketFdSet(server, @ptrCast(*u8, &fds));
    const ready = @socketSelect(server + 1, @ptrCast(*u8, &fds), null, null, 2000);
    if (ready <= 0) fail("select timeout\n");
    if (!@socketFdIsset(server, @ptrCast(*u8, &fds))) fail("server not ready\n");

    const accepted = @socketAccept(server);
    if (accepted < 0) fail("accept failed\n");

    // Client sends "hello".
    const msg: []const u8 = "hello";
    _ = @socketSend(client, msg.ptr, @intCast(i32, msg.len));

    // Server receives.
    var buf: [64]u8 = undefined;
    const n = @socketRecv(accepted, &buf[0], 64);
    if (n == 5 and buf[0] == 'h' and buf[4] == 'o') {
        const ok: []const u8 = "OK\n";
        _ = @socketSend(accepted, ok.ptr, @intCast(i32, ok.len));
    } else {
        fail("recv mismatch\n");
    }

    // Verify the echo round-trip back to the client.
    var ebuf: [64]u8 = undefined;
    const en = @socketRecv(client, &ebuf[0], 64);
    if (en != 3 or ebuf[0] != 'O' or ebuf[1] != 'K') fail("echo failed\n");

    @socketClose(accepted);
    @socketClose(client);
    @socketClose(server);
    std.io.printInt(@intCast(i32, 1));
    @exit(@intCast(u8, 0));
}
