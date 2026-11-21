// stdlib_tls_alpn_xmod — STDLIB std_tls TLS ALPN negotiation (Phase 3.3).
//
// Server-dependent fixture: takes `<host:port> <mode>` from argv, connects to a
// real `openssl s_server` started by scripts/stdlib/run_tls_alpn.sh against the
// committed localhost certificate, performs the handshake, and prints
// `alpn=<none|h2|http11>`.
//
// Modes:
//   1.2h2       TLS 1.2 only, alpn_h2 = true             -> server selects h2
//   1.3h2       TLS 1.3 only, alpn_h2 = true             -> server selects h2
//   1.3http11   TLS 1.3 only, alpn_h2 = true             -> server selects http/1.1
//   1.3none     TLS 1.3 only, alpn_h2 = false            -> no ALPN offered
//   1.3chacha   TLS 1.3 only, alpn_h2 = true, prefer_chacha20 = true; the first
//               ClientHello suite MUST be 0x1303 and the first supported group
//               MUST be x25519
//   1.3badalpn  TLS 1.3 only, alpn_h2 = true; the server offers only `foo`, so
//               the handshake fails closed and the result is never h2/http11
//
// The argless run prints one usage line to stdout and exits 2 (pinned golden).
//
// GREEN (contract): stdout `alpn=<selected>` and exit 0 for every mode.
const std = @import("std");
const tls = @import("std_tls.zig");
const net = @import("std_net.zig");
const os = @import("std_os.zig");
const rand = @import("std_rand.zig");
const x509 = @import("std_x509.zig");

const usage_line = "usage: stdlib_tls_alpn_xmod <host:port> <mode>\n";
const now_unix: i64 = 1893456000; // 2030-01-01, inside the committed cert window
const seed: u64 = 0x0123456789abcdef;
const CONNECT_TIMEOUT_MS: u32 = 15000;

// Trust anchor: examples/z98/demo/tls_demo/tests/certs/store.bin (Z98 M4 Test
// Root), embedded so the fixture is independent of the run CWD.
const store_bin = [_]u8{
    0x5a, 0x39, 0x38, 0x43, 0x41, 0x31, 0x30, 0x30, 0x01, 0x00, 0x00, 0x00,
    0x5f, 0x01, 0x00, 0x00, 0x1d, 0x00, 0x26, 0x01, 0x17, 0x7f, 0xda, 0x6a,
    0x17, 0x85, 0x72, 0x90, 0x30, 0x1b, 0x31, 0x19, 0x30, 0x17, 0x06, 0x03,
    0x55, 0x04, 0x03, 0x0c, 0x10, 0x5a, 0x39, 0x38, 0x20, 0x4d, 0x34, 0x20,
    0x54, 0x65, 0x73, 0x74, 0x20, 0x52, 0x6f, 0x6f, 0x74, 0x30, 0x82, 0x01,
    0x22, 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01,
    0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00, 0x30, 0x82, 0x01,
    0x0a, 0x02, 0x82, 0x01, 0x01, 0x00, 0xa5, 0xc8, 0x62, 0xce, 0x1c, 0x5b,
    0xc1, 0xcf, 0x9f, 0x11, 0x41, 0x87, 0xde, 0xc0, 0x0e, 0xe2, 0xef, 0xe5,
    0x2a, 0x99, 0xa1, 0xe6, 0x0b, 0xc5, 0x1b, 0x98, 0x6c, 0xf2, 0x28, 0x83,
    0xc7, 0x7d, 0xfe, 0x29, 0x15, 0xe0, 0xa9, 0xd1, 0x9c, 0x2a, 0xa0, 0xd8,
    0x5a, 0x67, 0xcb, 0xe6, 0x0f, 0x5a, 0xa4, 0x84, 0xca, 0x0b, 0x5d, 0x90,
    0xc1, 0xdf, 0x01, 0x71, 0xa6, 0x5a, 0x1e, 0x1c, 0x4a, 0x2d, 0x94, 0xbb,
    0x38, 0xc7, 0xf1, 0x64, 0x11, 0xb3, 0xec, 0xc1, 0x52, 0xa7, 0xc1, 0x87,
    0x0b, 0xc8, 0xd3, 0x4c, 0xd8, 0x7a, 0x47, 0x17, 0x11, 0x09, 0x7a, 0x45,
    0x44, 0x59, 0x0c, 0xc8, 0xad, 0xd5, 0x0d, 0xfb, 0x12, 0xc1, 0x4c, 0x27,
    0xf2, 0x00, 0xa6, 0xc9, 0x3b, 0x2b, 0x52, 0xe9, 0x05, 0x59, 0xfc, 0xc2,
    0xab, 0x62, 0x1f, 0x12, 0xd7, 0x02, 0xa9, 0x21, 0x06, 0x39, 0x1b, 0x59,
    0x7d, 0x5e, 0x02, 0x2e, 0x9f, 0x1e, 0x0f, 0x44, 0xec, 0x66, 0x6c, 0xce,
    0xba, 0x68, 0x4a, 0x39, 0x98, 0xe7, 0x2a, 0x63, 0x82, 0xfb, 0xe5, 0xf2,
    0x53, 0xae, 0x7f, 0x61, 0x0a, 0x19, 0xcf, 0xd7, 0xae, 0x7a, 0x11, 0xce,
    0xf8, 0x45, 0x06, 0x8c, 0x60, 0x5a, 0xcf, 0x2e, 0x74, 0x60, 0x08, 0x90,
    0x0f, 0x24, 0x4d, 0x59, 0xd8, 0x77, 0xcd, 0x2e, 0xcc, 0x64, 0x6c, 0x62,
    0xfa, 0x3a, 0x68, 0xcc, 0xcc, 0xf1, 0x82, 0xb2, 0xff, 0xd3, 0x65, 0x4d,
    0x1f, 0xce, 0x16, 0x4b, 0xf2, 0x88, 0x85, 0x57, 0x22, 0x4b, 0x0a, 0x0e,
    0x57, 0x2b, 0x21, 0x23, 0x0e, 0x6f, 0xdf, 0xb5, 0xba, 0xc5, 0x14, 0x96,
    0xde, 0x18, 0x4c, 0x1f, 0xd1, 0xe0, 0x7b, 0x3a, 0xcc, 0x11, 0x8e, 0x7c,
    0x33, 0xd2, 0xc1, 0x93, 0x26, 0x6b, 0x4f, 0xf1, 0x75, 0xe9, 0xc8, 0x3c,
    0xfc, 0x46, 0x72, 0xe6, 0xee, 0xb1, 0xbe, 0x07, 0x74, 0x05, 0x02, 0x03,
    0x01, 0x00, 0x01,
};

