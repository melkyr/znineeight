// main.zig — wireguard_demo: userspace TCP/IP through std_wireguard over a
// std_net UDP socket, then a MUD session through the tunnel (Phase 1 M7 T3).
//
// usage: wireguard_demo [wg.conf] [clock_override_unix]
//
// The config file uses `key = value` lines (comments start with # or ;):
//   private_key      = <hex or base64>   required (client interface key)
//   peer_public_key  = <hex or base64>   required (kernel far-side key)
//   endpoint         = <host|ipv4>:port  required (WireGuard UDP endpoint)
//   address          = <ipv4>[/prefix]   required (local tunnel address)
//   gateway          = <ipv4>            optional (default 0)
//   dns_server       = <ipv4>            optional (tunnel DNS, port 53)
//   mud_host         = <ipv4|name>       required (default mud.test)
//   mud_ip           = <ipv4>            optional direct target (skips DNS)
//   mud_port         = <u16>             optional (default 4000)
//   allowed_ips      = <cidr>[,<cidr>]   optional
//   mtu              = <u16>             optional (default 1400)
//   clock_override_unix = <seconds>      optional (dead-RTC machines)
//   seed             = <u64/0x...>       optional (deterministic test RNG)
//   command          = <line>            optional (default "look")
//
// Flow: handshake -> DNS/direct target -> TCP connect to the mud server ->
// print its banner, send one command line, print the reply, then:
//   wireguard_demo ok bytes=N arena_peak=N rss_peak=N cpu_ms=N
// Failures exit nonzero with `wg: <Reason>` or `tcp: <Reason>`.
//
// Sans-I/O: std_tcpip emits/receives raw IPv4 datagrams; this driver encrypts
// them with std_wireguard into UDP datagrams and feeds decrypted inner packets
// back to tcpipPoll. No heap; fixed static buffers and a std_arena stack.

const std = @import("std");
const wg = @import("std_wireguard.zig");
const tcp = @import("std_tcpip.zig");
const rand = @import("std_rand.zig");

const ARENA_SIZE: usize = 512 * 1024;
const CFG_SIZE: usize = 8192;
const MAX_SOCKETS: u32 = 4;
const HANDSHAKE_TIMEOUT_MS: u64 = 15000;
const DNS_TIMEOUT_MS: u64 = 10000;
const CONNECT_TIMEOUT_MS: u64 = 15000;
const IO_TIMEOUT_MS: u64 = 15000;
const UDP_WAIT_MS: u32 = 25;
const DEFAULT_MTU: u16 = 1400;

const DemoError = error{
    BadArgs,
    BadConfig,
    ConfigRead,
    BadKey,
    BadClock,
    BadIp,
    SocketFailed,
    WgCorrupt,
    WgAuthenticationFailed,
    WgNoSession,
    WgSessionExpired,
    WgOutputTooSmall,
    WgTimeout,
    WgNoSpace,
    WgInvalidPeer,
    DnsFailed,
    NoRoute,
    ConnRefused,
    Timeout,
    TcpClosed,
    TcpCorrupt,
    TcpFailed,
    OutOfMemory,
    OutputTooSmall,
};

const Config = struct {
    private_key: [32]u8,
    peer_public_key: [32]u8,
    endpoint_addr: std.net.IpAddr,
    endpoint_port: u16,
    local_ip: u32,
    netmask: u32,
    gateway: u32,
    dns_server: u32,
    mud_ip: u32,
    mud_name: [256]u8,
    mud_name_len: usize,
    mud_is_name: bool,
    mud_port: u16,
    mtu: u16,
    clock_unix: i64,
    seed: u64,
    has_seed: bool,
    command: [128]u8,
    command_len: usize,
    allowed_ips: [wg.WG_MAX_ALLOWED_IPS]wg.WgAllowedIp,
    allowed_count: usize,
    has_priv: bool,
    has_pub: bool,
    has_endpoint: bool,
    has_address: bool,
    has_mud: bool,
};

const Driver = struct {
    dev: wg.WgDevice,
    peer: wg.WgPeer,
    sock: std.net.Socket,
    stack: *tcp.TcpipStack,
    wall_ns: u64,
    now_ms: u64,
    session_up: bool,
    have_rx: bool,
    rx_buf: [2048]u8,
    rx_len: usize,
    pkt_buf: [2048]u8,
    wg_in: [2048]u8,
    wg_out: [2048]u8,
};

var g_cfg_buf: [CFG_SIZE]u8 = undefined;
var g_cfg: Config = undefined;
var g_arena_buf: [ARENA_SIZE]u8 = undefined;
var g_arena = std.arena.init(g_arena_buf[0..]);
var g_peers: [1]wg.WgPeer = undefined;
var g_driver: Driver = undefined;
var g_sock_open: bool = false;

