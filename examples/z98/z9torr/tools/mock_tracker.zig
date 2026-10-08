// mock_tracker.zig — z9torr M2 test double: a fixed HTTP tracker.
//
// Separate Z98 binary (not linked into the client). Listens on a fixed port
// (default 6969), reads one HTTP request until "\r\n\r\n", and replies with
//
//   HTTP/1.1 200 OK\r\nContent-Length: <n>\r\nConnection: close\r\n\r\n<body>
//
// where <body> is a fixed compact bencoded announce response pointing at the
// mock peer:
//
//   d8:intervali1800e5:peers<6*N>:<N * (4-byte IP + 2-byte BE port)>e
//
// or the raw bytes of a --response <file> when given.
//
// Flags: --port <n>  --peer <ip:port> (repeatable)  --peers a,b,c  --response <file>
//
// Build (binding recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o out tools/mock_tracker.zig
//   sh out/build_target.sh linux out/prog
//
// Z98 rules apply: free functions only, no generics, strict @intCast,
// switch needs else, string literals via `var s: []const u8 = "...";`.

const std = @import("std");
const std_net = @import("std_net");
const std_file = @import("std_file");

const DEFAULT_PORT: u32 = 6969;
const REQ_BUF: usize = 8192;
const RESP_MAX: usize = 65536;
const MAX_PEERS: usize = 64;

// Fixed work buffers (no per-connection allocation).
var g_body: [RESP_MAX]u8 = undefined;
var g_arena_buf: [65536]u8 = undefined;

// Accumulated compact peers (D2: fixed arrays, never a slice of a synthetic).
var g_ips: [MAX_PEERS][4]u8 = undefined;
var g_ports: [MAX_PEERS]u16 = undefined;
var g_npeers: usize = 0;

fn out(s: []const u8) void {
    std.io.write(s);
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn parseU32(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > @intCast(u64, 4294967295)) return null;
    }
    return @intCast(u32, v);
}

// Parse "a.b.c.d:port" into the 4 address bytes and host-order port.
fn parsePeer(s: []const u8, ip: *[4]u8, port: *u16) bool {
    var colon: usize = s.len;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == ':') { colon = i; break; }
    }
    if (colon == s.len) return false;

    var val: u32 = 0;
    var oct: usize = 0;
    var seen: bool = false;
    i = 0;
    while (i < colon) : (i += 1) {
        const c: u8 = s[i];
        if (c >= '0' and c <= '9') {
            val = val * 10 + @intCast(u32, c - '0');
            seen = true;
            if (val > 255) return false;
        } else if (c == '.') {
            if (!seen or oct >= 4) return false;
            ip[oct] = @intCast(u8, val);
            oct += 1;
            val = 0;
            seen = false;
        } else {
            return false;
        }
    }
    if (!seen or oct != 3) return false;
    ip[3] = @intCast(u8, val);

    if (colon + 1 >= s.len) return false;
    var ps: []const u8 = s[colon + 1 ..];
    if (parseU32(ps)) |pv| {
        if (pv > 65535) return false;
        port.* = @intCast(u16, pv);
        return true;
    }
    return false;
}

fn addPeerStr(s: []const u8) bool {
    if (g_npeers >= MAX_PEERS) return false;
    var ip: [4]u8 = undefined;
    var port: u16 = 0;
    if (!parsePeer(s, &ip, &port)) return false;
    g_ips[g_npeers] = ip;
    g_ports[g_npeers] = port;
    g_npeers += 1;
    return true;
}

// Split a comma-separated list and append each "ip:port".
fn addPeerList(list: []const u8) bool {
    var start: usize = 0;
    var i: usize = 0;
    while (i <= list.len) : (i += 1) {
        if (i == list.len or list[i] == ',') {
            var tok: []const u8 = list[start..i];
            if (tok.len == 0) return false;
            if (!addPeerStr(tok)) return false;
            start = i + 1;
        }
    }
    return true;
}

fn sendAll(fd: i32, data: []const u8) bool {
    var off: usize = 0;
    while (off < data.len) {
        var chunk: []const u8 = data[off..];
        const n = std_net.send(fd, chunk.ptr, @intCast(i32, chunk.len));
        if (n <= 0) return false;
        off += @intCast(usize, n);
    }
    return true;
}

fn hasHeaderEnd(b: []const u8) bool {
    if (b.len < 4) return false;
    var i: usize = 0;
    while (i + 3 < b.len) : (i += 1) {
        if (b[i] == '\r' and b[i + 1] == '\n' and b[i + 2] == '\r' and b[i + 3] == '\n') {
            return true;
        }
    }
    return false;
}

fn copyInto(dst: []u8, off_in: usize, src: []const u8) usize {
    var off: usize = off_in;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[off] = src[i];
        off += 1;
    }
    return off;
}

fn writeU64(dst: []u8, v_in: u64) usize {
    var v: u64 = v_in;
    if (v == 0) {
        dst[0] = '0';
        return 1;
    }
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dst[i] = tmp[n - 1 - i];
    }
    return n;
}

