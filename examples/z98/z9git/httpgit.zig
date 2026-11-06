// httpgit.zig -- z9git smart HTTP (v0) clone with streaming pack download.
//
// Flow: GET <repo>/info/refs?service=git-upload-pack (ref discovery +
// capabilities), POST <repo>/git-upload-pack with one `want <sha>` per
// advertised ref plus `done`, stream the de-chunked response through
// std_http.httpPostStreamOver, split the leading ACK/NAK pkt-lines from the
// raw PACK body, hash/write the pack on the flow, verify its 20-byte trailer,
// synthesize the .idx with pack.idxSynthesize, install refs/HEAD, and check
// the HEAD tree out into the worktree.
//
// Transport: http:// is std_net TCP; https:// is std_net TCP + std_tls with a
// std_x509.TrustStore. The TLS glue is local to this app (same recipe as
// examples/z98/demo/tls_demo). The trust store defaults to ca_store.bin in the
// CWD, then next to the executable, then the repo tree path
// examples/z98/demo/tls_demo/ca_store.bin. There is deliberately no --ca flag.
//
// Pacing: --max-down is KB/s in the CLI; main converts it to bytes/s here.
// The sink sleeps when the bytes downloaded so far are ahead of
// bytes/rate (z9torr-style). 0 disables pacing.
//
// No sideband, no multi_ack, no thin packs. Z98 subset only; direct imports.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const os = @import("std_os.zig");
const crypto = @import("std_crypto.zig");
const http = @import("std_http.zig");
const net = @import("std_net.zig");
const tls = @import("std_tls.zig");
const x509 = @import("std_x509.zig");
const rand = @import("std_rand.zig");
const time = @import("std_time.zig");
const pkt = @import("pkt.zig");
const pack_mod = @import("pack.zig");
const repo = @import("repo.zig");

const CONNECT_TIMEOUT_MS: u32 = 15000;
const IO_TIMEOUT_MS: u32 = 15000;

const KIND_IO: u8 = 1;
const KIND_PROTOCOL: u8 = 2;
const KIND_DISK_FULL: u8 = 3;

const DISK_GUARD_BYTES: u64 = 4 * 1024 * 1024;
const SHALLOW_MAX: usize = 4096;
const MAX_ATTEMPTS: usize = 4;



pub const OpenError = error{ Transport, OutOfMemory };

// The caller supplies one fresh transport connection per request.
pub const TransportFactory = struct {
    state: *void,
    open_fn: fn (*void, []const u8) OpenError!http.HttpTransport,
};

const Scheme = enum { http, https };

const UrlParts = struct {
    scheme: Scheme,
    host: []const u8,
    port: u16,
    base_url: []const u8,
};

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn startsWith(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        if (s[i] != prefix[i]) return false;
    }
    return true;
}

fn endsWith(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        if (s[s.len - suffix.len + i] != suffix[i]) return false;
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

fn findByte(hay: []const u8, needle: u8, from: usize) usize {
    if (from > hay.len) return hay.len;
    var i: usize = from;
    while (i < hay.len) : (i += 1) {
        if (hay[i] == needle) return i;
    }
    return hay.len;
}

fn hexVal(c: u8) i32 {
    if (c >= '0' and c <= '9') return @intCast(i32, c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(i32, c - 'a') + 10;
    if (c >= 'A' and c <= 'F') return @intCast(i32, c - 'A') + 10;
    return -1;
}

fn hexOut(out: []u8, v: u8) void {
    const hi = v >> 4;
    const lo = v & 0x0f;
    out[0] = if (hi < 10) '0' + hi else 'a' + (hi - 10);
    out[1] = if (lo < 10) '0' + lo else 'a' + (lo - 10);
}

fn hexId(id: [20]u8, out: []u8) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        hexOut(out[i * 2 .. i * 2 + 2], id[i]);
    }
}

fn parseId(s: []const u8, out: *[20]u8) bool {
    if (s.len != 40) return false;
    var id: [20]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const hi = hexVal(s[i * 2]);
        const lo = hexVal(s[i * 2 + 1]);
        if (hi < 0 or lo < 0) return false;
        id[i] = @intCast(u8, hi * 16 + lo);
    }
    i = 0;
    while (i < 20) : (i += 1) out[i] = id[i];
    return true;
}

fn idEql(a: [20]u8, b: [20]u8) bool {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn parsePort(s: []const u8) ?u16 {
    if (s.len == 0) return null;
    var v: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u32, c - '0');
        if (v > 65535) return null;
    }
    if (v == 0) return null;
    return @intCast(u16, v);
}

fn parseUrl(url: []const u8) OpenError!UrlParts {
    const sep = findFrom(url, "://", 0);
    if (sep >= url.len) return error.Transport;
    const scheme_s = url[0..sep];
    var scheme: Scheme = .http;
    var default_port: u16 = 80;
    if (eq(scheme_s, "http")) {
        scheme = .http;
        default_port = 80;
    } else if (eq(scheme_s, "https")) {
        scheme = .https;
        default_port = 443;
    } else {
        return error.Transport;
    }
    const auth_start = sep + 3;
    var auth_end = auth_start;
    while (auth_end < url.len and url[auth_end] != '/' and url[auth_end] != '?') : (auth_end += 1) {}
    if (auth_end == auth_start) return error.Transport;
    const authority = url[auth_start..auth_end];
    var host = authority;
    var port = default_port;
    const colon = findByte(authority, ':', 0);
    if (colon < authority.len) {
        host = authority[0..colon];
        port = parsePort(authority[colon + 1 ..]) orelse return error.Transport;
    }
    if (host.len == 0) return error.Transport;

    var path_end = url.len;
    const qs = findByte(url, '?', auth_end);
    if (qs < path_end) path_end = qs;
    var base_end = path_end;
    while (base_end > auth_start and url[base_end - 1] == '/') base_end -= 1;
    return UrlParts{ .scheme = scheme, .host = host, .port = port, .base_url = url[0..base_end] };
}