fn out(s: []const u8) void {
    std.io.write(s);
}

fn zeroBytes(p: []u8) void {
    var i: usize = 0;
    while (i < p.len) : (i += 1) p[i] = 0;
}

fn zeroPeer(p: *wg.WgPeer) void {
    var raw: [*]u8 = @ptrCast([*]u8, p);
    var i: usize = 0;
    while (i < @sizeOf(wg.WgPeer)) : (i += 1) raw[i] = 0;
}

fn copyBytes(dst: []u8, src: []const u8) void {
    var n = src.len;
    if (n > dst.len) n = dst.len;
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = src[i];
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
    var i = from;
    while (i + needle.len <= hay.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (hay[i + j] != needle[j]) break;
        }
        if (j == needle.len) return i;
    }
    return hay.len;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

fn trim(s: []const u8) []const u8 {
    var a: usize = 0;
    var b: usize = s.len;
    while (a < b and isSpace(s[a])) : (a += 1) {}
    while (b > a and isSpace(s[b - 1])) : (b -= 1) {}
    return s[a..b];
}

fn lowerAscii(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c - 'A' + 'a';
    return c;
}

fn keyEq(a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < a.len and (a[i] == '_' or a[i] == '-')) : (i += 1) {}
        while (j < b.len and (b[j] == '_' or b[j] == '-')) : (j += 1) {}
        if (i >= a.len or j >= b.len) return i >= a.len and j >= b.len;
        if (lowerAscii(a[i]) != lowerAscii(b[j])) return false;
        i += 1;
        j += 1;
    }
    return false;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn hexVal(c: u8) i32 {
    if (c >= '0' and c <= '9') return @intCast(i32, c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(i32, c - 'a' + 10);
    if (c >= 'A' and c <= 'F') return @intCast(i32, c - 'A' + 10);
    return -1;
}

fn b64Val(c: u8) i32 {
    if (c >= 'A' and c <= 'Z') return @intCast(i32, c - 'A');
    if (c >= 'a' and c <= 'z') return @intCast(i32, c - 'a' + 26);
    if (c >= '0' and c <= '9') return @intCast(i32, c - '0' + 52);
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

fn decodeKey(text0: []const u8, out_key: *[32]u8) bool {
    var text = trim(text0);
    if (text.len >= 2 and ((text[0] == '"' and text[text.len - 1] == '"') or
        (text[0] == '\'' and text[text.len - 1] == '\'')))
    {
        text = text[1 .. text.len - 1];
    }
    if (text.len == 64) {
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            const hi = hexVal(text[i * 2]);
            const lo = hexVal(text[i * 2 + 1]);
            if (hi < 0 or lo < 0) return false;
            out_key[i] = @intCast(u8, (hi << 4) | lo);
        }
        return true;
    }

    var acc: u32 = 0;
    var bits: u8 = 0;
    var oi: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '=') break;
        if (isSpace(c)) continue;
        var v = b64Val(c);
        if (v < 0 and c == '-') v = 62;
        if (v < 0 and c == '_') v = 63;
        if (v < 0) return false;
        acc = ((acc << 6) | @intCast(u32, v)) & 0xFFFFFF;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            if (oi < 32) out_key[oi] = @intCast(u8, (acc >> @intCast(u5, bits)) & 0xFF);
            oi += 1;
        }
    }
    return oi == 32;
}

fn parseU64(s: []const u8) ?u64 {
    var t = trim(s);
    if (t.len == 0) return null;
    var base: u64 = 10;
    var i: usize = 0;
    if (t.len > 2 and t[0] == '0' and (t[1] == 'x' or t[1] == 'X')) {
        base = 16;
        i = 2;
    }
    if (i >= t.len) return null;
    var v: u64 = 0;
    while (i < t.len) : (i += 1) {
        var d: u64 = 0;
        if (isDigit(t[i])) {
            d = @intCast(u64, t[i] - '0');
        } else if (base == 16) {
            const hv = hexVal(t[i]);
            if (hv < 0) return null;
            d = @intCast(u64, hv);
        } else return null;
        if (d >= base) return null;
        if (v > (0xFFFFFFFFFFFFFFFF - d) / base) return null;
        v = v * base + d;
    }
    return v;
}

fn parseI64(s: []const u8) ?i64 {
    var t = trim(s);
    if (t.len == 0) return null;
    var neg = false;
    var i: usize = 0;
    if (t[0] == '-') {
        neg = true;
        i = 1;
    } else if (t[0] == '+') {
        i = 1;
    }
    if (i >= t.len) return null;
    var v: u64 = 0;
    const limit: u64 = @intCast(u64, 9223372036854775807);
    while (i < t.len) : (i += 1) {
        if (!isDigit(t[i])) return null;
        const d: u64 = @intCast(u64, t[i] - '0');
        if (v > (limit - d) / 10) return null;
        v = v * 10 + d;
    }
    if (neg) return -@intCast(i64, v);
    return @intCast(i64, v);
}

