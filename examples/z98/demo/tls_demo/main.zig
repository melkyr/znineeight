// main.zig — tls_demo: HTTPS fetch over std_net + std_tls through
// std_http.httpGetOver (Phase 1 M4 Task 3).
//
// usage: tls_demo [url] [store] [clock_override_unix]
//
// Defaults: url https://www.google.com/, store ca_store.bin (falling back to
// the tree path examples/z98/demo/tls_demo/ca_store.bin), clock from
// std_time.wallClockUnix().  The optional clock override exists for Win9x
// machines with a dead RTC; without it a nonsensical system clock fails
// cleanly as `cert: time`.
//
// Output: `status=N`, the first 4 KiB of the response body, then
//   tls_demo ok status=N bytes=N arena_peak=N rss_peak=N cpu_ms=N
// Failures exit nonzero with `cert: <Reason>` or `tls: <Reason>`.

const std = @import("std");
const tls = @import("std_tls.zig");
const http = @import("std_http.zig");
const x509 = @import("std_x509.zig");
const rand = @import("std_rand.zig");
const filemod = @import("std_file.zig");

const DEFAULT_URL = "https://www.google.com/";
const BODY_PRINT_CAP: usize = 4096;
const CONNECT_TIMEOUT_MS: u32 = 15000;
const IO_TIMEOUT_MS: u32 = 15000;
const ARENA_SIZE: usize = 4 * 1024 * 1024;
const STORE_ARENA_SIZE: usize = 512 * 1024;

var g_arena_buf: [ARENA_SIZE]u8 = undefined;
var g_arena = std.arena.init(g_arena_buf[0..]);
var g_store_buf: [STORE_ARENA_SIZE]u8 = undefined;
var g_store_arena = std.arena.init(g_store_buf[0..]);
var g_store: x509.TrustStore = undefined;
var g_session: tls.TlsSession = undefined;
var g_rng: rand.Xoshiro256 = undefined;

const DemoError = error{
    Time,
    BadArgs,
    DnsFailed,
    ConnectFailed,
    Timeout,
    StoreRead,
    StoreCorrupt,
    OutOfMemory,
    CertificateExpired,
    CertificateNotYetValid,
    UnknownIssuer,
    HostnameMismatch,
    BadSignature,
    ChainTooLong,
    UnsupportedAlgorithm,
    UnsupportedVersion,
    UnsupportedSuite,
    UnsupportedGroup,
    BadConfig,
    HandshakeFailed,
    Corrupt,
    AuthenticationFailed,
    RecordTooLarge,
    Closed,
    AppTooLarge,
    OutputTooSmall,
    BadAction,
    WeakPublicKey,
    InvalidPrivateKey,
    InvalidPublicKey,
    HttpBadUrl,
    HttpBadResponse,
    HttpTooLarge,
    HttpFailed,
    TlsInternal,
};

const Conn = struct {
    fd: i32,
    sess: *tls.TlsSession,
    established: bool,
    closed: bool,
};

const UrlParts = struct {
    host: []const u8,
    port: u16,
    path: []const u8,
};

fn out(s: []const u8) void {
    std.io.write(s);
}

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn findFrom(hay: []const u8, needle: []const u8, from: usize) usize {
    if (needle.len == 0) return from;
    if (from > hay.len) return hay.len;
    var i: usize = from;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (hay[i + j] != needle[j]) break;
        }
        if (j == needle.len) return i;
    }
    return hay.len;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn parseU64(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (!isDigit(s[i])) return null;
        if (v > (@intCast(u64, 18446744073709551615) - @intCast(u64, s[i] - 48)) / 10) return null;
        v = v * 10 + @intCast(u64, s[i] - 48);
    }
    return v;
}