fn joinUrl(arena: *arena_mod.Arena, a: []const u8, b: []const u8) OpenError![]u8 {
    const n = a.len + b.len;
    const raw = arena_mod.alloc(arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    i = 0;
    while (i < b.len) : (i += 1) raw[a.len + i] = b[i];
    return raw[0..n];
}


// --- plain TCP and TLS transports -------------------------------------------

const TcpConn = struct {
    fd: i32,
    closed: bool,
};

const TlsConn = struct {
    fd: i32,
    sess: *tls.TlsSession,
    closed: bool,
};

var g_empty_byte: [1]u8 = undefined;
var g_net_inited: bool = false;
var g_tls_session: tls.TlsSession = undefined;
var g_tls_rng: rand.Xoshiro256 = undefined;


fn ensureNet() OpenError!void {
    if (g_net_inited) return;
    if (net.init() != 0) return error.Transport;
    g_net_inited = true;
}

fn waitRead(fd: i32, ms: u32) OpenError!void {
    var fds: net.fd_set = undefined;
    net.fdZero(@ptrCast(*u8, &fds));
    net.fdSet(fd, @ptrCast(*u8, &fds));
    const sr = net.select(fd + 1, @ptrCast(*u8, &fds), null, null, @intCast(i32, ms));
    if (sr == 0) return error.Transport;
    if (sr < 0) return error.Transport;
}

fn waitWrite(fd: i32, ms: u32) OpenError!void {
    var fds: net.fd_set = undefined;
    net.fdZero(@ptrCast(*u8, &fds));
    net.fdSet(fd, @ptrCast(*u8, &fds));
    const sr = net.select(fd + 1, null, @ptrCast(*u8, &fds), null, @intCast(i32, ms));
    if (sr == 0) return error.Transport;
    if (sr < 0) return error.Transport;
}

fn rawRecv(fd: i32, buf: []u8) OpenError!usize {
    if (buf.len == 0) return 0;
    while (true) {
        try waitRead(fd, IO_TIMEOUT_MS);
        var sock: net.Socket = fd;
        const n = net.recvNonBlocking(&sock, buf) catch |e| {
            if (e == error.WouldBlock) continue;
            return error.Transport;
        };
        return n;
    }
}

fn rawSendAll(fd: i32, data: []const u8) OpenError!void {
    var sent: usize = 0;
    while (sent < data.len) {
        try waitWrite(fd, IO_TIMEOUT_MS);
        var sock: net.Socket = fd;
        const n = net.sendNonBlocking(&sock, data[sent..]) catch |e| {
            if (e == error.WouldBlock) continue;
            return error.Transport;
        };
        if (n == 0) return error.Transport;
        sent += n;
    }
}

fn tcpRead(state: *void, buf: []u8) !usize {
    var c: *TcpConn = @ptrCast(*TcpConn, state);
    if (c.closed) return 0;
    return rawRecv(c.fd, buf) catch return error.ConnectFailed;
}

fn tcpWrite(state: *void, data: []const u8) !usize {
    var c: *TcpConn = @ptrCast(*TcpConn, state);
    if (c.closed) return error.ConnectFailed;
    rawSendAll(c.fd, data) catch return error.ConnectFailed;
    return data.len;
}

fn tcpClose(state: *void) void {
    var c: *TcpConn = @ptrCast(*TcpConn, state);
    if (!c.closed) {
        net.close(c.fd);
        c.closed = true;
    }
}

fn tlsHandshake(c: *TlsConn) OpenError!void {
    var outbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var inbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var act = tls.tlsStep(c.sess, "", outbuf[0..]) catch return error.Transport;
    var guard: usize = 0;
    while (true) {
        guard += 1;
        if (guard > 100000) return error.Transport;
        switch (act) {
            .send => |bytes| {
                rawSendAll(c.fd, bytes) catch return error.Transport;
                act = tls.tlsStep(c.sess, "", outbuf[0..]) catch return error.Transport;
            },
            .recv => {
                const n = rawRecv(c.fd, inbuf[0..]) catch return error.Transport;
                if (n == 0) return error.Transport;
                act = tls.tlsStep(c.sess, inbuf[0..n], outbuf[0..]) catch return error.Transport;
            },
            .wait => {
                const n = rawRecv(c.fd, inbuf[0..]) catch return error.Transport;
                if (n == 0) return error.Transport;
                act = tls.tlsStep(c.sess, inbuf[0..n], outbuf[0..]) catch return error.Transport;
            },
            .established => {
                return;
            },
            .closed => return error.Transport,
            else => return error.Transport,
        }
    }
}

fn tlsReadApp(c: *TlsConn, buf: []u8) !usize {
    if (buf.len == 0) return 0;
    var outbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var inbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    while (true) {
        const got = tls.tlsRead(c.sess, buf) catch return error.BadResponse;
        if (got > 0) return got;
        if (c.closed) return 0;
        const n = rawRecv(c.fd, inbuf[0..]) catch return error.ConnectFailed;
        if (n == 0) {
            c.closed = true;
            return 0;
        }
        var act = tls.tlsStep(c.sess, inbuf[0..n], outbuf[0..]) catch return error.BadResponse;
        var guard: usize = 0;
        while (true) {
            guard += 1;
            if (guard > 64) return error.BadResponse;
            switch (act) {
                .send => |bytes| {
                    rawSendAll(c.fd, bytes) catch return error.ConnectFailed;
                    act = tls.tlsStep(c.sess, "", outbuf[0..]) catch return error.BadResponse;
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

fn tlsRead(state: *void, buf: []u8) !usize {
    var c: *TlsConn = @ptrCast(*TlsConn, state);
    return tlsReadApp(c, buf);
}

fn tlsWrite(state: *void, data: []const u8) !usize {
    var c: *TlsConn = @ptrCast(*TlsConn, state);
    if (data.len == 0) return 0;
    var outbuf: [tls.TLS_MAX_WIRE_RECORD + 64]u8 = undefined;
    var off: usize = 0;
    while (off < data.len) {
        var take = data.len - off;
        if (take > tls.TLS_MAX_PLAINTEXT_RECORD) take = tls.TLS_MAX_PLAINTEXT_RECORD;
        const n = tls.tlsWrite(c.sess, data[off .. off + take], outbuf[0..]) catch return error.TooLarge;
        rawSendAll(c.fd, outbuf[0..n]) catch return error.ConnectFailed;
        off += take;
    }
    return data.len;
}

fn tlsClose(state: *void) void {
    var c: *TlsConn = @ptrCast(*TlsConn, state);
    if (!c.closed) {
        net.close(c.fd);
        c.closed = true;
    }
}

fn dirname(path: []const u8) []const u8 {
    var cut = path.len;
    while (cut > 0) {
        if (path[cut - 1] == '/' or path[cut - 1] == '\\') break;
        cut -= 1;
    }
    if (cut == 0) return "";
    return path[0 .. cut - 1];
}

fn loadDefaultStore(arena: *arena_mod.Arena, store: *x509.TrustStore) OpenError!void {
    var path: []const u8 = "ca_store.bin";
    if (!file_mod.exists(path)) {
        const argv0 = os.argv(0);
        const dir = dirname(argv0);
        if (dir.len > 0) {
            const alt = joinUrl(arena, dir, "/ca_store.bin") catch return error.OutOfMemory;
            if (file_mod.exists(alt)) {
                path = alt;
            } else {
                path = "examples/z98/demo/tls_demo/ca_store.bin";
            }
        } else {
            path = "examples/z98/demo/tls_demo/ca_store.bin";
        }
    }
    const raw = file_mod.readAll(arena, path) catch return error.Transport;
    x509.trustStoreLoad(arena, raw, store) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Transport;
    };
}

const RealFactory = struct {
    scheme: Scheme,
    arena: *arena_mod.Arena,
    store_loaded: bool,
    store: x509.TrustStore,
};

fn openReal(factory_state: *void, url: []const u8) OpenError!http.HttpTransport {
    var rf: *RealFactory = @ptrCast(*RealFactory, factory_state);
    const parts = try parseUrl(url);
    try ensureNet();
    const ip = net.resolve(parts.host) catch return error.Transport;
    const fd = net.tcpSocket() catch return error.Transport;
    net.connectToIp(fd, ip, parts.port, CONNECT_TIMEOUT_MS) catch {
        net.close(fd);
        return error.Transport;
    };

    if (rf.scheme == .http) {
        const raw = arena_mod.alloc(rf.arena, @sizeOf(TcpConn)) catch return error.OutOfMemory;
        const c: *TcpConn = @ptrCast(*TcpConn, raw);
        c.* = TcpConn{ .fd = fd, .closed = false };
        return http.HttpTransport{
            .state = @ptrCast(*void, c),
            .read_fn = tcpRead,
            .write_fn = tcpWrite,
            .close_fn = tcpClose,
        };
    }

    if (!rf.store_loaded) {
        try loadDefaultStore(rf.arena, &rf.store);
        rf.store_loaded = true;
    }
    var now_unix = time.wallClockUnix();
    if (now_unix <= 0) now_unix = 1;
    const seed: u64 = @intCast(u64, now_unix) ^ time.highRes() ^ @intCast(u64, fd);
    g_tls_rng = rand.xoshiroInit(seed);
    var cfg = tls.TlsConfig{
        .hostname = parts.host,
        .store = &rf.store,
        .rng = &g_tls_rng,
        .now_unix = now_unix,
        .min_version = tls.TLS_VERSION_12,
        .max_version = tls.TLS_VERSION_13,
    };
    tls.tlsInit(&g_tls_session, &cfg);
    const raw = arena_mod.alloc(rf.arena, @sizeOf(TlsConn)) catch return error.OutOfMemory;
    const c: *TlsConn = @ptrCast(*TlsConn, raw);
    c.* = TlsConn{ .fd = fd, .sess = &g_tls_session, .closed = false };
    tlsHandshake(c) catch {
        net.close(fd);
        return error.Transport;
    };
    return http.HttpTransport{
        .state = @ptrCast(*void, c),
        .read_fn = tlsRead,
        .write_fn = tlsWrite,
        .close_fn = tlsClose,
    };
}

// --- ref discovery ----------------------------------------------------------

const Ref = struct { name: []const u8, id: [20]u8 };

const RefList = struct {
    items: []Ref,
    len: usize,
    cap: usize,
};

fn refAppend(arena: *arena_mod.Arena, list: *RefList, name: []const u8, id: [20]u8) repo.GitError!void {
    if (list.len == list.cap) {
        var ncap: usize = 16;
        if (list.cap != 0) ncap = list.cap * 2;
        const raw = arena_mod.alloc(arena, ncap * @sizeOf(Ref)) catch return error.OutOfMemory;
        const next = @ptrCast([*]Ref, raw)[0..ncap];
        var i: usize = 0;
        while (i < list.len) : (i += 1) next[i] = list.items[i];
        list.items = next;
        list.cap = ncap;
    }
    list.items[list.len].name = name;
    var i: usize = 0;
    while (i < 20) : (i += 1) list.items[list.len].id[i] = id[i];
    list.len += 1;
}

const Discovery = struct {
    refs: []Ref,
    head_id: [20]u8,
    has_head: bool,
    head_target: []const u8,
};

fn trimEol(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == '\n' or s[end - 1] == '\r')) end -= 1;
    return s[0..end];
}

fn findSymref(caps: []const u8) []const u8 {
    var i: usize = 0;
    while (i < caps.len) {
        while (i < caps.len and (caps[i] == ' ' or caps[i] == '\t')) : (i += 1) {}
        var j = i;
        while (j < caps.len and caps[j] != ' ' and caps[j] != '\t') : (j += 1) {}
        const tok = caps[i..j];
        if (startsWith(tok, "symref=HEAD:")) return tok[12..];
        i = j;
    }
    return "";
}

fn parseDiscovery(arena: *arena_mod.Arena, body: []const u8) repo.GitError!Discovery {
    const raw0 = arena_mod.alloc(arena, 16 * @sizeOf(Ref)) catch return error.OutOfMemory;
    var list = RefList{
        .items = @ptrCast([*]Ref, raw0)[0..16],
        .len = 0,
        .cap = 16,
    };
    var saw_service = false;
    var caps_done = false;
    var head_id: [20]u8 = undefined;
    var hz: usize = 0;
    while (hz < 20) : (hz += 1) head_id[hz] = 0;
    var has_head = false;
    var head_target: []const u8 = "";
    var pos: usize = 0;
    while (true) {
        const maybe = pkt.decodeAt(body, pos) catch return error.Protocol;
        const p = maybe orelse break;
        pos += p.total_len;
        if (!saw_service) {
            if (p.kind != .data) return error.Protocol;
            const line = trimEol(p.payload);
            if (!eq(line, "# service=git-upload-pack")) return error.Protocol;
            saw_service = true;
            continue;
        }
        if (p.kind != .data) continue;
        var line = trimEol(p.payload);
        if (line.len == 0) continue;

        var caps: []const u8 = "";
        const nul = findByte(line, 0, 0);
        if (nul < line.len) {
            caps = line[nul + 1 ..];
            line = line[0..nul];
        }
        if (!caps_done and caps.len != 0) {
            head_target = findSymref(caps);
            caps_done = true;
        }
        if (line.len < 41 or line[40] != ' ') return error.Protocol;
        var id: [20]u8 = undefined;
        if (!parseId(line[0..40], &id)) return error.Protocol;
        const name = line[41..];
        if (name.len == 0) return error.Protocol;
        if (eq(name, "HEAD")) {
            var hk: usize = 0;
            while (hk < 20) : (hk += 1) head_id[hk] = id[hk];
            has_head = true;
            continue;
        }
        if (endsWith(name, "^{}")) continue;
        if (startsWith(name, "refs/pull/")) continue;
        try refAppend(arena, &list, name, id);
    }
    if (!saw_service or list.len == 0) return error.Protocol;
    var d: Discovery = undefined;
    d.refs = list.items[0..list.len];
    var k: usize = 0;
    while (k < 20) : (k += 1) d.head_id[k] = head_id[k];
    d.has_head = has_head;
    d.head_target = head_target;
    return d;
}

fn copyAt(dst: []u8, pos: *usize, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[pos.* + i] = src[i];
    }
    pos.* += src.len;
}

fn appendDecAt(dst: []u8, pos: *usize, v0: u64) void {
    var tmp: [24]u8 = undefined;
    var n: usize = 0;
    var v = v0;
    if (v == 0) {
        dst[pos.*] = '0';
        pos.* += 1;
        return;
    }
    while (v != 0) : (v = v / 10) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        n += 1;
    }
    var i: usize = n;
    while (i > 0) : (i -= 1) {
        dst[pos.*] = tmp[i - 1];
        pos.* += 1;
    }
}

fn collectWanted(arena: *arena_mod.Arena, refs: []const Ref, out_raw: *[]u8, out_count: *usize) repo.GitError!void {
    const ids_raw = arena_mod.alloc(arena, refs.len * 20) catch return error.OutOfMemory;
    var count: usize = 0;
    var i: usize = 0;
    while (i < refs.len) : (i += 1) {
        var dup = false;
        var j: usize = 0;
        while (j < count) : (j += 1) {
            var same = true;
            var k: usize = 0;
            while (k < 20) : (k += 1) {
                if (ids_raw[j * 20 + k] != refs[i].id[k]) {
                    same = false;
                    break;
                }
            }
            if (same) {
                dup = true;
                break;
            }
        }
        if (dup) continue;
        var k: usize = 0;
        while (k < 20) : (k += 1) ids_raw[count * 20 + k] = refs[i].id[k];
        count += 1;
    }
    if (count == 0) return error.Protocol;
    out_raw.* = ids_raw[0 .. count * 20];
    out_count.* = count;
}

fn buildRequestEx(arena: *arena_mod.Arena, want_raw: []const u8, want_count: usize, have_raw: []const u8, have_count: usize, depth: u32, deepen_relative: bool, shallow_raw: []const u8, shallow_count: usize, partial: bool) repo.GitError![]u8 {
    var caps_buf: [64]u8 = undefined;
    var caps_len: usize = 0;
    const base_caps: []const u8 = " ofs-delta";

    var bi: usize = 0;
    while (bi < base_caps.len) : (bi += 1) {
        caps_buf[caps_len] = base_caps[bi];
        caps_len += 1;
    }
    if (deepen_relative) {
        const s: []const u8 = " deepen-relative";
        bi = 0;

        while (bi < s.len) : (bi += 1) {
            caps_buf[caps_len] = s[bi];
            caps_len += 1;
        }
    }
    if (partial) {
        const s: []const u8 = " filter";

        bi = 0;
        while (bi < s.len) : (bi += 1) {
            caps_buf[caps_len] = s[bi];
            caps_len += 1;
        }
    }
    const per_want = 4 + 46 + caps_len;
    const total = want_count * per_want + shallow_count * 53 + 64 + have_count * 50 + 13;
    const raw = arena_mod.alloc(arena, total) catch return error.OutOfMemory;
    const body = raw[0..total];
    var pos: usize = 0;
    var i: usize = 0;
    while (i < want_count) : (i += 1) {
        var payload: [128]u8 = undefined;
        payload[0] = 'w';
        payload[1] = 'a';
        payload[2] = 'n';
        payload[3] = 't';
        payload[4] = ' ';
        var id: [20]u8 = undefined;
        var k: usize = 0;
        while (k < 20) : (k += 1) id[k] = want_raw[i * 20 + k];
        hexId(id, payload[5..45]);
        var plen: usize = 45;
        if (i == 0) {
            var c: usize = 0;
            while (c < caps_len) : (c += 1) {
                payload[plen] = caps_buf[c];
                plen += 1;
            }
        }
        payload[plen] = '\n';
        plen += 1;
        pos += pkt.encode(body[pos..], payload[0..plen]) catch return error.Protocol;
    }
    i = 0;
    while (i < shallow_count) : (i += 1) {
        var payload: [64]u8 = undefined;
        const prefix: []const u8 = "shallow ";
        var p: usize = 0;
        while (p < prefix.len) : (p += 1) payload[p] = prefix[p];

        var id: [20]u8 = undefined;
        var k: usize = 0;
        while (k < 20) : (k += 1) id[k] = shallow_raw[i * 20 + k];
        hexId(id, payload[8..48]);
        payload[48] = '\n';
        pos += pkt.encode(body[pos..], payload[0..49]) catch return error.Protocol;
    }
    if (depth > 0) {
        var payload: [32]u8 = undefined;
        var p: usize = 0;
        const prefix: []const u8 = "deepen ";
        copyAt(payload[0..], &p, prefix);

        appendDecAt(payload[0..], &p, @intCast(u64, depth));
        payload[p] = '\n';
        p += 1;
        pos += pkt.encode(body[pos..], payload[0..p]) catch return error.Protocol;
    }
    if (partial) {
        pos += pkt.encode(body[pos..], "filter blob:none\n") catch return error.Protocol;
    }
    pos += pkt.encodeFlush(body[pos..]) catch return error.Protocol;
    i = 0;
    while (i < have_count) : (i += 1) {
        var payload: [64]u8 = undefined;
        const prefix: []const u8 = "have ";

        var p: usize = 0;
        while (p < prefix.len) : (p += 1) payload[p] = prefix[p];
        var id: [20]u8 = undefined;
        var k: usize = 0;
        while (k < 20) : (k += 1) id[k] = have_raw[i * 20 + k];
        hexId(id, payload[5..45]);
        payload[45] = '\n';
        pos += pkt.encode(body[pos..], payload[0..46]) catch return error.Protocol;
    }
    pos += pkt.encode(body[pos..], "done\n") catch return error.Protocol;
    return body[0..pos];
}

fn buildRequest(arena: *arena_mod.Arena, refs: []const Ref) repo.GitError![]u8 {
    var want_raw: []u8 = undefined;
    var want_count: usize = 0;
    try collectWanted(arena, refs, &want_raw, &want_count);
    return buildRequestEx(arena, want_raw, want_count, want_raw, 0, 0, false, want_raw, 0, false);
}


// --- streaming pack sink ----------------------------------------------------

const Phase = enum { len, payload, pack };

const PackSink = struct {
    file: file_mod.File,
    hasher: crypto.Sha1,
    hold: [20]u8,
    hold_pos: usize,
    hold_len: usize,
    phase: Phase,
    len_buf: [4]u8,
    len_pos: usize,
    pkt_remain: usize,
    pkt_total: usize,
    pkt_head: [64]u8,
    pkt_head_len: usize,
    pack_started: bool,
    pack_bytes: u64,
    max_down_bps: u32,
    pace_start: u64,
    fail_kind: u8,
    head: *http.Response,
    dest_git: []const u8,
    preflight_done: bool,
    have_cl: u64,
    pack_count: u64,
    guard_next: u64,
    pack_hdr: [12]u8,
    pack_hdr_len: usize,
    shallow_raw: [SHALLOW_MAX * 20]u8,
    shallow_count: usize,
};


fn sinkFail(s: *PackSink, kind: u8) http.HttpError {
    s.fail_kind = kind;
    return error.BadResponse;
}

fn writeFileAll(f: *file_mod.File, data: []const u8) bool {
    var off: usize = 0;
    while (off < data.len) {
        const n = file_mod.write(f, data[off..]) catch return false;
        if (n == 0) return false;
        off += n;
    }
    return true;
}

fn guardDownloadSpace(s: *PackSink) http.HttpError!void {
    if (s.guard_next == 0 or s.pack_bytes < s.guard_next) return;
    const est = if (s.have_cl > 0) s.have_cl else s.pack_bytes;
    repo.diskPreflightEstimate(s.dest_git, est, s.pack_count) catch return sinkFail(s, KIND_DISK_FULL);
    if (s.pack_bytes > 0xFFFFFFFFFFFFFFFF - DISK_GUARD_BYTES) {
        s.guard_next = 0xFFFFFFFFFFFFFFFF;
    } else {
        s.guard_next = s.pack_bytes + DISK_GUARD_BYTES;
    }
}

fn packWriteBytes(s: *PackSink, data: []const u8) http.HttpError!void {
    if (!writeFileAll(&s.file, data)) return sinkFail(s, KIND_IO);
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        if (s.hold_len < 20) {
            s.hold[s.hold_len] = data[i];
            s.hold_len += 1;
        } else {
            var one: [1]u8 = undefined;
            one[0] = s.hold[s.hold_pos];
            crypto.sha1Update(&s.hasher, one[0..1]);
            s.hold[s.hold_pos] = data[i];
            s.hold_pos = (s.hold_pos + 1) % 20;
        }
    }
    s.pack_started = true;
    s.pack_bytes += @intCast(u64, data.len);
    try guardDownloadSpace(s);
    if (s.max_down_bps != 0) {
        if (s.pace_start == 0) s.pace_start = time.highRes();
        const target_ms: u64 = s.pack_bytes * 1000 / @intCast(u64, s.max_down_bps);
        const now = time.highRes();
        const freq = time.highResFreq();
        var elapsed_ms: u64 = 0;
        if (freq != 0) elapsed_ms = (now - s.pace_start) * 1000 / freq;
        if (elapsed_ms < target_ms) {
            var diff = target_ms - elapsed_ms;
            if (diff > 600000) diff = 600000;
            time.sleepMs(@intCast(u32, diff));
        }
    }
}