var g_store_arena_buf: [32768]u8 = undefined;
var g_session: tls.TlsSession = undefined;

fn out(s: []const u8) void {
    std.io.write(s);
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn load16(in: []const u8, off: usize) u16 {
    return (@intCast(u16, in[off]) << 8) | @intCast(u16, in[off + 1]);
}

fn parsePort(s: []const u8, out_port: *u16) bool {
    if (s.len == 0 or s.len > 5) return false;
    var v: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return false;
        v = v * 10 + @intCast(u32, s[i] - '0');
    }
    if (v == 0 or v > 65535) return false;
    out_port.* = @intCast(u16, v);
    return true;
}

fn parseEndpoint(s: []const u8, host_out: *[]const u8, port_out: *u16) bool {
    var i: usize = s.len;
    while (i > 0) {
        i -= 1;
        if (s[i] == ':') {
            if (i == 0) return false;
            host_out.* = s[0..i];
            return parsePort(s[i + 1 ..], port_out);
        }
    }
    return false;
}

// The first outgoing record is the ClientHello: 5-byte record header then the
// 4-byte handshake header. Locate the first cipher suite / supported group.
fn firstSuite(raw: []const u8) u16 {
    if (raw.len < 9 + 38) return 0;
    const body = raw[9..];
    const sid_len = @intCast(usize, body[34]);
    const pos = 35 + sid_len + 2;
    if (pos + 2 > body.len) return 0;
    return load16(body, pos);
}

fn firstGroup(raw: []const u8) u16 {
    if (raw.len < 9 + 38) return 0;
    const body = raw[9..];
    const sid_len = @intCast(usize, body[34]);
    var pos: usize = 35 + sid_len;
    if (pos + 2 > body.len) return 0;
    const suites_len = @intCast(usize, load16(body, pos));
    pos += 2 + suites_len;
    if (pos + 1 > body.len) return 0;
    const comp_len = @intCast(usize, body[pos]);
    pos += 1 + comp_len;
    if (pos + 2 > body.len) return 0;
    const ext_total = @intCast(usize, load16(body, pos));
    pos += 2;
    const end = pos + ext_total;
    if (end > body.len) return 0;
    while (pos + 4 <= end) {
        const ext_type = load16(body, pos);
        const ext_len = @intCast(usize, load16(body, pos + 2));
        pos += 4;
        if (ext_len > end - pos) return 0;
        if (ext_type == 0x000A) {
            if (ext_len < 4) return 0;
            return load16(body, pos + 2);
        }
        pos += ext_len;
    }
    return 0;
}

fn sendAll(fd: i32, data: []const u8) bool {
    var sent: usize = 0;
    while (sent < data.len) {
        const n = net.send(fd, @ptrCast([*]const u8, data.ptr + sent),
            @intCast(i32, data.len - sent));
        if (n <= 0) return false;
        sent += @intCast(usize, n);
    }
    return true;
}