fn parseI64Clock(s: []const u8) ?i64 {
    if (s.len == 0) return null;
    var i: usize = 0;
    var neg: bool = false;
    if (s[0] == '-') {
        neg = true;
        i = 1;
    } else if (s[0] == '+') {
        i = 1;
    }
    if (i >= s.len) return null;
    var v: u64 = 0;
    const limit: u64 = @intCast(u64, 9223372036854775807);
    while (i < s.len) : (i += 1) {
        if (!isDigit(s[i])) return null;
        const digit: u64 = @intCast(u64, s[i] - 48);
        if (v > (limit - digit) / 10) return null;
        v = v * 10 + digit;
    }
    if (neg) return -@intCast(i64, v);
    return @intCast(i64, v);
}

fn parseHttpsUrl(url: []const u8) DemoError!UrlParts {
    const sep = findFrom(url, "://", 0);
    if (sep >= url.len) return DemoError.HttpBadUrl;
    if (!eqBytes(url[0..sep], "https")) return DemoError.HttpBadUrl;
    const auth_start = sep + 3;
    var auth_end: usize = auth_start;
    while (auth_end < url.len and url[auth_end] != '/' and url[auth_end] != '?') : (auth_end += 1) {}
    if (auth_end == auth_start) return DemoError.HttpBadUrl;

    const authority = url[auth_start..auth_end];
    var host: []const u8 = authority;
    var port: u16 = 443;
    const colon = findFrom(authority, ":", 0);
    if (colon < authority.len) {
        host = authority[0..colon];
        const p = parseU64(authority[colon + 1 ..]) orelse return DemoError.HttpBadUrl;
        if (p == 0 or p > 65535) return DemoError.HttpBadUrl;
        port = @intCast(u16, p);
    }
    if (host.len == 0) return DemoError.HttpBadUrl;

    var path: []const u8 = "/";
    if (auth_end < url.len) {
        if (url[auth_end] == '/') {
            path = url[auth_end..];
        } else {
            path = "/";
        }
    }
    return UrlParts{ .host = host, .port = port, .path = path };
}

fn mapTls(e: tls.TlsError) DemoError {
    if (e == error.CertificateExpired) return DemoError.CertificateExpired;
    if (e == error.CertificateNotYetValid) return DemoError.CertificateNotYetValid;
    if (e == error.UnknownIssuer) return DemoError.UnknownIssuer;
    if (e == error.HostnameMismatch) return DemoError.HostnameMismatch;
    if (e == error.BadSignature) return DemoError.BadSignature;
    if (e == error.ChainTooLong) return DemoError.ChainTooLong;
    if (e == error.UnsupportedAlgorithm) return DemoError.UnsupportedAlgorithm;
    if (e == error.UnsupportedVersion) return DemoError.UnsupportedVersion;
    if (e == error.UnsupportedSuite) return DemoError.UnsupportedSuite;
    if (e == error.UnsupportedGroup) return DemoError.UnsupportedGroup;
    if (e == error.BadConfig) return DemoError.BadConfig;
    if (e == error.HandshakeFailed) return DemoError.HandshakeFailed;
    if (e == error.Corrupt) return DemoError.Corrupt;
    if (e == error.AuthenticationFailed) return DemoError.AuthenticationFailed;
    if (e == error.RecordTooLarge) return DemoError.RecordTooLarge;
    if (e == error.Closed) return DemoError.Closed;
    if (e == error.AppTooLarge) return DemoError.AppTooLarge;
    if (e == error.OutputTooSmall) return DemoError.OutputTooSmall;
    if (e == error.BadAction) return DemoError.BadAction;
    if (e == error.WeakPublicKey) return DemoError.WeakPublicKey;
    if (e == error.InvalidPrivateKey) return DemoError.InvalidPrivateKey;
    if (e == error.InvalidPublicKey) return DemoError.InvalidPublicKey;
    return DemoError.TlsInternal;
}