fn packDecorate(s: *PackSink, data: []const u8) http.HttpError!void {
    if (!s.preflight_done) {
        if (s.have_cl == 0) s.have_cl = headerU64(s.head, "Content-Length");
        // Always read the 12-byte PACK header first so the preflight gets the
        // object count even when Content-Length is present; it selects the
        // idx/temp/worktree estimate. Nothing is written before this check.
        const need = 12 - s.pack_hdr_len;
        var take = data.len;
        if (take > need) take = need;
        var i: usize = 0;
        while (i < take) : (i += 1) s.pack_hdr[s.pack_hdr_len + i] = data[i];
        s.pack_hdr_len += take;
        if (s.pack_hdr_len < 12) return;
        const count = packCount(s.pack_hdr[0..]);
        repo.diskPreflightEstimate(s.dest_git, s.have_cl, count) catch return sinkFail(s, KIND_DISK_FULL);
        s.pack_count = count;
        s.guard_next = s.pack_bytes + DISK_GUARD_BYTES;
        s.preflight_done = true;
        try packWriteBytes(s, s.pack_hdr[0..12]);
        if (take < data.len) try packWriteBytes(s, data[take..]);
        return;
    }
    try packWriteBytes(s, data);
}

fn shallowAdd(s: *PackSink, id: [20]u8) void {
    var i: usize = 0;
    while (i < s.shallow_count) : (i += 1) {
        var same = true;
        var k: usize = 0;
        while (k < 20) : (k += 1) {
            if (s.shallow_raw[i * 20 + k] != id[k]) {
                same = false;
                break;
            }
        }
        if (same) return;
    }
    if (s.shallow_count >= SHALLOW_MAX) return;
    var k: usize = 0;
    while (k < 20) : (k += 1) s.shallow_raw[s.shallow_count * 20 + k] = id[k];
    s.shallow_count += 1;
}