fn recvSome(fd: i32, buf: []u8) i32 {
    return net.recv(fd, @ptrCast([*]u8, buf.ptr), @intCast(i32, buf.len));
}

fn alpnName(a: tls.AlpnProtocol) []const u8 {
    if (a == tls.AlpnProtocol.h2) return "h2";
    if (a == tls.AlpnProtocol.http11) return "http11";
    if (a == tls.AlpnProtocol.other) return "other";
    return "none";
}

fn failTls(mode: []const u8) tls.TlsAction {
    if (eqBytes(mode, "1.3badalpn")) {
        out("alpn=none\n");
        os.exit(0);
    }
    out("alpn=handshake-failed\n");
    os.exit(1);
    return tls.TlsAction{ .closed = {} };
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (os.argc() != 3) {
        out(usage_line);
        os.exit(2);
    }

    var host: []const u8 = "";
    var port: u16 = 0;
    if (!parseEndpoint(os.argv(1), &host, &port)) {
        out(usage_line);
        os.exit(2);
    }
    const mode = os.argv(2);

    var min_version = tls.TLS_VERSION_13;
    var max_version = tls.TLS_VERSION_13;
    var alpn_h2 = true;
    var prefer_chacha20 = false;
    if (eqBytes(mode, "1.2h2")) {
        min_version = tls.TLS_VERSION_12;
        max_version = tls.TLS_VERSION_12;
    } else if (eqBytes(mode, "1.3h2")) {
        // defaults
    } else if (eqBytes(mode, "1.3http11")) {
        // defaults (server selects http/1.1 from the h2+http/1.1 offer)
    } else if (eqBytes(mode, "1.3none")) {
        alpn_h2 = false;
    } else if (eqBytes(mode, "1.3chacha")) {
        prefer_chacha20 = true;
    } else if (eqBytes(mode, "1.3badalpn")) {
        // defaults; server offers only `foo`
    } else {
        out(usage_line);
        os.exit(2);
    }

    var arena = std.arena.init(g_store_arena_buf[0..]);
    var store: x509.TrustStore = undefined;
    x509.trustStoreLoad(&arena, store_bin[0..], &store) catch {
        out("alpn=store-failed\n");
        os.exit(1);
    };

    var rng = rand.xoshiroInit(seed);
    var cfg = tls.TlsConfig{
        .hostname = host,
        .store = &store,
        .rng = &rng,
        .now_unix = now_unix,
        .min_version = min_version,
        .max_version = max_version,
        .alpn_h2 = alpn_h2,
        .prefer_chacha20 = prefer_chacha20,
    };
    tls.tlsInit(&g_session, &cfg);

    const fd = net.createTcpClient(port);
    if (fd < 0) {
        out("alpn=connect-failed\n");
        os.exit(1);
    }

    var outbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var inbuf: [tls.TLS_MAX_WIRE_RECORD]u8 = undefined;
    var act = tls.tlsStep(&g_session, "", outbuf[0..]) catch failTls(mode);

    var guard: usize = 0;
    var established = false;
    while (!established) {
        guard += 1;
        if (guard > 100000) failTls(mode);
        switch (act) {
            .send => |bytes| {
                if (prefer_chacha20 and guard == 1) {
                    if (firstSuite(bytes) != 0x1303 or firstGroup(bytes) != 0x001D) {
                        out("alpn=preference-failed\n");
                        os.exit(1);
                    }
                }
                if (!sendAll(fd, bytes)) failTls(mode);
                act = tls.tlsStep(&g_session, "", outbuf[0..]) catch failTls(mode);
            },
            .recv => {
                const n = recvSome(fd, inbuf[0..]);
                if (n <= 0) failTls(mode);
                act = tls.tlsStep(&g_session, inbuf[0..@intCast(usize, n)], outbuf[0..]) catch failTls(mode);
            },
            .wait => {
                const n = recvSome(fd, inbuf[0..]);
                if (n <= 0) failTls(mode);
                act = tls.tlsStep(&g_session, inbuf[0..@intCast(usize, n)], outbuf[0..]) catch failTls(mode);
            },
            .established => established = true,
            .closed => failTls(mode),
            else => failTls(mode),
        }
    }

    const selected = tls.tlsAlpnSelected(&g_session);
    out("alpn=");
    out(alpnName(selected));
    out("\n");

    // Fail closed on the negative-server case: the server offering only `foo`
    // must never be reported as a protocol we offered.
    if (eqBytes(mode, "1.3badalpn")) {
        if (selected == tls.AlpnProtocol.h2 or selected == tls.AlpnProtocol.http11) {
            out("alpn=badalpn-mismatch\n");
            os.exit(1);
        }
    }

    net.close(fd);
    os.exit(0);
}