fn fail(e: DemoError) noreturn {
    var prefix: []const u8 = "tls: ";
    var name: []const u8 = "TlsInternal";
    if (e == DemoError.Time) {
        prefix = "cert: ";
        name = "time";
    } else if (e == DemoError.CertificateExpired) {
        prefix = "cert: ";
        name = "CertificateExpired";
    } else if (e == DemoError.CertificateNotYetValid) {
        prefix = "cert: ";
        name = "CertificateNotYetValid";
    } else if (e == DemoError.UnknownIssuer) {
        prefix = "cert: ";
        name = "UnknownIssuer";
    } else if (e == DemoError.HostnameMismatch) {
        prefix = "cert: ";
        name = "HostnameMismatch";
    } else if (e == DemoError.BadSignature) {
        prefix = "cert: ";
        name = "BadSignature";
    } else if (e == DemoError.ChainTooLong) {
        prefix = "cert: ";
        name = "ChainTooLong";
    } else if (e == DemoError.UnsupportedAlgorithm) {
        prefix = "cert: ";
        name = "UnsupportedAlgorithm";
    } else if (e == DemoError.StoreRead) {
        name = "StoreRead";
    } else if (e == DemoError.StoreCorrupt) {
        name = "StoreCorrupt";
    } else if (e == DemoError.DnsFailed) {
        name = "DnsFailed";
    } else if (e == DemoError.ConnectFailed) {
        name = "ConnectFailed";
    } else if (e == DemoError.Timeout) {
        name = "Timeout";
    } else if (e == DemoError.BadArgs) {
        name = "BadArgs";
    } else if (e == DemoError.HttpBadUrl) {
        name = "HttpBadUrl";
    } else if (e == DemoError.HttpBadResponse) {
        name = "HttpBadResponse";
    } else if (e == DemoError.HttpTooLarge) {
        name = "HttpTooLarge";
    } else if (e == DemoError.HttpFailed) {
        name = "HttpFailed";
    } else if (e == DemoError.HandshakeFailed) {
        name = "HandshakeFailed";
    } else if (e == DemoError.Corrupt) {
        name = "Corrupt";
    } else if (e == DemoError.AuthenticationFailed) {
        name = "AuthenticationFailed";
    } else if (e == DemoError.RecordTooLarge) {
        name = "RecordTooLarge";
    } else if (e == DemoError.Closed) {
        name = "Closed";
    } else if (e == DemoError.AppTooLarge) {
        name = "AppTooLarge";
    } else if (e == DemoError.OutputTooSmall) {
        name = "OutputTooSmall";
    } else if (e == DemoError.BadAction) {
        name = "BadAction";
    } else if (e == DemoError.WeakPublicKey) {
        name = "WeakPublicKey";
    } else if (e == DemoError.InvalidPrivateKey) {
        name = "InvalidPrivateKey";
    } else if (e == DemoError.InvalidPublicKey) {
        name = "InvalidPublicKey";
    } else if (e == DemoError.OutOfMemory) {
        name = "OutOfMemory";
    } else if (e == DemoError.UnsupportedVersion) {
        name = "UnsupportedVersion";
    } else if (e == DemoError.UnsupportedSuite) {
        name = "UnsupportedSuite";
    } else if (e == DemoError.UnsupportedGroup) {
        name = "UnsupportedGroup";
    } else if (e == DemoError.BadConfig) {
        name = "BadConfig";
    }
    out(prefix);
    out(name);
    out("\n");
    std.os.exit(1);
}

fn waitRead(fd: i32, ms: u32) DemoError!void {
    var fds: std.net.fd_set = undefined;
    std.net.fdZero(@ptrCast(*u8, &fds));
    std.net.fdSet(fd, @ptrCast(*u8, &fds));
    const sr = std.net.select(fd + 1, @ptrCast(*u8, &fds), null, null, @intCast(i32, ms));
    if (sr == 0) return DemoError.Timeout;
    if (sr < 0) return DemoError.ConnectFailed;
}

fn waitWrite(fd: i32, ms: u32) DemoError!void {
    var fds: std.net.fd_set = undefined;
    std.net.fdZero(@ptrCast(*u8, &fds));
    std.net.fdSet(fd, @ptrCast(*u8, &fds));
    const sr = std.net.select(fd + 1, null, @ptrCast(*u8, &fds), null, @intCast(i32, ms));
    if (sr == 0) return DemoError.Timeout;
    if (sr < 0) return DemoError.ConnectFailed;
}