fn shallowRemove(s: *PackSink, id: [20]u8) void {
    var i: usize = 0;
    while (i < s.shallow_count) : (i += 1) {
        var same = true;
        var k: usize = 0;
        while (k < 20) : (k += 1) {
            if (s.shallow_raw[i * 20 + k] != id[k]) {
                same = false;
                break;
            }
        }
        if (same) {
            var j: usize = i;
            while (j + 1 < s.shallow_count) : (j += 1) {
                var m: usize = 0;
                while (m < 20) : (m += 1) {
                    s.shallow_raw[j * 20 + m] = s.shallow_raw[(j + 1) * 20 + m];
                }
            }
            s.shallow_count -= 1;
            return;
        }
    }
}

fn pktPayloadDone(s: *PackSink) http.HttpError!void {
    const plen = s.pkt_total - 4;
    const hlen = s.pkt_head_len;
    var is_nak = false;
    var is_ack = false;
    var is_err = false;
    if (plen == 4 and hlen == 4) {
        if (s.pkt_head[0] == 'N' and s.pkt_head[1] == 'A' and s.pkt_head[2] == 'K' and s.pkt_head[3] == '\n') is_nak = true;
    }
    if (hlen >= 4) {
        if (s.pkt_head[0] == 'A' and s.pkt_head[1] == 'C' and s.pkt_head[2] == 'K' and s.pkt_head[3] == ' ') is_ack = true;
        if (s.pkt_head[0] == 'E' and s.pkt_head[1] == 'R' and s.pkt_head[2] == 'R' and s.pkt_head[3] == ' ') is_err = true;
    }
    if (is_err) return sinkFail(s, KIND_PROTOCOL);
    if (hlen >= 48 and startsWith(s.pkt_head[0..hlen], "shallow ")) {
        var id: [20]u8 = undefined;
        if (parseId(s.pkt_head[8..48], &id)) shallowAdd(s, id);
        s.phase = .len;
        return;
    }
    if (hlen >= 50 and startsWith(s.pkt_head[0..hlen], "unshallow ")) {
        var id: [20]u8 = undefined;
        if (parseId(s.pkt_head[10..50], &id)) shallowRemove(s, id);
        s.phase = .len;
        return;
    }

    if (is_nak or is_ack) {
        s.phase = .pack;
        return;
    }
    return sinkFail(s, KIND_PROTOCOL);
}

fn packSinkWrite(state: *void, data: []const u8) http.HttpError!void {
    var s: *PackSink = @ptrCast(*PackSink, state);
    if (s.head.status >= 300 and s.head.status <= 399) return;
    var off: usize = 0;

    while (off < data.len) {
        switch (s.phase) {
            .pack => {
                try packDecorate(s, data[off..]);
                return;
            },
            .len => {
                const want = 4 - s.len_pos;
                var take = data.len - off;
                if (take > want) take = want;
                var i: usize = 0;
                while (i < take) : (i += 1) s.len_buf[s.len_pos + i] = data[off + i];
                s.len_pos += take;
                off += take;
                if (s.len_pos == 4) {
                    s.len_pos = 0;
                    const v = pkt.parseLen(s.len_buf[0..4]) catch return sinkFail(s, KIND_PROTOCOL);
                    if (v == 0 or v == 1 or v == 2) {
                        continue;
                    }
                    if (v < 4) return sinkFail(s, KIND_PROTOCOL);
                    s.pkt_total = @intCast(usize, v);
                    s.pkt_remain = s.pkt_total - 4;
                    s.pkt_head_len = 0;
                    s.phase = .payload;
                }
            },
            .payload => {
                var take = data.len - off;
                if (take > s.pkt_remain) take = s.pkt_remain;
                var i: usize = 0;
                while (i < take) : (i += 1) {
                    if (s.pkt_head_len < s.pkt_head.len) {
                        s.pkt_head[s.pkt_head_len] = data[off + i];
                        s.pkt_head_len += 1;
                    }
                }
                s.pkt_remain -= take;
                off += take;
                if (s.pkt_remain == 0) {
                    try pktPayloadDone(s);
                }
            },
            else => return sinkFail(s, KIND_PROTOCOL),
        }
    }
}

fn trailerOrder(s: *PackSink, out: *[20]u8) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) out[i] = s.hold[(s.hold_pos + i) % 20];
}

fn removeIfExists(path: []const u8) void {
    file_mod.remove(path) catch {};
}

fn openTransport(factory: *const TransportFactory, url: []const u8) repo.GitError!http.HttpTransport {
    const t = factory.open_fn(factory.state, url) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Transport;
    };
    return t;
}

fn headerNameEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        var ca = a[i];
        var cb = b[i];
        if (ca >= 'A' and ca <= 'Z') ca = ca + 32;
        if (cb >= 'A' and cb <= 'Z') cb = cb + 32;
        if (ca != cb) return false;
    }
    return true;
}

