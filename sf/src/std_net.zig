// std_net.zig — Z98 networking library as target-selected extern "c" OS
// bindings (S2 std_net extern rewrite). Windows path = wsock32 (Winsock 1.1,
// WSAStartup(1,1) init); linux path = libc. The C89 emitter emits no
// prototypes for non-variadic externs, so net_prelude.h (found on the
// compiler include path) supplies the per-OS declarations.

@cInclude("<net_prelude.h>");

pub const fd_set = struct {
    // Opaque fd_set blob (Windows 260B / Linux 128B layouts covered by 512B).
    // [128]u32 forces 4-byte alignment, required by WinSock's select.
    data: [128]u32,
};

// Public byte-order helpers + extern wrappers. The externs are the real OS
// htons/htonl (wsock32 on win32, libc elsewhere); the Manual variants are
// portable byte-swaps for debugging.
pub extern "c" fn htons(x: u16) u16;
pub extern "c" fn htonl(x: u32) u32;

pub fn htonsManual(x: u16) u16 {
    return @intCast(u16, ((x & @intCast(u16, 0xFF)) << 8) | (x >> 8));
}

pub fn htonlManual(x: u32) u32 {
    return @intCast(u32, ((x & @intCast(u32, 0xFF)) << 24) | ((x & @intCast(u32, 0xFF00)) << 8) | ((x & @intCast(u32, 0xFF0000)) >> 8) | (x >> 24));
}

// Target extern sets. accept/connect/send/recv/close/select are declared with
// an _os suffix because std_net's public API owns those names; net_prelude.h
// maps the _os identifiers to the real OS symbols (single declaration source
// remains the OS header). Select's fd_set/timeval params are *void (the caller
// blob is byte-layout-identical to the native fd_set at offset 0, so a pointer
// cast lowers cleanly — S2-I layout probes).
extern "c" fn socket(af: i32, typ: i32, proto: i32) i32;
extern "c" fn bind(s: i32, name: *const void, namelen: i32) i32;
extern "c" fn listen(s: i32, backlog: i32) i32;
extern "c" fn setsockopt(s: i32, level: i32, optname: i32, optval: *const void, optlen: i32) i32;
extern "c" fn accept_os(s: i32, addr: *void, addrlen: *void) i32;
extern "c" fn connect_os(s: i32, name: *const void, namelen: i32) i32;
extern "c" fn send_os(s: i32, buf: [*]const u8, len: i32, flags: i32) i32;
extern "c" fn recv_os(s: i32, buf: [*]u8, len: i32, flags: i32) i32;
extern "c" fn select_os(nfds: i32, readfds: *void, writefds: *void, exceptfds: *void, timeout: *const void) i32;
extern "c" fn close_os(fd: i32) i32;
extern "c" fn closesocket(s: i32) i32;
extern "c" fn WSAStartup(wVersion: u16, lpWSAData: *void) i32;
extern "c" fn WSACleanup() i32;

pub fn init() i32 {
    if (@isWindows()) {
        var wsa: WSAData = undefined;
        const rc = WSAStartup(@intCast(u16, 0x0101), @ptrCast(*void, &wsa));
        return rc;
    } else {
        return 0;
    }
}

pub fn cleanup() void {
    if (@isWindows()) {
        _ = WSACleanup();
    } else {
        return;
    }
}

pub fn createTcpServer(port: u16) i32 {
    if (@isWindows()) {
        const s = socket(@intCast(i32, 2), @intCast(i32, 1), @intCast(i32, 0));
        if (s == -1) return -1;
        var addr = SockAddrIn{
            .sin_family = @intCast(u16, 2),
            .sin_port = htons(port),
            .sin_addr = htonl(@intCast(u32, 0)),
            .sin_zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
        };
        if (bind(s, @ptrCast(*const void, &addr), @intCast(i32, 16)) == -1) {
            _ = closesocket(s);
            return -1;
        }
        return s;
    } else {
        const s = socket(@intCast(i32, 2), @intCast(i32, 1), @intCast(i32, 0));
        if (s < 0) return -1;
        var opt: i32 = @intCast(i32, 1);
        _ = setsockopt(s, @intCast(i32, 1), @intCast(i32, 2), @ptrCast(*const void, &opt), @intCast(i32, 4));
        var addr = SockAddrIn{
            .sin_family = @intCast(u16, 2),
            .sin_port = htons(port),
            .sin_addr = htonl(@intCast(u32, 0)),
            .sin_zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
        };
        if (bind(s, @ptrCast(*const void, &addr), @intCast(i32, 16)) < 0) {
            _ = close_os(s);
            return -1;
        }
        return s;
    }
}

pub fn bindListen(fd: i32, backlog: i32) i32 {
    if (@isWindows()) {
        const rc = listen(fd, backlog);
        if (rc == -1) return -1;
        return 0;
    } else {
        const rc = listen(fd, backlog);
        if (rc < 0) return -1;
        return 0;
    }
}

pub fn accept(fd: i32) i32 {
    if (@isWindows()) {
        const c = accept_os(fd, @ptrCast(*void, @intToPtr(*void, 0)), @ptrCast(*void, @intToPtr(*void, 0)));
        if (c == -1) return -1;
        return c;
    } else {
        return accept_os(fd, @ptrCast(*void, @intToPtr(*void, 0)), @ptrCast(*void, @intToPtr(*void, 0)));
    }
}

