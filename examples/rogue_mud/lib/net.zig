const std = @import("../../mud_server/std.zig");

pub const PlatSocket = i32;

pub extern "c" fn plat_socket_init() i32;
pub extern "c" fn plat_socket_cleanup() void;
pub extern "c" fn plat_create_tcp_server(port: u16) PlatSocket;
pub extern "c" fn plat_bind_listen(sock: PlatSocket, backlog: i32) i32;
pub extern "c" fn plat_accept(server_sock: PlatSocket) PlatSocket;
pub extern "c" fn plat_recv(sock: PlatSocket, buf: [*]u8, len: i32) i32;
pub extern "c" fn plat_send(sock: PlatSocket, buf: [*]const u8, len: i32) i32;
pub extern "c" fn plat_close_socket(sock: PlatSocket) void;

pub const plat_fd_set = struct {
    data: [128]u32,
};

pub extern "c" fn plat_socket_select(nfds: i32, readfds: ?*u8, writefds: ?*u8, exceptfds: ?*u8, timeout_ms: i32) i32;
pub extern "c" fn plat_socket_fd_zero(s: *u8) void;
pub extern "c" fn plat_socket_fd_set(fd: i32, s: *u8) void;
pub extern "c" fn plat_socket_fd_isset(fd: i32, s: *u8) bool;

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
    if (plat_socket_init() != 0) return error.SocketInitFailed;

    const sock = plat_create_tcp_server(port);
    if (sock < 0) return error.CreateSocketFailed;

    if (plat_bind_listen(sock, 5) < 0) {
        plat_close_socket(sock);
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
            plat_close_socket(self.clients[i].socket);
        }
    }
    plat_close_socket(self.listen_socket);
    plat_socket_cleanup();
}