fn parseIpv4(text: []const u8, addr: *std.net.IpAddr) bool {
    var octets: [4]u32 = undefined;
    var count: usize = 0;
    var v: u32 = 0;
    var have: bool = false;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '.') {
            if (!have or count >= 4) return false;
            octets[count] = v;
            count += 1;
            v = 0;
            have = false;
        } else if (isDigit(text[i])) {
            v = v * 10 + @intCast(u32, text[i] - '0');
            if (v > 255) return false;
            have = true;
        } else return false;
    }
    if (count != 4) return false;
    addr.* = std.net.IpAddr{
        .a = @intCast(u8, octets[0]),
        .b = @intCast(u8, octets[1]),
        .c = @intCast(u8, octets[2]),
        .d = @intCast(u8, octets[3]),
    };
    return true;
}

fn addrToLogical(a: std.net.IpAddr) u32 {
    return (@intCast(u32, a.a) << 24) | (@intCast(u32, a.b) << 16) |
        (@intCast(u32, a.c) << 8) | @intCast(u32, a.d);
}

fn packedToAddr(p: u32) std.net.IpAddr {
    return std.net.IpAddr{
        .a = @intCast(u8, p & 0xFF),
        .b = @intCast(u8, (p >> 8) & 0xFF),
        .c = @intCast(u8, (p >> 16) & 0xFF),
        .d = @intCast(u8, (p >> 24) & 0xFF),
    };
}

fn prefixMask(prefix: u8) u32 {
    if (prefix == 0) return 0;
    if (prefix >= 32) return 0xFFFFFFFF;
    var m: u32 = 0;
    var i: u8 = 0;
    while (i < prefix) : (i += 1) m = (m << 1) | 1;
    var sh: u8 = 32 - prefix;
    while (sh > 0) : (sh -= 1) m = (m << 1);
    return m;
}

fn parseIpv4WithPrefix(text: []const u8, addr: *std.net.IpAddr, mask: *u32) bool {
    const slash = findFrom(text, "/", 0);
    var ip_part = text;
    var prefix: u8 = 24;
    if (slash < text.len) {
        ip_part = text[0..slash];
        const p = parseU64(text[slash + 1 ..]) orelse return false;
        if (p > 32) return false;
        prefix = @intCast(u8, p);
    }
    if (!parseIpv4(trim(ip_part), addr)) return false;
    mask.* = prefixMask(prefix);
    return true;
}

fn parseHostPort(text: []const u8, addr: *std.net.IpAddr, port: *u16) bool {
    const colon = findFrom(text, ":", 0);
    if (colon >= text.len) return false;
    const host = trim(text[0..colon]);
    const ptxt = trim(text[colon + 1 ..]);
    if (host.len == 0 or ptxt.len == 0) return false;
    const p = parseU64(ptxt) orelse return false;
    if (p == 0 or p > 65535) return false;
    port.* = @intCast(u16, p);
    if (parseIpv4(host, addr)) return true;
    const host_be = std.net.resolve(host) catch return false;
    addr.* = packedToAddr(host_be);
    return true;
}

fn initConfig(c: *Config) void {
    zeroBytes(c.private_key[0..]);
    zeroBytes(c.peer_public_key[0..]);
    c.endpoint_addr = std.net.IpAddr{ .a = 0, .b = 0, .c = 0, .d = 0 };
    c.endpoint_port = 0;
    c.local_ip = 0;
    c.netmask = prefixMask(24);
    c.gateway = 0;
    c.dns_server = 0;
    c.mud_ip = 0;
    c.mud_name_len = 0;
    zeroBytes(c.mud_name[0..]);
    c.mud_is_name = false;
    c.mud_port = 4000;
    c.mtu = DEFAULT_MTU;
    c.clock_unix = 0;
    c.seed = 0;
    c.has_seed = false;
    copyBytes(c.command[0..], "look\n");
    c.command_len = 5;
    c.allowed_count = 0;
    c.has_priv = false;
    c.has_pub = false;
    c.has_endpoint = false;
    c.has_address = false;
    c.has_mud = false;
}

fn setCommand(c: *Config, val: []const u8) void {
    var t = trim(val);
    if (t.len >= 2 and ((t[0] == '"' and t[t.len - 1] == '"') or
        (t[0] == '\'' and t[t.len - 1] == '\'')))
    {
        t = t[1 .. t.len - 1];
    }
    if (t.len == 0) {
        copyBytes(c.command[0..], "look\n");
        c.command_len = 5;
        return;
    }
    var n = t.len;
    if (n > c.command.len - 1) n = c.command.len - 1;
    copyBytes(c.command[0..], t[0..n]);
    c.command_len = n;
    if (c.command[c.command_len - 1] != '\n') {
        c.command[c.command_len] = '\n';
        c.command_len += 1;
    }
}