fn headerU64(head: *http.Response, name: []const u8) u64 {
    var i: usize = 0;
    while (i < head.headers.len) : (i += 1) {
        if (headerNameEq(head.headers[i].name, name)) {
            const v = head.headers[i].value;
            var n: u64 = 0;
            var any = false;
            var k: usize = 0;
            while (k < v.len) : (k += 1) {
                const c = v[k];
                if (c == ' ' or c == '\t') continue;
                if (c < '0' or c > '9') return 0;
                const d: u64 = @intCast(u64, c - '0');
                if (n > (0xFFFFFFFFFFFFFFFF - d) / 10) return 0;
                n = n * 10 + d;
                any = true;
            }
            if (any) return n;
            return 0;
        }
    }
    return 0;
}

fn packCount(hdr: []const u8) u64 {
    var c: u64 = @intCast(u64, hdr[8]);
    c = (c << 8) | @intCast(u64, hdr[9]);
    c = (c << 8) | @intCast(u64, hdr[10]);
    c = (c << 8) | @intCast(u64, hdr[11]);
    return c;
}

// --- resume state, redirects and multi-attempt download ---------------------

const State = struct {
    url: []const u8,
    depth: u32,
    partial: bool,
    shallow_raw: []u8,
    shallow_count: usize,
    have_raw: []u8,
    have_count: usize,
    pack_raw: []u8,
    pack_count: usize,
    has_prefix: bool,
    prefix_id: [20]u8,
    prefix_bytes: u64,
    prefix_entries: u64,
};

fn stateEmpty(arena: *arena_mod.Arena) State {
    _ = arena;
    var s: State = undefined;
    s.url = "";
    s.depth = 0;
    s.partial = false;
    s.shallow_raw = g_empty_byte[0..0];
    s.have_raw = g_empty_byte[0..0];
    s.pack_raw = g_empty_byte[0..0];
    s.shallow_count = 0;
    s.have_count = 0;
    s.pack_count = 0;
    s.has_prefix = false;
    var i: usize = 0;
    while (i < 20) : (i += 1) s.prefix_id[i] = 0;
    s.prefix_bytes = 0;
    s.prefix_entries = 0;
    return s;
}


fn parseDecSlice(s: []const u8) u64 {
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c < '0' or c > '9') break;
        v = v * 10 + @intCast(u64, c - '0');
    }
    return v;
}


fn stateInitArrays(arena: *arena_mod.Arena, data_len: usize, s: *State) bool {
    var cap: usize = data_len / 40 + 8;
    if (cap < SHALLOW_MAX) cap = SHALLOW_MAX;
    const a = arena_mod.alloc(arena, cap * 20) catch return false;
    const b = arena_mod.alloc(arena, cap * 20) catch return false;
    const c = arena_mod.alloc(arena, cap * 20) catch return false;
    s.shallow_raw = a[0 .. cap * 20];
    s.have_raw = b[0 .. cap * 20];
    s.pack_raw = c[0 .. cap * 20];
    return true;
}

fn rawHas(raw: []const u8, count: usize, id: [20]u8) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var same = true;
        var k: usize = 0;
        while (k < 20) : (k += 1) {
            if (raw[i * 20 + k] != id[k]) {
                same = false;
                break;
            }
        }
        if (same) return true;
    }
    return false;
}

fn rawAdd(raw: []u8, count: *usize, cap: usize, id: [20]u8) void {
    if (rawHas(raw[0 .. cap * 20], count.*, id)) return;
    if (count.* >= cap) return;
    var k: usize = 0;
    while (k < 20) : (k += 1) raw[count.* * 20 + k] = id[k];
    count.* += 1;
}


fn parseStateLineId(line: []const u8, out: *[20]u8) bool {
    if (line.len < 40) return false;
    return parseId(line[0..40], out);
}

