// mock_blackhole_peer.zig — z9torr M4.1 Task 4 test double: an unresponsive
// (black-hole) peer.
//
// Separate Z98 binary (not linked into the client). Listens on a fixed port and
// accepts every connection but NEVER reads or writes a byte, and never closes
// it. A client that dials it completes the TCP connect immediately, then its
// MSE/PE probe (and plaintext fallback) stalls until its own deadline. This is
// the "dead/unresponsive peer" in tests/tier_stall.sh: with the coroutine-aware
// connect + MSE probe, other peers keep making progress while this one waits.
//
// Flags: --port <n>
//
// Build (binding recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9_m41_seed/zig1_5_clean -ffast -o out tools/mock_blackhole_peer.zig
//   sh out/build_target.sh linux out/prog
//
// Z98 rules apply: free functions only, no generics, strict @intCast, switch
// needs else, string literals via `var s: []const u8 = "...";`.

const std = @import("std");
const std_net = @import("std_net");

const DEFAULT_PORT: u32 = 6991;
// Held-open accepted sockets (never closed, never read/written). A tiny list is
// enough: the client dials at most twice (MSE probe + plaintext fallback).
const MAX_HELD: usize = 64;
var g_held: [MAX_HELD]i32 = undefined;

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

pub fn main(argc: i32, argv: [*][*]u8) void {
    var port: u32 = DEFAULT_PORT;

    const n: usize = @intCast(usize, argc);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--port")) {
            i += 1;
            if (i >= n) { out("mock_blackhole_peer: --port needs a value\n"); std.os.exit(1); return; }
            if (parseU32(argAt(argv, i))) |pv| {
                port = pv;
            } else {
                out("mock_blackhole_peer: bad --port\n");
                std.os.exit(1);
                return;
            }
        } else if (eq(tok, "--help") or eq(tok, "-h")) {
            var u: []const u8 = "usage: mock_blackhole_peer [--port N]\n";
            out(u);
            std.os.exit(0);
            return;
        } else {
            // ignore unknown tokens
        }
    }

    if (port > 65535) {
        out("mock_blackhole_peer: port out of range\n");
        std.os.exit(1);
        return;
    }

    if (std_net.init() != 0) {
        out("mock_blackhole_peer: socket init failed\n");
        return;
    }
    const srv = std_net.createTcpServer(@intCast(u16, port));
    if (srv < 0) {
        out("mock_blackhole_peer: createTcpServer failed\n");
        return;
    }
    if (std_net.bindListen(srv, 8) < 0) {
        out("mock_blackhole_peer: listen failed\n");
        std_net.close(srv);
        return;
    }

    var l1: []const u8 = "mock_blackhole_peer listening\n";
    out(l1);

    var held: usize = 0;
    while (true) {
        const c = std_net.accept(srv);
        if (c < 0) continue;
        // Hold the connection open and stay silent: the client's handshake waits
        // until its own deadline instead of getting an immediate EOF/refusal.
        if (held < MAX_HELD) {
            g_held[held] = c;
            held += 1;
        }
    }
}