fn socketRecvSome(c: *Conn, buf: []u8) DemoError!usize {
    if (buf.len == 0) return 0;
    while (true) {
        try waitRead(c.fd, IO_TIMEOUT_MS);
        var sock: std.net.Socket = c.fd;
        const n = std.net.recvNonBlocking(&sock, buf) catch |e| {
            if (e == error.WouldBlock) continue;
            return DemoError.ConnectFailed;
        };
        return n;
    }
}

fn socketSendAll(c: *Conn, data: []const u8) DemoError!void {
    var sent: usize = 0;
    while (sent < data.len) {
        try waitWrite(c.fd, IO_TIMEOUT_MS);
        var sock: std.net.Socket = c.fd;
        const n = std.net.sendNonBlocking(&sock, data[sent..]) catch |e| {
            if (e == error.WouldBlock) continue;
            return DemoError.ConnectFailed;
        };
        if (n == 0) return DemoError.ConnectFailed;
        sent += n;
    }
}

fn tlsStepEmpty(c: *Conn, outbuf: []u8) DemoError!tls.TlsAction {
    return tls.tlsStep(c.sess, "", outbuf) catch |e| return mapTls(e);
}

fn handshake(c: *Conn) DemoError!void {
    var outbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var inbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var act = tls.tlsStep(c.sess, "", outbuf[0..]) catch |e| return mapTls(e);
    var guard: usize = 0;
    while (true) {
        guard += 1;
        if (guard > 100000) return DemoError.HandshakeFailed;
        switch (act) {
            .send => |bytes| {
                try socketSendAll(c, bytes);
                act = try tlsStepEmpty(c, outbuf[0..]);
            },
            .recv => {
                const n = try socketRecvSome(c, inbuf[0..]);
                if (n == 0) return DemoError.HandshakeFailed;
                act = tls.tlsStep(c.sess, inbuf[0..n], outbuf[0..]) catch |e| return mapTls(e);
            },
            .wait => {
                const n = try socketRecvSome(c, inbuf[0..]);
                if (n == 0) return DemoError.HandshakeFailed;
                act = tls.tlsStep(c.sess, inbuf[0..n], outbuf[0..]) catch |e| return mapTls(e);
            },
            .established => {
                c.established = true;
                return;
            },
            .closed => return DemoError.HandshakeFailed,
            else => return DemoError.HandshakeFailed,
        }
    }
}

fn openTls(url: []const u8, now_unix: i64) DemoError!Conn {
    const parts = try parseHttpsUrl(url);

    const ip = std.net.resolve(parts.host) catch return DemoError.DnsFailed;
    const fd = std.net.tcpSocket() catch return DemoError.ConnectFailed;
    std.net.connectToIp(fd, ip, parts.port, CONNECT_TIMEOUT_MS) catch |e| {
        std.net.close(fd);
        if (e == error.Timeout) return DemoError.Timeout;
        return DemoError.ConnectFailed;
    };

    const seed: u64 = @intCast(u64, now_unix) ^ std.time.highRes() ^ @intCast(u64, fd);
    g_rng = rand.xoshiroInit(seed);
    var cfg = tls.TlsConfig{
        .hostname = parts.host,
        .store = &g_store,
        .rng = &g_rng,
        .now_unix = now_unix,
        .min_version = tls.TLS_VERSION_12,
        .max_version = tls.TLS_VERSION_12,
    };
    tls.tlsInit(&g_session, &cfg);

    var c = Conn{ .fd = fd, .sess = &g_session, .established = false, .closed = false };
    handshake(&c) catch |e| {
        std.net.close(fd);
        return e;
    };
    return c;
}