fn stateLoad(arena: *arena_mod.Arena, git_dir: []const u8, s: *State) bool {
    s.* = stateEmpty(arena);
    if (!stateInitArrays(arena, 0, s)) return false;
    const path = joinUrl(arena, git_dir, "/z9git-state") catch return false;
    if (!file_mod.exists(path)) return false;
    const data = file_mod.readAll(arena, path) catch return false;
    if (!stateInitArrays(arena, data.len, s)) return false;

    var pos: usize = 0;
    var saw_header = false;
    while (pos < data.len) {
        var end = pos;
        while (end < data.len and data[end] != '\n') : (end += 1) {}
        var line = data[pos..end];
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        pos = end + 1;
        if (!saw_header) {
            if (eq(line, "z9git-state 1")) saw_header = true;
            continue;
        }
        if (startsWith(line, "url ")) {
            s.url = line[4..];
        } else if (startsWith(line, "depth ")) {
            const v = parseDecSlice(line[6..]);
            if (v <= 4294967295) s.depth = @intCast(u32, v);
        } else if (startsWith(line, "partial ")) {
            s.partial = line.len >= 9 and line[8] == '1';
        } else if (startsWith(line, "shallow ")) {
            var id: [20]u8 = undefined;
            if (parseStateLineId(line[8..], &id)) {
                var cap = s.shallow_raw.len / 20;
                rawAdd(s.shallow_raw, &s.shallow_count, cap, id);
                _ = cap;
            }
        } else if (startsWith(line, "have ")) {
            var id: [20]u8 = undefined;
            if (parseStateLineId(line[5..], &id)) {
                var cap = s.have_raw.len / 20;
                rawAdd(s.have_raw, &s.have_count, cap, id);
                _ = cap;
            }
        } else if (startsWith(line, "pack ")) {
            var id: [20]u8 = undefined;
            if (parseStateLineId(line[5..], &id)) {
                var cap = s.pack_raw.len / 20;
                rawAdd(s.pack_raw, &s.pack_count, cap, id);
                _ = cap;
            }
        } else if (startsWith(line, "prefix ")) {
            var rest = line[7..];
            var id: [20]u8 = undefined;
            if (parseStateLineId(rest, &id)) {
                s.has_prefix = true;
                var k: usize = 0;
                while (k < 20) : (k += 1) s.prefix_id[k] = id[k];
                rest = rest[40..];
                while (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
                var sp = 0;
                while (sp < rest.len and rest[sp] != ' ') : (sp += 1) {}
                s.prefix_bytes = parseDecSlice(rest[0..sp]);
                if (sp < rest.len) {
                    rest = rest[sp + 1..];
                    s.prefix_entries = parseDecSlice(rest);
                }
            }
        }
    }
    return saw_header;
}

fn textAppend(dst: []u8, pos: *usize, src: []const u8) void {
    var i: usize = 0;
    while (i < src.len) : (i += 1) dst[pos.* + i] = src[i];
    pos.* += src.len;
}

fn textAppendId(dst: []u8, pos: *usize, id: [20]u8) void {
    hexId(id, dst[pos.* .. pos.* + 40]);
    pos.* += 40;
}

fn discHead(disc: *const Discovery, head_target: *[]const u8, head_id: *[20]u8, has_head: *bool) void {
    head_target.* = disc.head_target;
    var hk: usize = 0;
    while (hk < 20) : (hk += 1) head_id.*[hk] = disc.head_id[hk];
    has_head.* = disc.has_head;
    if (head_target.*.len != 0 and !has_head.*) {
        var i: usize = 0;
        while (i < disc.refs.len) : (i += 1) {
            if (eq(disc.refs[i].name, head_target.*)) {
                var k: usize = 0;
                while (k < 20) : (k += 1) head_id.*[k] = disc.refs[i].id[k];
                has_head.* = true;
                break;
            }
        }
    }
    if (!has_head.*) {
        var i: usize = 0;
        while (i < disc.refs.len) : (i += 1) {
            if (startsWith(disc.refs[i].name, "refs/heads/")) {
                head_target.* = disc.refs[i].name;
                var k: usize = 0;
                while (k < 20) : (k += 1) head_id.*[k] = disc.refs[i].id[k];
                has_head.* = true;
                break;
            }
        }
    }
}

fn stateSave(arena: *arena_mod.Arena, git_dir: []const u8, s: *const State, disc: *const Discovery) repo.GitError!void {
    var ref_names: usize = 0;
    var ri: usize = 0;
    while (ri < disc.refs.len) : (ri += 1) ref_names += disc.refs[ri].name.len + 56;
    const total = 4096 + s.url.len + ref_names + (s.shallow_count + s.have_count + s.pack_count) * 52;
    const raw = arena_mod.alloc(arena, total) catch return error.OutOfMemory;
    const out = raw[0..total];
    var pos: usize = 0;
    textAppend(out, &pos, "z9git-state 1\n");
    textAppend(out, &pos, "url ");
    textAppend(out, &pos, s.url);
    textAppend(out, &pos, "\n");
    textAppend(out, &pos, "depth ");
    appendDecAt(out, &pos, @intCast(u64, s.depth));
    textAppend(out, &pos, "\n");
    textAppend(out, &pos, if (s.partial) "partial 1\n" else "partial 0\n");
    var i: usize = 0;
    while (i < s.shallow_count) : (i += 1) {
        var id: [20]u8 = undefined;
        var k: usize = 0;
        while (k < 20) : (k += 1) id[k] = s.shallow_raw[i * 20 + k];
        textAppend(out, &pos, "shallow ");
        textAppendId(out, &pos, id);
        textAppend(out, &pos, "\n");
    }
    i = 0;
    while (i < s.have_count) : (i += 1) {
        var id: [20]u8 = undefined;
        var k: usize = 0;
        while (k < 20) : (k += 1) id[k] = s.have_raw[i * 20 + k];
        textAppend(out, &pos, "have ");
        textAppendId(out, &pos, id);
        textAppend(out, &pos, "\n");
    }
    i = 0;
    while (i < s.pack_count) : (i += 1) {
        var id: [20]u8 = undefined;
        var k: usize = 0;
        while (k < 20) : (k += 1) id[k] = s.pack_raw[i * 20 + k];
        textAppend(out, &pos, "pack ");
        textAppendId(out, &pos, id);
        textAppend(out, &pos, "\n");
    }
    if (s.has_prefix) {
        textAppend(out, &pos, "prefix ");
        textAppendId(out, &pos, s.prefix_id);
        textAppend(out, &pos, " ");
        appendDecAt(out, &pos, s.prefix_bytes);
        textAppend(out, &pos, " ");
        appendDecAt(out, &pos, s.prefix_entries);
        textAppend(out, &pos, "\n");
    }
    i = 0;
    while (i < disc.refs.len) : (i += 1) {
        textAppend(out, &pos, "ref ");
        textAppendId(out, &pos, disc.refs[i].id);
        textAppend(out, &pos, " ");
        textAppend(out, &pos, disc.refs[i].name);
        textAppend(out, &pos, "\n");
    }
    var head_target: []const u8 = "";
    var head_id: [20]u8 = undefined;
    var has_head = false;
    discHead(disc, &head_target, &head_id, &has_head);
    if (startsWith(head_target, "refs/")) {
        textAppend(out, &pos, "head ");
        textAppend(out, &pos, head_target);
        textAppend(out, &pos, "\n");
    } else if (has_head) {
        textAppend(out, &pos, "head-id ");
        textAppendId(out, &pos, head_id);
        textAppend(out, &pos, "\n");
    }
    const path = joinUrl(arena, git_dir, "/z9git-state") catch return error.OutOfMemory;
    file_mod.writeAll(path, out[0..pos]) catch return error.Io;
}

fn headerString(head: *http.Response, name: []const u8) []const u8 {
    var i: usize = 0;
    while (i < head.headers.len) : (i += 1) {
        if (headerNameEq(head.headers[i].name, name)) return head.headers[i].value;
    }
    return "";
}

fn resolveLocation(arena: *arena_mod.Arena, base: []const u8, loc: []const u8) ![]u8 {
    if (startsWith(loc, "http://") or startsWith(loc, "https://")) {
        return joinUrl(arena, loc, "") catch return error.OutOfMemory;
    }
    const sep = findFrom(base, "://", 0);
    if (sep >= base.len) return error.Transport;
    var auth_end = sep + 3;
    while (auth_end < base.len and base[auth_end] != '/' and base[auth_end] != '?') : (auth_end += 1) {}
    const origin = base[0..auth_end];
    if (loc.len > 0 and loc[0] == '/') {
        return joinUrl(arena, origin, loc) catch return error.OutOfMemory;
    }
    var cut = base.len;
    while (cut > auth_end and base[cut - 1] != '/') cut -= 1;

    var prefix: []const u8 = base[0..cut];
    if (cut == base.len) {
        prefix = joinUrl(arena, base, "/") catch return error.OutOfMemory;
    }
    return joinUrl(arena, prefix, loc) catch return error.OutOfMemory;
}

fn normalizeUrl(arena: *arena_mod.Arena, url: []const u8) repo.GitError![]const u8 {
    const parts = parseUrl(url) catch return error.Transport;
    var base = parts.base_url;
    const is_code_host = eq(parts.host, "github.com") or eq(parts.host, "gitlab.com");
    if (is_code_host and !endsWith(base, ".git")) {
        return joinUrl(arena, base, ".git") catch return error.OutOfMemory;
    }
    return base;
}

fn httpGetFollow(arena: *arena_mod.Arena, factory: *const TransportFactory, url0: []const u8, out: *http.Response) repo.GitError!void {
    var url = url0;
    var tries: usize = 0;
    while (tries < 6) : (tries += 1) {
        var t = try openTransport(factory, url);
        http.httpGetOver(arena, &t, url, out) catch |e| {
            if (e == error.OutOfMemory) return error.OutOfMemory;
            if (e == error.BadResponse) return error.Protocol;
            if (e == error.BadHeader) return error.Protocol;
            if (e == error.TooLarge) return error.Protocol;
            return error.Transport;
        };
        if (out.status == 301 or out.status == 302 or out.status == 303 or out.status == 307) {
            const loc = headerString(out, "location");
            if (loc.len == 0) return error.Protocol;
            url = resolveLocation(arena, url, loc) catch return error.OutOfMemory;
            continue;
        }
        return;
    }
    return error.Transport;
}

fn installPack(arena: *arena_mod.Arena, dest_git: []const u8, tmp_pack: []const u8, tmp_idx: []const u8, id: [20]u8) repo.GitError!void {
    pack_mod.setTempDir(dest_git);
    pack_mod.idxSynthesize(arena, tmp_pack, tmp_idx) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        if (e == error.WriteFailed) return error.DiskFull;
        if (e == error.OpenFailed) return error.Io;
        if (e == error.ReadFailed) return error.Io;
        return error.ObjectStore;
    };
    var hexbuf: [40]u8 = undefined;
    hexId(id, hexbuf[0..40]);
    const pack_dir = joinUrl(arena, dest_git, "/objects/pack/pack-") catch return error.OutOfMemory;
    const stem = joinUrl(arena, pack_dir, hexbuf[0..40]) catch return error.OutOfMemory;
    const final_pack = joinUrl(arena, stem, ".pack") catch return error.OutOfMemory;
    const final_idx = joinUrl(arena, stem, ".idx") catch return error.OutOfMemory;
    if (file_mod.exists(final_pack)) file_mod.remove(final_pack) catch return error.Io;
    if (file_mod.exists(final_idx)) file_mod.remove(final_idx) catch return error.Io;
    file_mod.rename(tmp_pack, final_pack) catch {
        removeIfExists(final_idx);
        return error.Io;
    };
    file_mod.rename(tmp_idx, final_idx) catch {
        removeIfExists(final_pack);
        removeIfExists(final_idx);
        return error.Io;
    };
}

fn stateAddPack(s: *State, id: [20]u8) void {
    const cap = s.pack_raw.len / 20;
    rawAdd(s.pack_raw, &s.pack_count, cap, id);
}

fn stateAddHave(s: *State, id: [20]u8) void {
    const cap = s.have_raw.len / 20;
    rawAdd(s.have_raw, &s.have_count, cap, id);
}

fn addCompleteHaves(arena: *arena_mod.Arena, dest_git: []const u8, disc: *const Discovery, partial: bool, s: *State) void {
    var i: usize = 0;
    while (i < disc.refs.len) : (i += 1) {
        if (startsWith(disc.refs[i].name, "refs/pull/")) continue;
        if (rawHas(s.have_raw, s.have_count, disc.refs[i].id)) continue;
        const ok = repo.tipClosureComplete(arena, dest_git, disc.refs[i].id, partial) catch false;
        if (ok) stateAddHave(s, disc.refs[i].id);
    }
}



const Attempt = struct {
    complete: bool,
    id: [20]u8,
    pack_bytes: u64,
    shallow_raw: []u8,
    shallow_count: usize,
    status: u16,
    fail_kind: u8,
    transport: bool,
    redirect: []const u8,
};

