// mock_udp_tracker.zig — z9torr M4 test double: a fixed BEP 15 UDP tracker.
//
// Separate Z98 binary (not linked into the client). Binds a UDP port (default
// 6969) and answers any datagram whose action field says connect (0) or
// announce (1):
//   connect  -> u32 action=0, u32 txn, u64 connection_id=0x0123456789ABCDEF
//   announce -> u32 action=1, u32 txn, u32 interval, u32 leechers, u32 seeders,
//               then 6*N compact peer bytes (4B net IPv4 + 2B BE port)
// Every other action is ignored. The `connection_id` is not validated (the mock
// is a stateless responder); replies go to the datagram source address.
//
// Flags: --port <n>  --peer <ip:port> (repeatable)  --peers a,b,c
//
// Build (binding recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o out tools/mock_udp_tracker.zig
//   sh out/build_target.sh linux out/prog
//
// Z98 rules apply: free functions only, no generics, strict @intCast, switch
// needs else, string literals via `var s: []const u8 = "...";`.

const std = @import("std");
const std_net = @import("std_net");

const DEFAULT_PORT: u32 = 6969;
const RECV_MAX: usize = 4096;
const RESP_MAX: usize = 4096;
const MAX_PEERS: usize = 64;
const CONNECTION_ID: u64 = 0x0123456789ABCDEF;
const INTERVAL: u32 = 1800;
const SEEDERS: u32 = 1;
const LEECHERS: u32 = 0;

var g_ips: [MAX_PEERS][4]u8 = undefined;
var g_ports: [MAX_PEERS]u16 = undefined;
var g_npeers: usize = 0;
var g_resp: [RESP_MAX]u8 = undefined;
var g_event_fd: usize = 0;
var g_has_event_log: bool = false;

fn out(s: []const u8) void {
    std.io.write(s);
}