fn readApp(c: *Conn, buf: []u8) DemoError!usize {
    if (buf.len == 0) return 0;
    var outbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var inbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    while (true) {
        const got = tls.tlsRead(c.sess, buf) catch |e| return mapTls(e);
        if (got > 0) return got;
        if (c.closed) return 0;

        const n = try socketRecvSome(c, inbuf[0..]);
        if (n == 0) {
            c.closed = true;
            return 0;
        }
        var act = tls.tlsStep(c.sess, inbuf[0..n], outbuf[0..]) catch |e| return mapTls(e);
        var guard: usize = 0;
        while (true) {
            guard += 1;
            if (guard > 64) return DemoError.TlsInternal;
            switch (act) {
                .send => |bytes| {
                    try socketSendAll(c, bytes);
                    act = try tlsStepEmpty(c, outbuf[0..]);
                },
                .closed => {
                    c.closed = true;
                    break;
                },
                else => break,
            }
        }
    }
    return 0;
}

fn trRead(state: *void, buf: []u8) !usize {
    var c: *Conn = @ptrCast(*Conn, state);
    const n = readApp(c, buf) catch |e| {
        if (e == DemoError.Timeout) return error.Timeout;
        if (e == DemoError.OutOfMemory) return error.OutOfMemory;
        return error.BadResponse;
    };
    return n;
}

fn trWrite(state: *void, data: []const u8) !usize {
    var c: *Conn = @ptrCast(*Conn, state);
    if (data.len == 0) return 0;
    var outbuf: [tls.TLS_MAX_WIRE_RECORD + 64]u8 = undefined;
    const n = tls.tlsWrite(c.sess, data, outbuf[0..]) catch |e| {
        if (e == error.OutputTooSmall) return error.TooLarge;
        return error.ConnectFailed;
    };
    socketSendAll(c, outbuf[0..n]) catch |e| {
        if (e == DemoError.Timeout) return error.Timeout;
        return error.ConnectFailed;
    };
    return data.len;
}

fn trClose(state: *void) void {
    var c: *Conn = @ptrCast(*Conn, state);
    if (!c.closed) {
        std.net.close(c.fd);
        c.closed = true;
    }
}

fn readSmallFile(path: []const u8, buf: []u8) usize {
    const fd = std.io.fileOpen(path, false) orelse return 0;
    const n = std.io.fileRead(fd, buf);
    std.io.fileClose(fd);
    return n;
}

fn rssPeakKb() u64 {
    var buf: [4096]u8 = undefined;
    const n = readSmallFile("/proc/self/status", buf[0..]);
    if (n == 0) return 0;
    const raw = buf[0..n];
    const at = findFrom(raw, "VmHWM:", 0);
    if (at >= raw.len) return 0;
    var i = at + 6;
    while (i < raw.len and (raw[i] == ' ' or raw[i] == '\t')) : (i += 1) {}
    const start = i;
    while (i < raw.len and isDigit(raw[i])) : (i += 1) {}
    if (i == start) return 0;
    return parseU64(raw[start..i]) orelse 0;
}

fn cpuMs() u64 {
    var buf: [4096]u8 = undefined;
    const n = readSmallFile("/proc/self/stat", buf[0..]);
    if (n == 0) return 0;
    const raw = buf[0..n];

    var close_paren: usize = 0;
    var i: usize = 0;
    var found: bool = false;
    while (i < raw.len) : (i += 1) {
        if (raw[i] == ')') {
            close_paren = i;
            found = true;
        }
    }
    if (!found) return 0;

    var p = close_paren + 1;
    var field: usize = 2;
    var utime: u64 = 0;
    var stime: u64 = 0;
    while (p < raw.len) {
        while (p < raw.len and (raw[p] == ' ' or raw[p] == '\t' or raw[p] == '\n')) : (p += 1) {}
        if (p >= raw.len) break;
        const start = p;
        while (p < raw.len and raw[p] != ' ' and raw[p] != '\t' and raw[p] != '\n') : (p += 1) {}
        field += 1;
        if (field == 14) utime = parseU64(raw[start..p]) orelse 0;
        if (field == 15) {
            stime = parseU64(raw[start..p]) orelse 0;
            return (utime + stime) * 10;
        }
    }
    return 0;
}