fn postPack(arena: *arena_mod.Arena, factory: *const TransportFactory, post_url: []const u8, req_body: []const u8, max_down_bps: u32, dest_git: []const u8, tmp_path: []const u8, tmp_idx: []const u8, out: *Attempt) repo.GitError!void {
    out.complete = false;
    out.pack_bytes = 0;
    out.status = 0;
    out.fail_kind = 0;
    out.transport = false;
    out.redirect = "";
    out.shallow_count = 0;
    const empty_shallow = arena_mod.alloc(arena, 0) catch return error.OutOfMemory;
    out.shallow_raw = empty_shallow[0..0];

    var i: usize = 0;
    while (i < 20) : (i += 1) out.id[i] = 0;
    removeIfExists(tmp_path);
    removeIfExists(tmp_idx);
    const pack_file = file_mod.open(arena, tmp_path, file_mod.Mode.Write) catch return error.Io;

    var no_headers: [1]http.Header = undefined;
    var no_body: [1]u8 = undefined;
    var head = http.Response{ .status = 0, .headers = no_headers[0..0], .body = no_body[0..0] };
    var ps: PackSink = undefined;
    ps.file = pack_file;
    ps.hasher = crypto.sha1Init();
    ps.hold_pos = 0;
    ps.hold_len = 0;
    ps.phase = .len;
    ps.len_pos = 0;
    ps.pkt_remain = 0;
    ps.pkt_total = 0;
    ps.pkt_head_len = 0;
    ps.pack_started = false;
    ps.pack_bytes = 0;
    ps.max_down_bps = max_down_bps;
    ps.pace_start = 0;
    ps.fail_kind = 0;
    ps.head = &head;
    ps.dest_git = dest_git;
    ps.preflight_done = false;
    ps.have_cl = 0;
    ps.pack_hdr_len = 0;
    ps.pack_count = 0;
    ps.guard_next = 0;
    ps.shallow_count = 0;
    var sink = http.ResponseSink{
        .state = @ptrCast(*void, &ps),
        .write_fn = packSinkWrite,
    };
    var post_t = openTransport(factory, post_url) catch {
        file_mod.close(&ps.file);
        out.transport = true;
        return;
    };
    http.httpPostStreamOver(arena, &post_t, post_url, req_body, "application/x-git-upload-pack-request", "application/x-git-upload-pack-result", &sink, &head) catch |e| {
        if (e == error.OutOfMemory) {
            file_mod.close(&ps.file);
            return error.OutOfMemory;
        }
        out.fail_kind = ps.fail_kind;
        if (ps.fail_kind == 0) out.transport = true;
    };
    file_mod.close(&ps.file);

    out.status = head.status;
    out.pack_bytes = ps.pack_bytes;
    out.fail_kind = ps.fail_kind;
    const sc = ps.shallow_count;
    const sraw = arena_mod.alloc(arena, if (sc == 0) 0 else sc * 20) catch return error.OutOfMemory;
    i = 0;
    while (i < sc * 20) : (i += 1) sraw[i] = ps.shallow_raw[i];
    out.shallow_raw = sraw[0 .. sc * 20];
    out.shallow_count = sc;

    if (head.status == 301 or head.status == 302 or head.status == 303 or head.status == 307) {
        out.redirect = headerString(&head, "location");
        return;
    }
    if (head.status != 200) return;
    if (!ps.pack_started or ps.hold_len != 20) return;

    var digest: [20]u8 = undefined;
    crypto.sha1Final(&ps.hasher, &digest);
    var trailer: [20]u8 = undefined;
    trailerOrder(&ps, &trailer);
    if (!idEql(digest, trailer)) return;
    out.complete = true;
    i = 0;
    while (i < 20) : (i += 1) out.id[i] = trailer[i];
}

fn tryPrefix(arena: *arena_mod.Arena, dest_git: []const u8, tmp_path: []const u8, s: *State) bool {
    const tmp_pack = joinUrl(arena, dest_git, "/objects/pack/tmp_prefix.pack") catch return false;
    const tmp_idx = joinUrl(arena, dest_git, "/objects/pack/tmp_prefix.idx") catch return false;
    removeIfExists(tmp_pack);
    removeIfExists(tmp_idx);
    pack_mod.setTempDir(dest_git);
    var info: pack_mod.PrefixInfo = undefined;
    pack_mod.prefixFinalize(arena, tmp_path, tmp_pack, tmp_idx, &info) catch {

        removeIfExists(tmp_pack);
        removeIfExists(tmp_idx);
        removeIfExists(tmp_path);
        return false;
    };

    installPack(arena, dest_git, tmp_pack, tmp_idx, info.id) catch {
        removeIfExists(tmp_pack);
        removeIfExists(tmp_idx);
        removeIfExists(tmp_path);
        return false;
    };
    removeIfExists(tmp_pack);
    removeIfExists(tmp_idx);
    removeIfExists(tmp_path);
    stateAddPack(s, info.id);
    s.has_prefix = true;
    var pk: usize = 0;
    while (pk < 20) : (pk += 1) s.prefix_id[pk] = info.id[pk];

    s.prefix_bytes = info.body_bytes;
    s.prefix_entries = info.entries;
    return true;
}

const WantOpts = struct {
    post_url: []const u8,
    dest_git: []const u8,
    max_down_bps: u32,
    depth: u32,
    deepen_relative: bool,
    partial: bool,
    shallow_raw: []const u8,
    shallow_count: usize,
};

const DownloadResult = struct {
    shallow_raw: []u8,
    shallow_count: usize,
};

fn downloadWanted(arena: *arena_mod.Arena, factory: *const TransportFactory, disc: *const Discovery, opts: *WantOpts, s: *State) repo.GitError!DownloadResult {
    var want_raw: []u8 = undefined;
    var want_count: usize = 0;
    try collectWanted(arena, disc.refs, &want_raw, &want_count);
    const tmp_path = joinUrl(arena, opts.dest_git, "/objects/pack/tmp_http_pack.pack") catch return error.OutOfMemory;
    const tmp_idx = joinUrl(arena, opts.dest_git, "/objects/pack/tmp_http_pack.idx") catch return error.OutOfMemory;
    var attempts: usize = 0;
    while (attempts < MAX_ATTEMPTS) : (attempts += 1) {
        const req = try buildRequestEx(arena, want_raw, want_count, s.have_raw, s.have_count, opts.depth, opts.deepen_relative, opts.shallow_raw, opts.shallow_count, opts.partial);
        var at: Attempt = undefined;
        try postPack(arena, factory, opts.post_url, req, opts.max_down_bps, opts.dest_git, tmp_path, tmp_idx, &at);


        if (at.redirect.len != 0) {
            opts.post_url = resolveLocation(arena, opts.post_url, at.redirect) catch return error.OutOfMemory;
            removeIfExists(tmp_path);
            removeIfExists(tmp_idx);
            continue;
        }
        if (at.complete) {
            try installPack(arena, opts.dest_git, tmp_path, tmp_idx, at.id);
            stateAddPack(s, at.id);

            s.shallow_raw = at.shallow_raw;
            s.shallow_count = at.shallow_count;
            s.depth = opts.depth;
            try stateSave(arena, opts.dest_git, s, disc);
            var r: DownloadResult = undefined;
            r.shallow_raw = at.shallow_raw;
            r.shallow_count = at.shallow_count;
            return r;
        }
        if (at.status != 0 and at.status != 200 and at.pack_bytes <= 12) {
            removeIfExists(tmp_path);
            removeIfExists(tmp_idx);
            if (at.status >= 400) return error.Transport;
            return error.Protocol;
        }
        const pref_ok = tryPrefix(arena, opts.dest_git, tmp_path, s);

        if (pref_ok) {
            s.shallow_raw = at.shallow_raw;
            s.shallow_count = at.shallow_count;

            s.depth = opts.depth;
            addCompleteHaves(arena, opts.dest_git, disc, opts.partial, s);
            try stateSave(arena, opts.dest_git, s, disc);
            continue;
        }
        removeIfExists(tmp_path);
        removeIfExists(tmp_idx);
        if (at.fail_kind == KIND_DISK_FULL) return error.DiskFull;
        if (at.fail_kind == KIND_IO) return error.Io;
        if (at.fail_kind == KIND_PROTOCOL) return error.Protocol;
        return error.Transport;
    }
    removeIfExists(tmp_path);
    removeIfExists(tmp_idx);
    return error.Transport;
}

fn downloadBlobIds(arena: *arena_mod.Arena, factory: *const TransportFactory, post_url0: []const u8, dest_git: []const u8, max_down_bps: u32, want_raw: []const u8, want_count: usize) repo.GitError!void {
    const tmp_path = joinUrl(arena, dest_git, "/objects/pack/tmp_http_blob.pack") catch return error.OutOfMemory;
    const tmp_idx = joinUrl(arena, dest_git, "/objects/pack/tmp_http_blob.idx") catch return error.OutOfMemory;
    var post_url = post_url0;
    var attempts: usize = 0;
    while (attempts < MAX_ATTEMPTS) : (attempts += 1) {
        const req = try buildRequestEx(arena, want_raw, want_count, want_raw, 0, 0, false, want_raw, 0, false);
        var at: Attempt = undefined;
        try postPack(arena, factory, post_url, req, max_down_bps, dest_git, tmp_path, tmp_idx, &at);
        if (at.redirect.len != 0) {
            post_url = resolveLocation(arena, post_url, at.redirect) catch return error.OutOfMemory;
            removeIfExists(tmp_path);
            removeIfExists(tmp_idx);
            continue;
        }
        if (at.complete) {
            try installPack(arena, dest_git, tmp_path, tmp_idx, at.id);
            return;
        }
        removeIfExists(tmp_path);
        removeIfExists(tmp_idx);
        if (at.status != 0 and at.status != 200) return error.Transport;
        if (at.fail_kind == KIND_DISK_FULL) return error.DiskFull;
        if (at.fail_kind == KIND_IO) return error.Io;
        if (at.fail_kind == KIND_PROTOCOL) return error.Protocol;
    }
    return error.Transport;
}