fn parseAllowed(c: *Config, val: []const u8) DemoError!void {
    c.allowed_count = 0;
    var start: usize = 0;
    while (start <= val.len) {
        var end = start;
        while (end < val.len and val[end] != ',') : (end += 1) {}
        const item = trim(val[start..end]);
        if (item.len != 0) {
            if (c.allowed_count >= wg.WG_MAX_ALLOWED_IPS) return DemoError.BadConfig;
            var addr: std.net.IpAddr = undefined;
            var mask: u32 = 0;
            if (!parseIpv4WithPrefix(item, &addr, &mask)) return DemoError.BadConfig;
            c.allowed_ips[c.allowed_count] = wg.WgAllowedIp{ .ip = addrToLogical(addr), .mask = mask };
            c.allowed_count += 1;
        }
        if (end == val.len) break;
        start = end + 1;
    }
}

fn setConfigValue(c: *Config, key: []const u8, val0: []const u8) DemoError!void {
    const val = trim(val0);
    if (keyEq(key, "private_key") or keyEq(key, "privatekey")) {
        if (!decodeKey(val, &c.private_key)) return DemoError.BadKey;
        c.has_priv = true;
    } else if (keyEq(key, "peer_public_key") or keyEq(key, "publickey") or keyEq(key, "peerpublickey")) {
        if (!decodeKey(val, &c.peer_public_key)) return DemoError.BadKey;
        c.has_pub = true;
    } else if (keyEq(key, "endpoint")) {
        if (!parseHostPort(val, &c.endpoint_addr, &c.endpoint_port)) return DemoError.BadConfig;
        c.has_endpoint = true;
    } else if (keyEq(key, "address") or keyEq(key, "tunnel_ip") or keyEq(key, "tunnelip") or keyEq(key, "local_ip") or keyEq(key, "localip")) {
        var addr: std.net.IpAddr = undefined;
        var mask: u32 = 0;
        if (!parseIpv4WithPrefix(val, &addr, &mask)) return DemoError.BadIp;
        c.local_ip = addrToLogical(addr);
        c.netmask = mask;
        c.has_address = true;
    } else if (keyEq(key, "gateway")) {
        var addr: std.net.IpAddr = undefined;
        if (!parseIpv4(val, &addr)) return DemoError.BadIp;
        c.gateway = addrToLogical(addr);
    } else if (keyEq(key, "dns_server") or keyEq(key, "dnsserver") or keyEq(key, "dns")) {
        var addr: std.net.IpAddr = undefined;
        if (!parseIpv4(val, &addr)) return DemoError.BadIp;
        c.dns_server = addrToLogical(addr);
    } else if (keyEq(key, "mud_ip") or keyEq(key, "mudip") or keyEq(key, "server_ip") or keyEq(key, "serverip")) {
        var addr: std.net.IpAddr = undefined;
        if (!parseIpv4(val, &addr)) return DemoError.BadIp;
        c.mud_ip = addrToLogical(addr);
        c.mud_is_name = false;
        c.has_mud = true;
    } else if (keyEq(key, "mud_host") or keyEq(key, "mudhost") or keyEq(key, "server_host") or keyEq(key, "serverhost") or keyEq(key, "mud")) {
        var addr: std.net.IpAddr = undefined;
        if (parseIpv4(val, &addr)) {
            c.mud_ip = addrToLogical(addr);
            c.mud_is_name = false;
        } else {
            if (val.len == 0 or val.len >= c.mud_name.len) return DemoError.BadConfig;
            copyBytes(c.mud_name[0..], val);
            c.mud_name_len = val.len;
            c.mud_is_name = true;
        }
        c.has_mud = true;
    } else if (keyEq(key, "mud_port") or keyEq(key, "mudport") or keyEq(key, "server_port") or keyEq(key, "serverport")) {
        const p = parseU64(val) orelse return DemoError.BadConfig;
        if (p == 0 or p > 65535) return DemoError.BadConfig;
        c.mud_port = @intCast(u16, p);
    } else if (keyEq(key, "mtu")) {
        const m = parseU64(val) orelse return DemoError.BadConfig;
        if (m < 64 or m > 9000) return DemoError.BadConfig;
        c.mtu = @intCast(u16, m);
    } else if (keyEq(key, "clock_override_unix") or keyEq(key, "clockoverrideunix")) {
        c.clock_unix = parseI64(val) orelse return DemoError.BadConfig;
    } else if (keyEq(key, "seed")) {
        c.seed = parseU64(val) orelse return DemoError.BadConfig;
        c.has_seed = true;
    } else if (keyEq(key, "command")) {
        setCommand(c, val);
    } else if (keyEq(key, "allowed_ips") or keyEq(key, "allowedips")) {
        try parseAllowed(c, val);
    } else {
        return DemoError.BadConfig;
    }
}

