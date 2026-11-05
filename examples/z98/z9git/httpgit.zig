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

fn buildRequest(arena: *arena_mod.Arena, refs: []const Ref) repo.GitError![]u8 {
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

    const total = count * 50 + 13;
    const raw = arena_mod.alloc(arena, total) catch return error.OutOfMemory;
    const body = raw[0..total];
    var pos: usize = 0;
    i = 0;
    while (i < count) : (i += 1) {
        var payload: [46]u8 = undefined;
        payload[0] = 'w';
        payload[1] = 'a';
        payload[2] = 'n';
        payload[3] = 't';
        payload[4] = ' ';
        var id: [20]u8 = undefined;
        var k: usize = 0;
        while (k < 20) : (k += 1) id[k] = ids_raw[i * 20 + k];
        hexId(id, payload[5..45]);
        payload[45] = '\n';
        pos += pkt.encode(body[pos..], payload[0..46]) catch return error.Protocol;
    }
    pos += pkt.encodeFlush(body[pos..]) catch return error.Protocol;
    pos += pkt.encode(body[pos..], "done\n") catch return error.Protocol;
    return body[0..pos];
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
    pkt_head: [16]u8,
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
    pack_hdr: [12]u8,
    pack_hdr_len: usize,
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
        s.preflight_done = true;
        try packWriteBytes(s, s.pack_hdr[0..12]);
        if (take < data.len) try packWriteBytes(s, data[take..]);
        return;
    }
    try packWriteBytes(s, data);
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
    if (is_nak or is_ack) {
        s.phase = .pack;
        return;
    }
    return sinkFail(s, KIND_PROTOCOL);
}