pub fn connect(fd: i32, port: u16) i32 {
    var addr = SockAddrIn{
        .sin_family = @intCast(u16, 2),
        .sin_port = htons(port),
        .sin_addr = htonl(@intCast(u32, 0x7F000001)),
        .sin_zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    if (@isWindows()) {
        const rc = connect_os(fd, @ptrCast(*const void, &addr), @intCast(i32, 16));
        if (rc == -1) return -1;
        return 0;
    } else {
        const rc = connect_os(fd, @ptrCast(*const void, &addr), @intCast(i32, 16));
        if (rc < 0) return -1;
        return 0;
    }
}

pub fn send(fd: i32, buf: [*]const u8, len: i32) i32 {
    return send_os(fd, buf, len, @intCast(i32, 0));
}

pub fn recv(fd: i32, buf: [*]u8, len: i32) i32 {
    return recv_os(fd, buf, len, @intCast(i32, 0));
}

pub fn close(fd: i32) void {
    if (@isWindows()) {
        _ = closesocket(fd);
    } else {
        _ = close_os(fd);
    }
}

pub fn select(nfds: i32, readfds: ?*u8, writefds: ?*u8, exceptfds: ?*u8, timeout_ms: i32) i32 {
    var tv = TimeVal{ .tv_sec = @intCast(i32, 0), .tv_usec = @intCast(i32, 0) };
    var ptv: *const void = @ptrCast(*const void, @intToPtr(*void, 0));
    if (timeout_ms >= 0) {
        tv.tv_sec = timeout_ms / @intCast(i32, 1000);
        tv.tv_usec = (timeout_ms % @intCast(i32, 1000)) * @intCast(i32, 1000);
        ptv = @ptrCast(*const void, &tv);
    }
    var rf: *void = undefined;
    if (readfds) |p| {
        rf = @ptrCast(*void, p);
    } else {
        rf = @ptrCast(*void, @intToPtr(*void, 0));
    }
    var wf: *void = undefined;
    if (writefds) |p2| {
        wf = @ptrCast(*void, p2);
    } else {
        wf = @ptrCast(*void, @intToPtr(*void, 0));
    }
    var xf: *void = undefined;
    if (exceptfds) |p3| {
        xf = @ptrCast(*void, p3);
    } else {
        xf = @ptrCast(*void, @intToPtr(*void, 0));
    }
    if (@isWindows()) {
        return select_os(nfds, rf, wf, xf, ptv);
    } else {
        return select_os(nfds, rf, wf, xf, ptv);
    }
}

pub fn fdZero(s: *u8) void {
    if (@isWindows()) {
        var fs = @ptrCast(*fd_set, s);
        fs.data[0] = @intCast(u32, 0);
    } else {
        var fs = @ptrCast(*fd_set, s);
        var i: usize = 0;
        while (i < @intCast(usize, 32)) : (i += 1) {
            fs.data[i] = @intCast(u32, 0);
        }
    }
}

pub fn fdSet(fd: i32, s: *u8) void {
    if (@isWindows()) {
        var fs = @ptrCast(*fd_set, s);
        var n = fs.data[0];
        n += @intCast(u32, 1);
        fs.data[0] = n;
        fs.data[n] = @intCast(u32, fd);
    } else {
        var fs = @ptrCast(*fd_set, s);
        const word = @intCast(usize, @intCast(u32, fd) / @intCast(u32, 32));
        var bit = @intCast(u32, fd) % @intCast(u32, 32);
        var mask: u32 = @intCast(u32, 1);
        var k: u32 = 0;
        while (k < bit) : (k += 1) {
            mask = mask + mask;
        }
        fs.data[word] = fs.data[word] | mask;
    }
}

pub fn fdIsset(fd: i32, s: *u8) bool {
    if (@isWindows()) {
        var fs = @ptrCast(*fd_set, s);
        var i: usize = 1;
        while (i <= @intCast(usize, fs.data[0])) : (i += 1) {
            if (fs.data[i] == @intCast(u32, fd)) return true;
        }
        return false;
    } else {
        var fs = @ptrCast(*fd_set, s);
        const word = @intCast(usize, @intCast(u32, fd) / @intCast(u32, 32));
        var bit = @intCast(u32, fd) % @intCast(u32, 32);
        var mask: u32 = @intCast(u32, 1);
        var k: u32 = 0;
        while (k < bit) : (k += 1) {
            mask = mask + mask;
        }
        if ((fs.data[word] & mask) != @intCast(u32, 0)) return true;
        return false;
    }
}

// Internal per-target layout structs (byte-exact vs the OS headers — S2-I
// verdict: WSAData 400B with lpVendorInfo@396; sockaddr_in 16B both targets;
// timeval { i32 sec, i32 usec } 8B both targets).
const WSAData = struct {
    wVersion: u16,
    wHighVersion: u16,
    szDescription: [257]u8,
    szSystemStatus: [129]u8,
    iMaxSockets: u16,
    iMaxUdpDg: u16,
    lpVendorInfo: *u8,
};

const SockAddrIn = struct {
    sin_family: u16,
    sin_port: u16,
    sin_addr: u32,
    sin_zero: [8]u8,
};

const TimeVal = struct {
    tv_sec: i32,
    tv_usec: i32,
};