fn parseConfig(c: *Config, len: usize) DemoError!void {
    var pos: usize = 0;
    while (pos < len) {
        var end = pos;
        while (end < len and g_cfg_buf[end] != '\n') : (end += 1) {}
        var line = trim(g_cfg_buf[pos..end]);
        // Strip an unquoted inline comment.
        var ci: usize = 0;
        while (ci < line.len) : (ci += 1) {
            if ((line[ci] == '#' or line[ci] == ';') and (ci == 0 or isSpace(line[ci - 1]))) {
                line = trim(line[0..ci]);
                break;
            }
        }
        if (line.len != 0) {
            const sep = findFrom(line, "=", 0);
            if (sep >= line.len) return DemoError.BadConfig;
            const key = trim(line[0..sep]);
            const val = trim(line[sep + 1 ..]);
            try setConfigValue(c, key, val);
        }
        pos = end + 1;
    }
    if (!c.has_priv or !c.has_pub or !c.has_endpoint or !c.has_address or !c.has_mud) {
        return DemoError.BadConfig;
    }
    if (c.mud_is_name and c.dns_server == 0) return DemoError.BadConfig;
}

fn loadConfig(path: []const u8, c: *Config) DemoError!void {
    initConfig(c);
    const fd = std.io.fileOpen(path, false) orelse return DemoError.ConfigRead;
    const n = std.io.fileRead(fd, g_cfg_buf[0..]);
    std.io.fileClose(fd);
    if (n == 0 or n >= CFG_SIZE) return DemoError.ConfigRead;
    try parseConfig(c, n);
}

fn nowMs() u64 {
    const freq = std.time.highResFreq();
    const t = std.time.highRes();
    if (freq == 0) return t / 1000000;
    if (freq >= 1000) return t / (freq / 1000);
    return (t * 1000) / freq;
}

fn mapWg(e: wg.WgError) DemoError {
    if (e == error.Corrupt) return DemoError.WgCorrupt;
    if (e == error.AuthenticationFailed) return DemoError.WgAuthenticationFailed;
    if (e == error.NoSession) return DemoError.WgNoSession;
    if (e == error.SessionExpired) return DemoError.WgSessionExpired;
    if (e == error.OutputTooSmall) return DemoError.WgOutputTooSmall;
    if (e == error.NoSpace) return DemoError.WgNoSpace;
    if (e == error.InvalidPeer) return DemoError.WgInvalidPeer;
    return DemoError.WgCorrupt;
}

fn mapTcp(e: i32) DemoError {
    if (e == error.Corrupt) return DemoError.TcpCorrupt;
    if (e == error.NoRoute) return DemoError.NoRoute;
    if (e == error.ConnRefused) return DemoError.ConnRefused;
    if (e == error.Timeout) return DemoError.Timeout;
    if (e == error.DnsFailed) return DemoError.DnsFailed;
    if (e == error.OutOfMemory) return DemoError.OutOfMemory;
    if (e == error.OutputTooSmall) return DemoError.OutputTooSmall;
    if (e == error.Closed) return DemoError.TcpClosed;
    return DemoError.TcpFailed;
}

fn fail(e: DemoError) noreturn {
    var prefix: []const u8 = "wg: ";
    var name: []const u8 = "BadConfig";
    if (e == DemoError.BadArgs) {
        name = "BadArgs";
    } else if (e == DemoError.ConfigRead) {
        name = "ConfigRead";
    } else if (e == DemoError.BadKey) {
        name = "BadKey";
    } else if (e == DemoError.BadClock) {
        name = "BadClock";
    } else if (e == DemoError.BadIp) {
        name = "BadIp";
    } else if (e == DemoError.SocketFailed) {
        name = "SocketFailed";
    } else if (e == DemoError.WgCorrupt) {
        name = "Corrupt";
    } else if (e == DemoError.WgAuthenticationFailed) {
        name = "AuthenticationFailed";
    } else if (e == DemoError.WgNoSession) {
        name = "NoSession";
    } else if (e == DemoError.WgSessionExpired) {
        name = "SessionExpired";
    } else if (e == DemoError.WgOutputTooSmall) {
        name = "OutputTooSmall";
    } else if (e == DemoError.WgTimeout) {
        name = "Timeout";
    } else if (e == DemoError.WgNoSpace) {
        name = "NoSpace";
    } else if (e == DemoError.WgInvalidPeer) {
        name = "InvalidPeer";
    } else {
        prefix = "tcp: ";
        if (e == DemoError.DnsFailed) {
            name = "DnsFailed";
        } else if (e == DemoError.NoRoute) {
            name = "NoRoute";
        } else if (e == DemoError.ConnRefused) {
            name = "ConnRefused";
        } else if (e == DemoError.Timeout) {
            name = "Timeout";
        } else if (e == DemoError.TcpClosed) {
            name = "Closed";
        } else if (e == DemoError.TcpCorrupt) {
            name = "Corrupt";
        } else if (e == DemoError.TcpFailed) {
            name = "Failed";
        } else if (e == DemoError.OutOfMemory) {
            name = "OutOfMemory";
        } else if (e == DemoError.OutputTooSmall) {
            name = "OutputTooSmall";
        }
    }
    out(prefix);
    out(name);
    out("\n");
    std.os.exit(1);
}