fn packSinkWrite(state: *void, data: []const u8) http.HttpError!void {
    var s: *PackSink = @ptrCast(*PackSink, state);
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

// --- clone entry points -----------------------------------------------------

pub fn httpCloneOver(arena: *arena_mod.Arena, url: []const u8, dest_dir: []const u8, max_down_bps: u32, factory: *const TransportFactory) repo.GitError!void {
    const parts = parseUrl(url) catch return error.Transport;
    const info_url = joinUrl(arena, parts.base_url, "/info/refs?service=git-upload-pack") catch return error.OutOfMemory;
    const post_url = joinUrl(arena, parts.base_url, "/git-upload-pack") catch return error.OutOfMemory;

    var get_t = try openTransport(factory, info_url);
    var info_resp: http.Response = undefined;
    http.httpGetOver(arena, &get_t, info_url, &info_resp) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        if (e == error.BadResponse) return error.Protocol;
        if (e == error.BadHeader) return error.Protocol;
        if (e == error.TooLarge) return error.Protocol;
        return error.Transport;
    };
    if (info_resp.status != 200) return error.Transport;

    const disc = try parseDiscovery(arena, info_resp.body);
    const req_body = try buildRequest(arena, disc.refs);

    const dest_git = try repo.prepareCloneDirs(arena, dest_dir);
    const tmp_path = joinUrl(arena, dest_git, "/objects/pack/tmp_http_pack.pack") catch return error.OutOfMemory;
    const tmp_idx = joinUrl(arena, dest_git, "/objects/pack/tmp_http_pack.idx") catch return error.OutOfMemory;
    if (file_mod.exists(tmp_path)) file_mod.remove(tmp_path) catch return error.Io;
    if (file_mod.exists(tmp_idx)) file_mod.remove(tmp_idx) catch return error.Io;
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
    var tmp_live = true;
    var pack_open = true;
    defer {
        if (pack_open) file_mod.close(&ps.file);
        if (tmp_live) removeIfExists(tmp_path);
        removeIfExists(tmp_idx);
    }
    var sink = http.ResponseSink{
        .state = @ptrCast(*void, &ps),
        .write_fn = packSinkWrite,
    };
    var post_t = try openTransport(factory, post_url);

    http.httpPostStreamOver(arena, &post_t, post_url, req_body, "application/x-git-upload-pack-request", "application/x-git-upload-pack-result", &sink, &head) catch |e| {
        if (head.status != 0 and head.status != 200) return error.Transport;
        if (ps.fail_kind == KIND_DISK_FULL) return error.DiskFull;
        if (ps.fail_kind == KIND_IO) return error.Io;
        if (ps.fail_kind == KIND_PROTOCOL) return error.Protocol;
        if (e == error.OutOfMemory) return error.OutOfMemory;
        if (e == error.BadResponse) return error.Protocol;
        if (e == error.BadHeader) return error.Protocol;
        if (e == error.TooLarge) return error.Protocol;
        return error.Transport;
    };
    file_mod.close(&ps.file);
    pack_open = false;
    if (head.status != 200) return error.Transport;
    if (ps.fail_kind == KIND_DISK_FULL) return error.DiskFull;
    if (ps.fail_kind == KIND_IO) return error.Io;
    if (ps.fail_kind == KIND_PROTOCOL) return error.Protocol;
    if (!ps.pack_started or ps.hold_len != 20) return error.Protocol;

    var digest: [20]u8 = undefined;
    crypto.sha1Final(&ps.hasher, &digest);
    var trailer: [20]u8 = undefined;
    trailerOrder(&ps, &trailer);
    if (!idEql(digest, trailer)) return error.Protocol;

    var hexbuf: [40]u8 = undefined;
    hexId(trailer, hexbuf[0..40]);
    const pack_path = joinUrl(arena, dest_git, "/objects/pack/pack-") catch return error.OutOfMemory;
    const pack_name = joinUrl(arena, pack_path, hexbuf[0..40]) catch return error.OutOfMemory;
    const final_pack = joinUrl(arena, pack_name, ".pack") catch return error.OutOfMemory;
    const final_idx = joinUrl(arena, pack_name, ".idx") catch return error.OutOfMemory;
    // Synthesize the idx beside the temp pack and only rename both into place
    // after success, so a write failure cannot leave a final pack without idx.
    pack_mod.setTempDir(dest_git);
    pack_mod.idxSynthesize(arena, tmp_path, tmp_idx) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        if (e == error.WriteFailed) return error.DiskFull;
        if (e == error.OpenFailed) return error.Io;
        if (e == error.ReadFailed) return error.Io;
        return error.ObjectStore;
    };
    if (file_mod.exists(final_pack)) file_mod.remove(final_pack) catch return error.Io;
    if (file_mod.exists(final_idx)) file_mod.remove(final_idx) catch return error.Io;
    file_mod.rename(tmp_path, final_pack) catch {
        removeIfExists(final_idx);
        return error.Io;
    };
    file_mod.rename(tmp_idx, final_idx) catch {
        removeIfExists(final_pack);
        removeIfExists(final_idx);
        return error.Io;
    };
    tmp_live = false;

    var head_target = disc.head_target;
    var head_id: [20]u8 = undefined;
    var hk: usize = 0;
    while (hk < 20) : (hk += 1) head_id[hk] = disc.head_id[hk];
    var has_head = disc.has_head;
    if (head_target.len != 0 and !has_head) {
        var i: usize = 0;
        while (i < disc.refs.len) : (i += 1) {
            if (eq(disc.refs[i].name, head_target)) {
                var k: usize = 0;
                while (k < 20) : (k += 1) head_id[k] = disc.refs[i].id[k];
                has_head = true;
                break;
            }
        }
    }
    if (!has_head) {
        var i: usize = 0;
        while (i < disc.refs.len) : (i += 1) {
            if (startsWith(disc.refs[i].name, "refs/heads/")) {
                head_target = disc.refs[i].name;
                var k: usize = 0;
                while (k < 20) : (k += 1) head_id[k] = disc.refs[i].id[k];
                has_head = true;
                break;
            }
        }
    }
    if (!has_head) return error.Protocol;

    var entries_raw = arena_mod.alloc(arena, disc.refs.len * @sizeOf(repo.RefEntry)) catch return error.OutOfMemory;
    const entries = @ptrCast([*]repo.RefEntry, entries_raw)[0..disc.refs.len];
    var i: usize = 0;
    while (i < disc.refs.len) : (i += 1) {
        entries[i].name = disc.refs[i].name;
        var k: usize = 0;
        while (k < 20) : (k += 1) entries[i].id[k] = disc.refs[i].id[k];
    }
    try repo.installRefs(arena, dest_dir, entries, head_target, head_id, has_head);
    try repo.checkoutHead(arena, dest_dir);
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
