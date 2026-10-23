// stdlib_wireguard_cross_xmod — std_wireguard (Phase1 M6) crosscheck driver.
//
// Default mode (fixture gate): deterministic `wireguard cross ok\n`.
// `--crosscheck` reads `seed wall_unix_ns` per line (decimal u64) and prints
// one lowercase-hex WireGuard handshake initiation (148 bytes) per input. The
// C89 reference at scripts/stdlib/ref/std_wireguard/ref.c implements the same
// protocol with the same RFC 7748 static keypairs.
const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const parse = @import("std_parse.zig");
const rand = @import("std_rand.zig");
const wg = @import("std_wireguard.zig");

const PRIV_I_HEX = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a";
const PUB_R_HEX = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f";

var g_peer: wg.WgPeer = undefined;
var g_peers: [1]wg.WgPeer = undefined;

fn sliceEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn isCrosscheck() bool {
    var i: usize = 1;
    while (i < os.argc()) : (i += 1) {
        if (sliceEq(os.argv(i), "--crosscheck")) return true;
    }
    return false;
}

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn nextToken(line: []const u8, pos: *usize) ?[]const u8 {
    var i: usize = pos.*;
    while (i < line.len and isWs(line[i])) : (i += 1) {}
    if (i >= line.len) {
        pos.* = i;
        return null;
    }
    var j: usize = i;
    while (j < line.len and !isWs(line[j])) : (j += 1) {}
    pos.* = j;
    return line[i..j];
}

fn hexNib(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return c - 'A' + 10;
}

fn unhex(s: []const u8, out: []u8) void {
    var i: usize = 0;
    while (i * 2 + 1 < s.len) : (i += 1) {
        out[i] = (hexNib(s[i * 2]) << 4) | hexNib(s[i * 2 + 1]);
    }
}

fn fill32(p: *[32]u8, v: u8) void {
    var i: usize = 0;
    while (i < 32) : (i += 1) p[i] = v;
}

fn resetPeer() void {
    fill32(&g_peer.static_priv, 0);
    fill32(&g_peer.remote_static_pub, 0);
    fill32(&g_peer.preshared_key, 0);
    g_peer.endpoint_ip = 0;
    g_peer.endpoint_port = 0;
    g_peer.allowed_ip_count = 0;
    fill32(&g_peer.public_key_dh, 0);
    fill32(&g_peer.label_mac1_key, 0);
    fill32(&g_peer.label_cookie_key, 0);
    g_peer.hs_valid = false;
    g_peer.hs_initiator = false;
    g_peer.local_index = 0;
    g_peer.remote_index = 0;
    fill32(&g_peer.ephemeral_priv, 0);
    fill32(&g_peer.remote_ephemeral, 0);
    fill32(&g_peer.hash, 0);
    fill32(&g_peer.chaining_key, 0);
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        g_peer.last_mac1[i] = 0;
        g_peer.cookie[i] = 0;
    }
    g_peer.has_mac1 = false;
    g_peer.cookie_valid = false;
    fill32(&g_peer.tx_key, 0);
    fill32(&g_peer.rx_key, 0);
    g_peer.session_valid = false;
    g_peer.last_handshake_sent_ms = 0;
    g_peer.last_handshake_received_ms = 0;
    g_peer.session_created_ms = 0;
    g_peer.handshake_attempts = 0;
}

fn hexChar(v: u8) u8 {
    if (v < 10) return @intCast(u8, @intCast(u32, '0') + @intCast(u32, v));
    return @intCast(u8, @intCast(u32, 'a') + @intCast(u32, v - 10));
}

fn writeHex(p: []const u8) void {
    var i: usize = 0;
    while (i < p.len) : (i += 1) {
        std.io.writeByte(hexChar(p[i] >> 4));
        std.io.writeByte(hexChar(p[i] & 15));
    }
    std.io.writeByte('\n');
}

fn crossMain() void {
    var priv_i: [32]u8 = undefined;
    var pub_r: [32]u8 = undefined;
    var dev: wg.WgDevice = undefined;
    var out: [wg.WG_INITIATION_LEN]u8 = undefined;
    var linebuf: [512]u8 = undefined;

    resetPeer();
    unhex(PRIV_I_HEX, priv_i[0..]);
    unhex(PUB_R_HEX, pub_r[0..]);
    fill32(&g_peer.static_priv, 0);
    fill32(&g_peer.remote_static_pub, 0);
    unhex(PRIV_I_HEX, g_peer.static_priv[0..]);
    unhex(PUB_R_HEX, g_peer.remote_static_pub[0..]);

    while (true) {
        const line_opt = stdin.readLine(linebuf[0..]) catch @panic("crosscheck read");
        if (line_opt) |line| {
            var pos: usize = 0;
            const seed_s = nextToken(line[0..], &pos) orelse @panic("crosscheck seed");
            const wall_s = nextToken(line[0..], &pos) orelse @panic("crosscheck wall");
            const seed = parse.parseUint64(seed_s) orelse @panic("crosscheck seed");
            const wall = parse.parseUint64(wall_s) orelse @panic("crosscheck wall");

            dev.peers = g_peers[0..];
            wg.wgInit(&dev, &priv_i);
            dev.rng = rand.xoshiroInit(seed);
            wg.wgAddPeer(&dev, &g_peer) catch @panic("crosscheck add peer");
            _ = wg.wgCreateInitiation(&dev, &dev.peers[0], wall, out[0..]) catch @panic("crosscheck initiation");
            writeHex(out[0..]);
        } else {
            break;
        }
    }
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (isCrosscheck()) {
        crossMain();
    } else {
        std.io.write("wireguard cross ok\n");
    }
}
