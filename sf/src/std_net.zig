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

// UDP surface (blueprint §3 L3, operator ruling m1432). Socket is a pure alias
// for the existing fd convention (the TCP surface returns a raw i32); NetError
// is the module's one error set (R2) and deliberately excludes OutOfMemory —
// no UDP path allocates. When a future std_net function allocates it unions
// OutOfMemory into its own return type, not this set.
pub const Socket = i32;

pub const NetError = error {
    WouldBlock,
    Timeout,
    ConnRefused,
    ConnReset,
    NotConnected,
    AddrInUse,
    InvalidAddr,
    Io,
};

// Dotted-quad IPv4 address (blueprint §3 L3). Z98 does not gate top-level
// declarations on `pub`, so callers can still name it for out-params.
const IpAddr = struct { a: u8, b: u8, c: u8, d: u8 };

// Public byte-order helpers + extern wrappers. The externs are the real OS
// htons/htonl (wsock32 on win32, libc elsewhere); the Manual variants are
// portable byte-swaps for debugging.
pub extern "stdcall" fn htons(x: u16) u16;
pub extern "stdcall" fn htonl(x: u32) u32;

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
extern "stdcall" fn socket(af: i32, typ: i32, proto: i32) i32;
extern "stdcall" fn bind(s: i32, name: *const void, namelen: i32) i32;
extern "stdcall" fn listen(s: i32, backlog: i32) i32;
extern "stdcall" fn setsockopt(s: i32, level: i32, optname: i32, optval: *const void, optlen: i32) i32;
extern "stdcall" fn accept_os(s: i32, addr: *void, addrlen: *void) i32;
extern "stdcall" fn connect_os(s: i32, name: *const void, namelen: i32) i32;
extern "stdcall" fn send_os(s: i32, buf: [*]const u8, len: i32, flags: i32) i32;
extern "stdcall" fn recv_os(s: i32, buf: [*]u8, len: i32, flags: i32) i32;
extern "stdcall" fn select_os(nfds: i32, readfds: *void, writefds: *void, exceptfds: *void, timeout: *const void) i32;
extern "stdcall" fn close_os(fd: i32) i32;
extern "stdcall" fn closesocket(s: i32) i32;
extern "stdcall" fn WSAStartup(wVersion: u16, lpWSAData: *void) i32;
extern "stdcall" fn WSACleanup() i32;

// UDP externs. sendto/recvfrom are not owned by std_net's public API (the
// public names are udpSendTo/udpRecvFrom), so they are declared directly — no
// _os alias needed. The sockaddr*/socklen* params are *void so the call sites
// convert implicitly to whatever the per-OS prototype in net_prelude.h wants
// (POSIX socklen_t* vs WinSock int*).
extern "stdcall" fn sendto(s: i32, buf: [*]const u8, len: i32, flags: i32, name: *const void, namelen: i32) i32;
extern "stdcall" fn recvfrom(s: i32, buf: [*]u8, len: i32, flags: i32, name: *void, namelen: *void) i32;

// Per-OS last-error source. WSAGetLastError is pruned on POSIX and
// __errno_location (glibc) is pruned on win32 by the @isWindows() guards in
// lastErr; the C89 emitter emits no prototype for non-variadic externs, so the
// declarations here are the resolution source for the call sites.
extern "stdcall" fn WSAGetLastError() i32;
extern "c" fn __errno_location() *i32;

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