fn sameAddr(a: std.net.IpAddr, b: std.net.IpAddr) bool {
    return a.a == b.a and a.b == b.b and a.c == b.c and a.d == b.d;
}

fn sendUdp(d: *Driver, data: []const u8) DemoError!void {
    std.net.udpSendTo(&d.sock, g_cfg.endpoint_addr, g_cfg.endpoint_port, data) catch |e| {
        return DemoError.SocketFailed;
    };
}

fn recvUdp(d: *Driver, timeout_ms: u32) DemoError!usize {
    var from: std.net.IpAddr = undefined;
    var from_port: u16 = 0;
    const n = std.net.udpRecvFrom(&d.sock, d.wg_in[0..], &from, &from_port) catch |e| {
        if (e == error.Timeout) return 0;
        return DemoError.SocketFailed;
    };
    if (n == 0) return 0;
    if (!sameAddr(from, g_cfg.endpoint_addr) or from_port != g_cfg.endpoint_port) return 0;
    return n;
}

fn handleWgAction(d: *Driver, act: wg.WgAction) DemoError!void {
    switch (act) {
        .session_up => {
            d.session_up = true;
        },
        .inner_packet => |n| {
            var len = n;
            if (len > d.rx_buf.len) len = d.rx_buf.len;
            copyBytes(d.rx_buf[0..], d.wg_out[0..len]);
            d.rx_len = len;
            d.have_rx = true;
        },
        .send_handshake => |n| {
            try sendUdp(d, d.wg_out[0..n]);
        },
        .send_keepalive => |n| {
            try sendUdp(d, d.wg_out[0..n]);
        },
        .none => {},
        .dropped_replay => {},
        else => {},
    }
}

fn handshake(d: *Driver) DemoError!void {
    const deadline = nowMs() + HANDSHAKE_TIMEOUT_MS;
    var attempts: u32 = 0;
    while (!d.session_up) {
        d.now_ms = nowMs();
        if (d.now_ms > deadline) return DemoError.WgTimeout;
        const act = wg.wgTick(&d.dev, d.now_ms, d.wall_ns, d.wg_out[0..]) catch |e| return mapWg(e);
        switch (act) {
            .send_handshake => |n| try sendUdp(d, d.wg_out[0..n]),
            .send_keepalive => |n| try sendUdp(d, d.wg_out[0..n]),
            .session_up => d.session_up = true,
            .inner_packet => {},
            .none => {},
            .dropped_replay => {},

            else => {},
        }
        if (d.session_up) return;
        const n = try recvUdp(d, UDP_WAIT_MS);
        if (n > 0) {
            const ract = wg.wgReceive(&d.dev, d.now_ms, d.wg_in[0..n], d.wg_out[0..]) catch |e| return mapWg(e);
            switch (ract) {
                .session_up => d.session_up = true,
                .inner_packet => {},
                .none => {},
                .send_handshake => |wn| try sendUdp(d, d.wg_out[0..wn]),
                .send_keepalive => |wn| try sendUdp(d, d.wg_out[0..wn]),
                .dropped_replay => {},
                else => {},
            }
        }
        attempts +%= 1;
        if (attempts == 0) return DemoError.WgTimeout;
    }
}