fn writeU64(v: u64) void {
    var tmp: [20]u8 = undefined;
    var len: usize = 0;
    var x: u64 = v;
    if (x == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        while (x > 0) {
            tmp[len] = '0' + @intCast(u8, x % 10);
            len += 1;
            x = x / 10;
        }
    }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        buf[i] = tmp[len - 1 - i];
    }
    out(buf[0..len]);
}

fn printStatus(status: u16) void {
    out("status=");
    writeU64(@intCast(u64, status));
    out("\n");
}

fn printBody(body: []const u8) void {
    var n = body.len;
    if (n > BODY_PRINT_CAP) n = BODY_PRINT_CAP;
    if (n > 0) out(body[0..n]);
    if (n == 0 or body[n - 1] != '\n') out("\n");
}

fn printResource(status: u16, bytes: usize, arena_peak: usize, rss_peak: u64, cpu_ms: u64) void {
    out("tls_demo ok status=");
    writeU64(@intCast(u64, status));
    out(" bytes=");
    writeU64(@intCast(u64, bytes));
    out(" arena_peak=");
    writeU64(@intCast(u64, arena_peak));
    out(" rss_peak=");
    writeU64(rss_peak);
    out(" cpu_ms=");
    writeU64(cpu_ms);
    out("\n");
}

fn loadStore(path: []const u8) DemoError!void {
    const raw = filemod.readAll(&g_store_arena, path) catch return DemoError.StoreRead;
    x509.trustStoreLoad(&g_store_arena, raw, &g_store) catch |e| {
        if (e == error.OutOfMemory) return DemoError.OutOfMemory;
        return DemoError.StoreCorrupt;
    };
}

fn run(argc: i32, argv: [*][*]u8) DemoError!void {
    const n: usize = @intCast(usize, argc);
    if (n > 4) return DemoError.BadArgs;

    var url: []const u8 = DEFAULT_URL;
    if (n >= 2) url = argAt(argv, 1);

    var store_path: []const u8 = "ca_store.bin";
    if (n >= 3) {
        store_path = argAt(argv, 2);
    } else if (!filemod.exists(store_path)) {
        store_path = "examples/z98/demo/tls_demo/ca_store.bin";
    }

    var now_unix: i64 = 0;
    if (n >= 4) {
        now_unix = parseI64Clock(argAt(argv, 3)) orelse return DemoError.BadArgs;
        if (now_unix <= 0) return DemoError.Time;
    } else {
        now_unix = std.time.wallClockUnix();
        if (now_unix < 946684800 or now_unix > 4102444800) return DemoError.Time;
    }

    try loadStore(store_path);

    var c = try openTls(url, now_unix);
    var transport = http.HttpTransport{
        .state = @ptrCast(*void, &c),
        .read_fn = trRead,
        .write_fn = trWrite,
        .close_fn = trClose,
    };

    var resp: http.Response = undefined;
    http.httpGetOver(&g_arena, &transport, url, &resp) catch |e| {
        if (e == error.BadUrl) return DemoError.HttpBadUrl;
        if (e == error.BadResponse) return DemoError.HttpBadResponse;
        if (e == error.TooLarge) return DemoError.HttpTooLarge;
        if (e == error.Timeout) return DemoError.Timeout;
        if (e == error.OutOfMemory) return DemoError.OutOfMemory;
        if (e == error.DnsFailed) return DemoError.DnsFailed;
        return DemoError.HttpFailed;
    };

    printStatus(resp.status);
    printBody(resp.body);
    printResource(resp.status, resp.body.len, g_arena.used, rssPeakKb(), cpuMs());
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    std.net.init();
    run(argc, argv) catch |e| {
        std.net.cleanup();
        fail(e);
    };
    std.net.cleanup();
    std.os.exit(0);
}
