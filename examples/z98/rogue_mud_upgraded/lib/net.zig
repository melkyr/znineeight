const std = @import("std");
const std_net = @import("std_net");

pub const PlatSocket = i32;

pub const fd_set = struct {
    // Opaque fd_set blob (Windows 260B / Linux 128B layouts covered by 512B).
    // [128]u32 forces 4-byte alignment, required by WinSock's select.
    data: [128]u32,
};

pub fn fdZero(s: *u8) void {
    std_net.fdZero(s);
}

pub fn fdSet(fd: i32, s: *u8) void {
    std_net.fdSet(fd, s);
}

pub fn fdIsset(fd: i32, s: *u8) bool {
    return std_net.fdIsset(fd, s);
}

pub fn select(nfds: i32, readfds: ?*u8, writefds: ?*u8, exceptfds: ?*u8, timeout_ms: i32) i32 {
    return std_net.select(nfds, readfds, writefds, exceptfds, timeout_ms);
}

pub fn accept(server_sock: PlatSocket) PlatSocket {
    return std_net.accept(server_sock);
}

pub fn send(sock: PlatSocket, buf: [*]const u8, len: i32) i32 {
    return std_net.send(sock, buf, len);
}

pub fn recv(sock: PlatSocket, buf: [*]u8, len: i32) i32 {
    return std_net.recv(sock, buf, len);
}

pub fn close(sock: PlatSocket) void {
    std_net.close(sock);
}

pub const Client = struct {
    socket: PlatSocket,
    active: bool,
    entity_idx: usize, // Index in dungeon.entities
    buffer: [1024]u8,
    pos: usize,
};

pub const Server = struct {
    listen_socket: PlatSocket,
    clients: [5]Client,
};

pub fn Server_init(port: u16) !Server {
    if (std_net.init() != 0) return error.SocketInitFailed;

    const sock = std_net.createTcpServer(port);
    if (sock < 0) return error.CreateSocketFailed;

    if (std_net.bindListen(sock, 5) < 0) {
        std_net.close(sock);
        return error.ListenFailed;
    }

    var server = Server{
        .listen_socket = sock,
        .clients = undefined,
    };

    var i: usize = 0;
    while (i < @intCast(usize, 5)) : (i += 1) {
        server.clients[i].active = false;
        server.clients[i].socket = -1;
        server.clients[i].pos = 0;
    }

    return server;
}

pub fn Server_deinit(self: *Server) void {
    var i: usize = 0;
    while (i < @intCast(usize, 5)) : (i += 1) {
        if (self.clients[i].active) {
            std_net.close(self.clients[i].socket);
        }
    }
    std_net.close(self.listen_socket);
    std_net.cleanup();
}