fn pumpStep(d: *Driver) DemoError!tcp.TcpipAction {
    var iter: u32 = 0;
    while (iter < 128) : (iter += 1) {
        d.now_ms = nowMs();
        const wact = wg.wgTick(&d.dev, d.now_ms, d.wall_ns, d.wg_out[0..]) catch |e| return mapWg(e);
        switch (wact) {
            .send_handshake => |n| try sendUdp(d, d.wg_out[0..n]),
            .send_keepalive => |n| try sendUdp(d, d.wg_out[0..n]),
            .session_up => d.session_up = true,
            .inner_packet => {},
            .none => {},
            .dropped_replay => {},
            else => {},
        }

        const rx: ?[]const u8 = if (d.have_rx) d.rx_buf[0..d.rx_len] else null;
        const act = tcp.tcpipPoll(d.stack, d.now_ms, rx, d.pkt_buf[0..]) catch |e| return mapTcp(e);
        d.have_rx = false;

        switch (act) {
            .send_pkt => |inner| {
                const n = wg.wgSend(&d.dev, d.now_ms, d.wall_ns, inner, d.wg_out[0..]) catch |e| return mapWg(e);
                try sendUdp(d, d.wg_out[0..n]);
                continue;
            },
            .wait => |ms| {
                var w: u32 = ms;
                if (w > UDP_WAIT_MS) w = UDP_WAIT_MS;
                if (w == 0) w = 1;
                const n = try recvUdp(d, w);
                if (n > 0) {
                    const ract = wg.wgReceive(&d.dev, d.now_ms, d.wg_in[0..n], d.wg_out[0..]) catch |e| return mapWg(e);
                    try handleWgAction(d, ract);
                }
                continue;
            },
            .connected => return act,
            .data => return act,
            .closed => return act,
            .failed => return act,
            .done => return act,
            else => return act,
        }
    }
    return tcp.TcpipAction{ .wait = 1 };
}

fn waitDone(d: *Driver, deadline: u64) DemoError!void {
    var guard: u32 = 0;
    while (guard < 1000000) : (guard += 1) {
        const act = try pumpStep(d);
        switch (act) {
            .done => return,
            .failed => |id| {
                _ = id;
                return DemoError.TcpFailed;
            },
            else => {},
        }
        if (nowMs() > deadline) return DemoError.Timeout;
    }
    return DemoError.Timeout;
}

fn tryDns(d: *Driver, name: []const u8, out_ip: *u32) DemoError!bool {
    tcp.dnsResolve(d.stack, name, out_ip) catch |e| {
        if (e == error.Timeout) return false;
        return mapTcp(e);
    };
    return true;
}

fn resolveMud(d: *Driver) DemoError!u32 {
    if (!g_cfg.mud_is_name) return g_cfg.mud_ip;
    if (g_cfg.dns_server == 0) return DemoError.BadConfig;
    const deadline = nowMs() + DNS_TIMEOUT_MS;
    var ip: u32 = 0;
    while (true) {
        if (try tryDns(d, g_cfg.mud_name[0..g_cfg.mud_name_len], &ip)) return ip;
        try waitDone(d, deadline);
        if (nowMs() > deadline) return DemoError.Timeout;
    }
    return DemoError.Timeout;
}

fn waitConnected(d: *Driver, sock: u32, deadline: u64) DemoError!void {
    var guard: u32 = 0;
    while (guard < 1000000) : (guard += 1) {
        const act = try pumpStep(d);
        switch (act) {
            .connected => |id| {
                if (id == sock) return;
            },
            .failed => |id| {
                if (id == sock) return DemoError.ConnRefused;
            },
            .closed => |id| {
                if (id == sock) return DemoError.TcpClosed;
            },
            else => {},
        }
        if (nowMs() > deadline) return DemoError.Timeout;
    }
    return DemoError.Timeout;
}

fn readSome(d: *Driver, sock: u32, buf: []u8, deadline: u64) DemoError!usize {
    var guard: u32 = 0;
    while (guard < 1000000) : (guard += 1) {
        const act = try pumpStep(d);
        switch (act) {
            .data => |id| {
                if (id == sock) {
                    const n = tcp.tcpRecv(d.stack, sock, buf) catch |e| return mapTcp(e);
                    if (n > 0) return n;
                }
            },
            .failed => |id| {
                if (id == sock) return DemoError.TcpFailed;
            },
            .closed => |id| {
                if (id == sock) return 0;
            },
            else => {},
        }
        if (nowMs() > deadline) return DemoError.Timeout;
    }
    return DemoError.Timeout;
}

fn readLine(d: *Driver, sock: u32, buf: []u8, deadline: u64) DemoError!usize {
    var used: usize = 0;
    while (used < buf.len) {
        const n = try readSome(d, sock, buf[used..], deadline);
        if (n == 0) return used;
        used += n;
        var i: usize = 0;
        while (i < used) : (i += 1) {
            if (buf[i] == '\n') return used;
        }
    }
    return used;
}