fn worktreeOf(git_dir: []const u8) []const u8 {
    if (endsWith(git_dir, "/.git")) return git_dir[0 .. git_dir.len - 5];
    if (eq(git_dir, ".git")) return ".";
    return git_dir;
}

pub fn httpCloneOverOpts(arena: *arena_mod.Arena, url: []const u8, dest_dir: []const u8, max_down_bps: u32, depth0: u32, partial0: bool, factory: *const TransportFactory) repo.GitError!void {
    const norm = try normalizeUrl(arena, url);
    const parts = parseUrl(norm) catch return error.Transport;
    const info_url = joinUrl(arena, norm, "/info/refs?service=git-upload-pack") catch return error.OutOfMemory;
    var post_url: []const u8 = joinUrl(arena, norm, "/git-upload-pack") catch return error.OutOfMemory;

    _ = parts;

    var info_resp: http.Response = undefined;
    try httpGetFollow(arena, factory, info_url, &info_resp);
    if (info_resp.status != 200) return error.Transport;
    const disc = try parseDiscovery(arena, info_resp.body);

    const dest_git = try repo.prepareCloneDirs(arena, dest_dir);
    var st: State = undefined;
    const had_state = stateLoad(arena, dest_git, &st);
    _ = had_state;
    var depth = depth0;


    var partial = partial0;
    if (depth == 0 and st.depth > 0) depth = st.depth;
    if (st.partial) partial = true;
    st.url = norm;

    var opts = WantOpts{
        .post_url = post_url,
        .dest_git = dest_git,
        .max_down_bps = max_down_bps,
        .depth = depth,
        .deepen_relative = false,
        .partial = partial,
        .shallow_raw = st.shallow_raw,
        .shallow_count = st.shallow_count,
    };
    const res = try downloadWanted(arena, factory, &disc, &opts, &st);
    post_url = opts.post_url;
    st.url = norm;
    st.depth = depth;
    st.partial = partial;
    st.shallow_raw = res.shallow_raw;
    st.shallow_count = res.shallow_count;
    try repo.writeShallow(arena, dest_git, st.shallow_raw, st.shallow_count);

    var head_target: []const u8 = "";
    var head_id: [20]u8 = undefined;
    var has_head = false;
    discHead(&disc, &head_target, &head_id, &has_head);
    if (!has_head) return error.Protocol;

    const entries_raw = arena_mod.alloc(arena, disc.refs.len * @sizeOf(repo.RefEntry)) catch return error.OutOfMemory;
    const entries = @ptrCast([*]repo.RefEntry, entries_raw)[0..disc.refs.len];
    var i: usize = 0;
    while (i < disc.refs.len) : (i += 1) {
        entries[i].name = disc.refs[i].name;
        var k: usize = 0;
        while (k < 20) : (k += 1) entries[i].id[k] = disc.refs[i].id[k];
    }
    try repo.installRefs(arena, dest_dir, entries, head_target, head_id, has_head);
    try stateSave(arena, dest_git, &st, &disc);

    if (partial) {
        var blob_raw: []u8 = undefined;
        var blob_count: usize = 0;
        try repo.missingBlobsForRef(arena, dest_git, "", &blob_raw, &blob_count);
        if (blob_count > 0) {
            try downloadBlobIds(arena, factory, post_url, dest_git, max_down_bps, blob_raw, blob_count);
            try stateSave(arena, dest_git, &st, &disc);
        }
    }
    try repo.checkoutHead(arena, dest_dir);
}

pub fn httpFetch(arena: *arena_mod.Arena, git_dir: []const u8, deepen: u32, max_down_bps: u32) repo.GitError!void {
    var st: State = undefined;
    if (!stateLoad(arena, git_dir, &st)) return error.Usage;
    if (st.url.len == 0 or st.depth == 0) return error.Usage;
    const norm = try normalizeUrl(arena, st.url);
    const info_url = joinUrl(arena, norm, "/info/refs?service=git-upload-pack") catch return error.OutOfMemory;
    var rf: RealFactory = undefined;
    const parts0 = parseUrl(norm) catch return error.Transport;
    rf.scheme = parts0.scheme;
    rf.arena = arena;
    rf.store_loaded = false;
    var factory = TransportFactory{ .state = @ptrCast(*void, &rf), .open_fn = openReal };
    var info_resp: http.Response = undefined;
    try httpGetFollow(arena, &factory, info_url, &info_resp);
    if (info_resp.status != 200) return error.Transport;
    const disc = try parseDiscovery(arena, info_resp.body);
    var hi: usize = 0;
    while (hi < disc.refs.len) : (hi += 1) {
        if (!startsWith(disc.refs[hi].name, "refs/pull/")) stateAddHave(&st, disc.refs[hi].id);
    }
    var new_depth: u64 = @intCast(u64, st.depth) + @intCast(u64, deepen);

    if (new_depth > 4294967295) return error.Usage;
    var opts = WantOpts{
        .post_url = joinUrl(arena, norm, "/git-upload-pack") catch return error.OutOfMemory,
        .dest_git = git_dir,
        .max_down_bps = max_down_bps,
        .depth = @intCast(u32, new_depth),
        .deepen_relative = true,
        .partial = st.partial,
        .shallow_raw = st.shallow_raw,
        .shallow_count = st.shallow_count,
    };
    const res = try downloadWanted(arena, &factory, &disc, &opts, &st);
    st.url = norm;
    st.depth = @intCast(u32, new_depth);
    st.shallow_raw = res.shallow_raw;
    st.shallow_count = res.shallow_count;
    try repo.writeShallow(arena, git_dir, st.shallow_raw, st.shallow_count);

    var head_target: []const u8 = "";
    var head_id: [20]u8 = undefined;
    var has_head = false;
    discHead(&disc, &head_target, &head_id, &has_head);
    if (!has_head) return error.Protocol;
    const wt = worktreeOf(git_dir);
    const entries_raw = arena_mod.alloc(arena, disc.refs.len * @sizeOf(repo.RefEntry)) catch return error.OutOfMemory;
    const entries = @ptrCast([*]repo.RefEntry, entries_raw)[0..disc.refs.len];
    var i: usize = 0;
    while (i < disc.refs.len) : (i += 1) {
        entries[i].name = disc.refs[i].name;
        var k: usize = 0;
        while (k < 20) : (k += 1) entries[i].id[k] = disc.refs[i].id[k];
    }
    try repo.installRefs(arena, wt, entries, head_target, head_id, has_head);
    try stateSave(arena, git_dir, &st, &disc);
}

pub fn httpFetchBlobsForRef(arena: *arena_mod.Arena, git_dir: []const u8, ref_name: []const u8, max_down_bps: u32) repo.GitError!void {
    var st: State = undefined;
    if (!stateLoad(arena, git_dir, &st)) return;
    if (!st.partial or st.url.len == 0) return;
    var want_raw: []u8 = undefined;
    var want_count: usize = 0;
    try repo.missingBlobsForRef(arena, git_dir, ref_name, &want_raw, &want_count);
    if (want_count == 0) return;
    const norm = try normalizeUrl(arena, st.url);
    const parts = parseUrl(norm) catch return error.Transport;
    var rf: RealFactory = undefined;
    rf.scheme = parts.scheme;
    rf.arena = arena;
    rf.store_loaded = false;
    var factory = TransportFactory{ .state = @ptrCast(*void, &rf), .open_fn = openReal };
    const post_url = joinUrl(arena, norm, "/git-upload-pack") catch return error.OutOfMemory;
    try downloadBlobIds(arena, &factory, post_url, git_dir, max_down_bps, want_raw, want_count);
}

pub fn httpCloneWithOpts(arena: *arena_mod.Arena, url: []const u8, dest_dir: []const u8, max_down_bps: u32, depth: u32, partial: bool) repo.GitError!void {
    const norm = try normalizeUrl(arena, url);
    const parts = parseUrl(norm) catch return error.Transport;
    var rf: RealFactory = undefined;
    rf.scheme = parts.scheme;
    rf.arena = arena;
    rf.store_loaded = false;
    var factory = TransportFactory{
        .state = @ptrCast(*void, &rf),
        .open_fn = openReal,
    };
    try httpCloneOverOpts(arena, url, dest_dir, max_down_bps, depth, partial, &factory);
}

pub fn httpCloneOver(arena: *arena_mod.Arena, url: []const u8, dest_dir: []const u8, max_down_bps: u32, factory: *const TransportFactory) repo.GitError!void {
    try httpCloneOverOpts(arena, url, dest_dir, max_down_bps, 0, false, factory);
}


pub fn httpClone(arena: *arena_mod.Arena, url: []const u8, dest_dir: []const u8, max_down_bps: u32) repo.GitError!void {
    const parts = parseUrl(url) catch return error.Transport;
    var rf: RealFactory = undefined;
    rf.scheme = parts.scheme;
    rf.arena = arena;
    rf.store_loaded = false;
    var factory = TransportFactory{
        .state = @ptrCast(*void, &rf),
        .open_fn = openReal,
    };
    try httpCloneOver(arena, url, dest_dir, max_down_bps, &factory);
}