// Append one `event=<code>` line to the --event-log file (diagnostic: lets the
// tier gate assert the BEP 15 event code the client actually transmitted).
fn logEvent(code: u32) void {
    if (!g_has_event_log) return;
    var b: [24]u8 = undefined;
    var n: usize = 0;
    var pre: []const u8 = "event=";
    var i: usize = 0;
    while (i < pre.len) : (i += 1) {
        b[n] = pre[i];
        n += 1;
    }
    var tmp: [12]u8 = undefined;
    var m: usize = 0;
    var v: u32 = code;
    if (v == 0) {
        tmp[0] = '0';
        m = 1;
    } else {
        while (v > 0) : (v = v / 10) {
            tmp[m] = '0' + @intCast(u8, v % 10);
            m += 1;
        }
    }
    var k: usize = 0;
    while (k < m) : (k += 1) {
        b[n] = tmp[m - 1 - k];
        n += 1;
    }
    b[n] = '\n';
    n += 1;
    std.io.fileWrite(g_event_fd, b[0..n]);
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

fn rdU32(b: []const u8, off: usize) u32 {
    return (@intCast(u32, b[off]) << 24) | (@intCast(u32, b[off + 1]) << 16) |
        (@intCast(u32, b[off + 2]) << 8) | @intCast(u32, b[off + 3]);
}

fn wrU32(b: []u8, off: usize, v: u32) void {
    b[off] = @intCast(u8, (v >> 24) & @intCast(u32, 0xFF));
    b[off + 1] = @intCast(u8, (v >> 16) & @intCast(u32, 0xFF));
    b[off + 2] = @intCast(u8, (v >> 8) & @intCast(u32, 0xFF));
    b[off + 3] = @intCast(u8, v & @intCast(u32, 0xFF));
}

fn wrU64(b: []u8, off: usize, v: u64) void {
    b[off] = @intCast(u8, (v >> 56) & @intCast(u64, 0xFF));
    b[off + 1] = @intCast(u8, (v >> 48) & @intCast(u64, 0xFF));
    b[off + 2] = @intCast(u8, (v >> 40) & @intCast(u64, 0xFF));
    b[off + 3] = @intCast(u8, (v >> 32) & @intCast(u64, 0xFF));
    b[off + 4] = @intCast(u8, (v >> 24) & @intCast(u64, 0xFF));
    b[off + 5] = @intCast(u8, (v >> 16) & @intCast(u64, 0xFF));
    b[off + 6] = @intCast(u8, (v >> 8) & @intCast(u64, 0xFF));
    b[off + 7] = @intCast(u8, v & @intCast(u64, 0xFF));
}

// u32 action at offset 8 = 0 (connect) / 1 (announce) for both request kinds.
fn actionOf(buf: []const u8) u32 {
    return rdU32(buf, 8);
}

fn txnOf(buf: []const u8) u32 {
    return rdU32(buf, 12);
}

fn sendConnect(sock: *std_net.Socket, addr: std_net.IpAddr, port: u16, txn: u32) void {
    wrU32(g_resp[0..], 0, @intCast(u32, 0));
    wrU32(g_resp[0..], 4, txn);
    wrU64(g_resp[0..], 8, CONNECTION_ID);
    std_net.udpSendTo(sock, addr, port, g_resp[0..16]) catch {};
}

fn sendAnnounce(sock: *std_net.Socket, addr: std_net.IpAddr, port: u16, txn: u32, event_code: u32) void {
    logEvent(event_code);
    wrU32(g_resp[0..], 0, @intCast(u32, 1));
    wrU32(g_resp[0..], 4, txn);
    wrU32(g_resp[0..], 8, INTERVAL);
    wrU32(g_resp[0..], 12, LEECHERS);
    wrU32(g_resp[0..], 16, SEEDERS);
    var off: usize = 20;
    var k: usize = 0;
    while (k < g_npeers) : (k += 1) {
        g_resp[off] = g_ips[k][0];
        g_resp[off + 1] = g_ips[k][1];
        g_resp[off + 2] = g_ips[k][2];
        g_resp[off + 3] = g_ips[k][3];
        g_resp[off + 4] = @intCast(u8, (g_ports[k] >> 8) & @intCast(u16, 0xFF));
        g_resp[off + 5] = @intCast(u8, g_ports[k] & @intCast(u16, 0xFF));
        off += 6;
    }
    std_net.udpSendTo(sock, addr, port, g_resp[0..off]) catch {};
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    var port: u32 = DEFAULT_PORT;
    var event_log_path: []const u8 = "";

    const n: usize = @intCast(usize, argc);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--port")) {
            i += 1;
            if (i >= n) { out("mock_udp_tracker: --port needs a value\n"); std.os.exit(1); return; }
            if (parseU32(argAt(argv, i))) |pv| {
                port = pv;
            } else {
                out("mock_udp_tracker: bad --port\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--peer")) {
            i += 1;
            if (i >= n) { out("mock_udp_tracker: --peer needs a value\n"); std.os.exit(1); return; }
            if (!addPeerStr(argAt(argv, i))) {
                out("mock_udp_tracker: bad --peer (want ip:port)\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--peers")) {
            i += 1;
            if (i >= n) { out("mock_udp_tracker: --peers needs a value\n"); std.os.exit(1); return; }
            if (!addPeerList(argAt(argv, i))) {
                out("mock_udp_tracker: bad --peers (want ip:port,ip:port,...)\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--event-log")) {
            i += 1;
            if (i >= n) { out("mock_udp_tracker: --event-log needs a value\n"); std.os.exit(1); return; }
            event_log_path = argAt(argv, i);
        } else if (eq(tok, "--help") or eq(tok, "-h")) {
            var u: []const u8 = "usage: mock_udp_tracker [--port N] [--peer IP:PORT]... [--peers a,b,c] [--event-log FILE]\n";
            out(u);
            std.os.exit(0);
            return;
        } else {
            // Ignore unknown tokens (the tier scripts only pass known flags).
        }
    }

    if (port > 65535) {
        out("mock_udp_tracker: port out of range\n");
        std.os.exit(1);
        return;
    }

    if (g_npeers == 0) {
        if (!addPeerStr("127.0.0.1:6970")) {
            out("mock_udp_tracker: default peer setup failed\n");
            std.os.exit(1);
            return;
        }
    }
    if (event_log_path.len > 0) {
        var fd: ?usize = std.io.fileOpen(event_log_path, true);
        if (fd) |f| {
            g_event_fd = f;
            g_has_event_log = true;
        } else {
            out("mock_udp_tracker: cannot open --event-log\n");
            std.os.exit(1);
            return;
        }
    }

    if (std_net.init() != 0) {
        out("mock_udp_tracker: socket init failed\n");
        return;
    }
    var sock = std_net.udpBind(@intCast(u16, port)) catch {
        out("mock_udp_tracker: udpBind failed\n");
        return;
    };

    var l1: []const u8 = "mock_udp_tracker listening\n";
    out(l1);

    var buf: [RECV_MAX]u8 = undefined;
    while (true) {
        var fa: std_net.IpAddr = undefined;
        var fp: u16 = 0;
        const len = std_net.udpRecvFrom(&sock, buf[0..], &fa, &fp) catch {
            continue;
        };
        if (len < 16) continue;
        var action: u32 = actionOf(buf[0..len]);
        var txn: u32 = txnOf(buf[0..len]);
        if (action == 0) {
            sendConnect(&sock, fa, fp, txn);
        } else if (action == 1) {
            if (len < 98) continue;
            sendAnnounce(&sock, fa, fp, txn, rdU32(buf[0..len], 80));
        } else {
            // ignore unknown actions
        }
    }
}