// Build the compact announce body for every accumulated peer into g_body and
// return its length. `peers` is a byte string of exactly 6*N bytes.
fn buildBody() usize {
    var prefix: []const u8 = "d8:intervali1800e5:peers";
    var len: usize = 0;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        g_body[len] = prefix[i];
        len += 1;
    }
    len += writeU64(g_body[len..], @intCast(u64, g_npeers * 6));
    g_body[len] = ':';
    len += 1;
    var k: usize = 0;
    while (k < g_npeers) : (k += 1) {
        i = 0;
        while (i < 4) : (i += 1) {
            g_body[len] = g_ips[k][i];
            len += 1;
        }
        g_body[len] = @intCast(u8, (g_ports[k] >> 8) & @intCast(u16, 0xFF));
        len += 1;
        g_body[len] = @intCast(u8, g_ports[k] & @intCast(u16, 0xFF));
        len += 1;
    }
    g_body[len] = 'e';
    len += 1;
    return len;
}

fn handle(fd: i32, body: []const u8) void {
    var req: [REQ_BUF]u8 = undefined;
    var len: usize = 0;
    while (len < REQ_BUF) {
        const n = std_net.recv(fd, @ptrCast([*]u8, &req[len]), @intCast(i32, REQ_BUF - len));
        if (n <= 0) return;
        len += @intCast(usize, n);
        if (hasHeaderEnd(req[0..len])) break;
    }

    var hdr: [160]u8 = undefined;
    var hl: usize = 0;
    var p1: []const u8 = "HTTP/1.1 200 OK\r\nContent-Length: ";
    hl = copyInto(hdr[0..], hl, p1);
    hl += writeU64(hdr[hl..], @intCast(u64, body.len));
    var p2: []const u8 = "\r\nConnection: close\r\n\r\n";
    hl = copyInto(hdr[0..], hl, p2);

    _ = sendAll(fd, hdr[0..hl]);
    _ = sendAll(fd, body);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var port: u32 = DEFAULT_PORT;
    var response_path: []const u8 = "";
    var have_response: bool = false;

    const n: usize = @intCast(usize, argc);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--port")) {
            i += 1;
            if (i >= n) { out("mock_tracker: --port needs a value\n"); std.os.exit(1); return; }
            if (parseU32(argAt(argv, i))) |pv| {
                port = pv;
            } else {
                out("mock_tracker: bad --port\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--peer")) {
            i += 1;
            if (i >= n) { out("mock_tracker: --peer needs a value\n"); std.os.exit(1); return; }
            if (!addPeerStr(argAt(argv, i))) {
                out("mock_tracker: bad --peer (want ip:port)\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--peers")) {
            i += 1;
            if (i >= n) { out("mock_tracker: --peers needs a value\n"); std.os.exit(1); return; }
            if (!addPeerList(argAt(argv, i))) {
                out("mock_tracker: bad --peers (want ip:port,ip:port,...)\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--response")) {
            i += 1;
            if (i >= n) { out("mock_tracker: --response needs a value\n"); std.os.exit(1); return; }
            response_path = argAt(argv, i);
            have_response = true;
        } else if (eq(tok, "--help") or eq(tok, "-h")) {
            var u: []const u8 = "usage: mock_tracker [--port N] [--peer IP:PORT]... [--peers a,b,c] [--response FILE]\n";
            out(u);
            std.os.exit(0);
            return;
        } else {
            // Ignore unknown tokens (the tier scripts only pass known flags).
        }
    }

    if (port > 65535) {
        out("mock_tracker: port out of range\n");
        std.os.exit(1);
        return;
    }

    if (g_npeers == 0) {
        if (!addPeerStr("127.0.0.1:6970")) {
            out("mock_tracker: default peer setup failed\n");
            std.os.exit(1);
            return;
        }
    }

    var arena = std.arena.init(g_arena_buf[0..]);
    var body: []const u8 = undefined;
    if (have_response) {
        var data: []u8 = std_file.readAll(&arena, response_path) catch {
            out("mock_tracker: cannot read --response file\n");
            std.os.exit(1);
            return;
        };
        body = data;
    } else {
        const blen = buildBody();
        body = g_body[0..blen];
    }

    if (std_net.init() != 0) {
        out("mock_tracker: socket init failed\n");
        return;
    }
    const srv = std_net.createTcpServer(@intCast(u16, port));
    if (srv < 0) {
        out("mock_tracker: createTcpServer failed\n");
        return;
    }
    if (std_net.bindListen(srv, 8) < 0) {
        out("mock_tracker: listen failed\n");
        std_net.close(srv);
        return;
    }

    var l1: []const u8 = "mock_tracker listening\n";
    out(l1);

    while (true) {
        const c = std_net.accept(srv);
        if (c < 0) continue;
        handle(c, body);
        std_net.close(c);
    }
}