pub fn createTcpClient(port: u16) i32 {
    if (@isWindows()) {
        const s = socket(@intCast(i32, 2), @intCast(i32, 1), @intCast(i32, 0));
        if (s == -1) return -1;
        var addr = SockAddrIn{
            .sin_family = @intCast(u16, 2),
            .sin_port = htons(port),
            .sin_addr = htonl(@intCast(u32, 0x7F000001)),
            .sin_zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
        };
        if (connect_os(s, @ptrCast(*const void, &addr), @intCast(i32, 16)) == -1) {
            _ = closesocket(s);
            return -1;
        }
        return s;
    } else {
        const s = socket(@intCast(i32, 2), @intCast(i32, 1), @intCast(i32, 0));
        if (s < 0) return -1;
        var addr = SockAddrIn{
            .sin_family = @intCast(u16, 2),
            .sin_port = htons(port),
            .sin_addr = htonl(@intCast(u32, 0x7F000001)),
            .sin_zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
        };
        if (connect_os(s, @ptrCast(*const void, &addr), @intCast(i32, 16)) < 0) {
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

// --- UDP surface (blueprint §3 L3, operator m1432) --------------------------

// Per-OS last socket error. Must be read immediately after the failing OS call
// (any intervening libc call, including close, may clobber errno).
fn lastErr() i32 {
    if (@isWindows()) {
        return WSAGetLastError();
    } else {
        return __errno_location().*;
    }
}

// Map the per-OS socket error codes to NetError. POSIX values are the pinned
// i386-linux numbers; win32 values are the Winsock 1.1 WSAE* numbers. Anything
// not a known transient/address condition collapses to Io.
fn mapErr(code: i32) NetError {
    if (@isWindows()) {
        if (code == 10035) return error.WouldBlock;   // WSAEWOULDBLOCK
        if (code == 10060) return error.Timeout;      // WSAETIMEDOUT
        if (code == 10061) return error.ConnRefused;  // WSAECONNREFUSED
        if (code == 10054) return error.ConnReset;    // WSAECONNRESET
        if (code == 10057) return error.NotConnected; // WSAENOTCONN
        if (code == 10048) return error.AddrInUse;    // WSAEADDRINUSE
        if (code == 10022) return error.InvalidAddr;  // WSAEINVAL
        if (code == 10047) return error.InvalidAddr;  // WSAEAFNOSUPPORT
        return error.Io;
    } else {
        if (code == 11) return error.WouldBlock;    // EAGAIN / EWOULDBLOCK
        if (code == 110) return error.Timeout;      // ETIMEDOUT
        if (code == 111) return error.ConnRefused;  // ECONNREFUSED
        if (code == 104) return error.ConnReset;    // ECONNRESET
        if (code == 107) return error.NotConnected; // ENOTCONN
        if (code == 98) return error.AddrInUse;     // EADDRINUSE
        if (code == 22) return error.InvalidAddr;   // EINVAL
        if (code == 97) return error.InvalidAddr;   // EAFNOSUPPORT
        return error.Io;
    }
}

// Receive-path normalization. The UDP socket is never set non-blocking, so its
// only EAGAIN/EWOULDBLOCK source is the SO_RCVTIMEO expiry; WinSock reports the
// same expiry as WSAETIMEDOUT. Both collapse to Timeout so the contract is
// uniform across targets.
fn mapRecvErr(code: i32) NetError {
    const e = mapErr(code);
    if (e == error.WouldBlock) return error.Timeout;
    return e;
}

// Pack a.b.c.d into the network-order 32-bit address (a is the high byte);
// htonl then places the bytes in memory order on either endianness.
fn ipToU32(addr: IpAddr) u32 {
    return (@intCast(u32, addr.a) << 24) | (@intCast(u32, addr.b) << 16) | (@intCast(u32, addr.c) << 8) | @intCast(u32, addr.d);
}

fn emptySockAddr() SockAddrIn {
    return SockAddrIn{
        .sin_family = @intCast(u16, 2),
        .sin_port = @intCast(u16, 0),
        .sin_addr = @intCast(u32, 0),
        .sin_zero = [8]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };
}

// AF_INET=2, SOCK_DGRAM=2, IPPROTO_UDP=0 on both targets.
pub fn udpBind(port: u16) NetError!Socket {
    const s = socket(@intCast(i32, 2), @intCast(i32, 2), @intCast(i32, 0));
    if (s < 0) return mapErr(lastErr());
    var addr = emptySockAddr();
    addr.sin_port = htons(port);
    addr.sin_addr = htonl(@intCast(u32, 0));
    const rc = bind(s, @ptrCast(*const void, &addr), @intCast(i32, 16));
    if (rc < 0) {
        const e = lastErr();
        close(s);
        return mapErr(e);
    }
    return s;
}

pub fn udpSendTo(s: *Socket, addr: IpAddr, port: u16, data: []const u8) NetError!void {
    var sa = emptySockAddr();
    sa.sin_port = htons(port);
    sa.sin_addr = htonl(ipToU32(addr));
    const rc = sendto(s.*, data.ptr, @intCast(i32, data.len), @intCast(i32, 0), @ptrCast(*const void, &sa), @intCast(i32, 16));
    if (rc < 0) return mapErr(lastErr());
    return;
}

// Write the source address/port out-params from a recvfrom sockaddr. Reading
// the network-order sin_addr bytes directly keeps host endianness irrelevant.
fn fillOut(from: *SockAddrIn, out_addr: *IpAddr, out_port: *u16) void {
    var p: [*]u8 = @ptrCast([*]u8, &from.sin_addr);
    out_addr.* = IpAddr{ .a = p[0], .b = p[1], .c = p[2], .d = p[3] };
    out_port.* = htonsManual(from.sin_port);
}

pub fn udpRecvFrom(s: *Socket, buf: []u8, out_addr: *IpAddr, out_port: *u16) NetError!usize {
    var from = emptySockAddr();
    var fromlen: i32 = @intCast(i32, 16);
    const rc = recvfrom(s.*, buf.ptr, @intCast(i32, buf.len), @intCast(i32, 0), @ptrCast(*void, &from), @ptrCast(*void, &fromlen));
    if (rc < 0) {
        const e = lastErr();
        // WinSock reports a datagram larger than the buffer as WSAEMSGSIZE
        // after copying the truncated prefix; POSIX recvfrom silently returns
        // buf.len instead. Normalize so truncation is uniformly
        // non-detectable (the documented contract). WinSock still fills the
        // source sockaddr, so the out-params are populated exactly as on the
        // POSIX success path.
        if (@isWindows()) {
            if (e == 10040) {
                fillOut(&from, out_addr, out_port);
                return buf.len;
            }
        }
        return mapRecvErr(e);
    }
    // Truncation (rc == buf.len while the datagram was longer) is not
    // detectable here; see the module contract.
    fillOut(&from, out_addr, out_port);
    return @intCast(usize, rc);
}

pub fn udpSetTimeout(s: *Socket, ms: u32) NetError!void {
    if (@isWindows()) {
        // WinSock SO_RCVTIMEO (SOL_SOCKET=0xFFFF, opt=0x1006) takes a DWORD of
        // milliseconds, not a timeval.
        var v: u32 = ms;
        const rc = setsockopt(s.*, @intCast(i32, 65535), @intCast(i32, 4102), @ptrCast(*const void, &v), @intCast(i32, 4));
        if (rc != 0) return mapErr(lastErr());
        return;
    } else {
        // POSIX SO_RCVTIMEO (SOL_SOCKET=1, opt=20) takes a struct timeval
        // (i386: two i32 fields).
        var tv = TimeVal{ .tv_sec = @intCast(i32, ms / 1000), .tv_usec = @intCast(i32, (ms % 1000) * 1000) };
        const rc = setsockopt(s.*, @intCast(i32, 1), @intCast(i32, 20), @ptrCast(*const void, &tv), @intCast(i32, 8));
        if (rc != 0) return mapErr(lastErr());
        return;
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
