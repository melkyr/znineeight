// std_net.zig — Z98 networking library over the 11 socket builtins (Task F6).
// Zero extern "c". The C89 emitter inlines the per-platform socket bodies
// (#ifdef _WIN32 / #else), replacing net_runtime.c for migrated programs.

pub const fd_set = struct {
    // Opaque fd_set blob (Windows 260B / Linux 128B layouts covered by 512B).
    // [128]u32 forces 4-byte alignment, required by WinSock's select.
    data: [128]u32,
};

pub fn init() i32 {
    return 0;
}

pub fn cleanup() void {}

pub fn createTcpServer(port: u16) i32 {
    return @socketCreate(port);
}

pub fn bindListen(fd: i32, backlog: i32) i32 {
    return @socketBindListen(fd, backlog);
}

pub fn accept(fd: i32) i32 {
    return @socketAccept(fd);
}

pub fn connect(fd: i32, port: u16) i32 {
    return @socketConnect(fd, port);
}

pub fn send(fd: i32, buf: [*]const u8, len: i32) i32 {
    return @socketSend(fd, buf, len);
}

pub fn recv(fd: i32, buf: [*]u8, len: i32) i32 {
    return @socketRecv(fd, buf, len);
}

pub fn close(fd: i32) void {
    @socketClose(fd);
}

pub fn select(nfds: i32, readfds: ?*u8, writefds: ?*u8, exceptfds: ?*u8, timeout_ms: i32) i32 {
    return @socketSelect(nfds, readfds, writefds, exceptfds, timeout_ms);
}

pub fn fdZero(s: *u8) void {
    @socketFdZero(s);
}

pub fn fdSet(fd: i32, s: *u8) void {
    @socketFdSet(fd, s);
}

pub fn fdIsset(fd: i32, s: *u8) bool {
    return @socketFdIsset(fd, s);
}