fn sendCommand(d: *Driver, sock: u32) DemoError!void {
    var sent: usize = 0;
    while (sent < g_cfg.command_len) {
        const n = tcp.tcpSend(d.stack, sock, g_cfg.command[sent..g_cfg.command_len]) catch |e| return mapTcp(e);
        if (n == 0) return DemoError.TcpClosed;
        sent += n;
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
    while (i < raw.len and isSpace(raw[i])) : (i += 1) {}
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
    var found = false;
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
        while (p < raw.len and isSpace(raw[p])) : (p += 1) {}
        if (p >= raw.len) break;
        const start = p;
        while (p < raw.len and !isSpace(raw[p])) : (p += 1) {}
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
    var x = v;
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
    while (i < len) : (i += 1) buf[i] = tmp[len - 1 - i];
    out(buf[0..len]);
}

fn printResource(bytes: usize) void {
    out("wireguard_demo ok bytes=");
    writeU64(@intCast(u64, bytes));
    out(" arena_peak=");
    writeU64(@intCast(u64, g_arena.used));
    out(" rss_peak=");
    writeU64(rssPeakKb());
    out(" cpu_ms=");
    writeU64(cpuMs());
    out("\n");
}

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn setupDriver(d: *Driver, wall_sec: i64) DemoError!void {
    var tcfg = tcp.TcpipConfig{
        .ip = g_cfg.local_ip,
        .netmask = g_cfg.netmask,
        .gateway = g_cfg.gateway,
        .mtu = g_cfg.mtu,
        .dns_server = g_cfg.dns_server,
        .max_sockets = MAX_SOCKETS,
    };
    d.stack = tcp.tcpipInit(&g_arena, &tcfg) catch |e| return mapTcp(e);

    d.wall_ns = @intCast(u64, wall_sec) * 1000000000;
    d.dev.peers = g_peers[0..];
    wg.wgInit(&d.dev, &g_cfg.private_key);
    var seed: u64 = 0;
    if (g_cfg.has_seed) {
        seed = g_cfg.seed;
    } else {
        seed = std.time.highRes() ^ d.wall_ns ^ @intCast(u64, g_cfg.local_ip) ^ @intCast(u64, g_cfg.endpoint_port);
    }
    d.dev.rng = rand.xoshiroInit(seed);

    var pp: *wg.WgPeer = &g_peers[0];
    zeroPeer(pp);
    copyBytes(pp.static_priv[0..], g_cfg.private_key[0..]);
    copyBytes(pp.remote_static_pub[0..], g_cfg.peer_public_key[0..]);
    pp.endpoint_ip = addrToLogical(g_cfg.endpoint_addr);
    pp.endpoint_port = g_cfg.endpoint_port;
    pp.allowed_ip_count = g_cfg.allowed_count;
    var i: usize = 0;
    while (i < g_cfg.allowed_count) : (i += 1) {
        pp.allowed_ips[i] = g_cfg.allowed_ips[i];
    }
    wg.wgAddPeer(&d.dev, pp) catch |e| return mapWg(e);

    d.sock = std.net.udpBind(0) catch return DemoError.SocketFailed;
    g_sock_open = true;
    std.net.udpSetTimeout(&d.sock, UDP_WAIT_MS) catch return DemoError.SocketFailed;

    d.session_up = false;
    d.have_rx = false;
    d.rx_len = 0;
    d.now_ms = nowMs();
}

fn run(argc: i32, argv: [*][*]u8) DemoError!void {
    const n: usize = @intCast(usize, argc);
    if (n > 3) return DemoError.BadArgs;

    var cfg_path: []const u8 = "wg.conf";
    if (n >= 2) cfg_path = argAt(argv, 1);
    try loadConfig(cfg_path, &g_cfg);

    var wall_sec = g_cfg.clock_unix;
    if (n >= 3) {
        wall_sec = parseI64(argAt(argv, 2)) orelse return DemoError.BadArgs;
    }
    if (wall_sec == 0) wall_sec = std.time.wallClockUnix();
    if (wall_sec <= 0) return DemoError.BadClock;

    try setupDriver(&g_driver, wall_sec);
    try handshake(&g_driver);

    const mud_ip = try resolveMud(&g_driver);
    const sock = tcp.tcpConnect(g_driver.stack, mud_ip, g_cfg.mud_port) catch |e| return mapTcp(e);

    try waitConnected(&g_driver, sock, nowMs() + CONNECT_TIMEOUT_MS);

    var banner: [512]u8 = undefined;
    const bn = try readLine(&g_driver, sock, banner[0..], nowMs() + IO_TIMEOUT_MS);
    if (bn == 0) return DemoError.TcpClosed;

    try sendCommand(&g_driver, sock);

    var reply: [512]u8 = undefined;
    const rn = try readLine(&g_driver, sock, reply[0..], nowMs() + IO_TIMEOUT_MS);
    if (rn == 0) return DemoError.TcpClosed;

    out(banner[0..bn]);
    out(reply[0..rn]);
    if (reply[rn - 1] != '\n') out("\n");
    printResource(bn + rn);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = std.net.init();
    run(argc, argv) catch |e| {
        if (g_sock_open) std.net.close(g_driver.sock);
        std.net.cleanup();
        fail(e);
    };
    if (g_sock_open) std.net.close(g_driver.sock);
    std.net.cleanup();
    std.os.exit(0);
}
