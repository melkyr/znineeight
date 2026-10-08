// ratelimit_test.zig — deterministic unit harness for ratelimit.TokenBucket.
//
// Fixed synthetic clock (no wall time, no randomness): a 10,000 B/s bucket is
// driven from t=0 to t=60,000 ms, draining greedily each millisecond. It must
// admit 600,000 bytes +/- 10% and never exceed the analytic ceiling
// `capacity + floor(rate * t / 1000)` at any instant (no over-admit).
//
// Build (binding recipe), entry is this file:
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -ffast -o out testdata/ratelimit_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog
//
// This lives under testdata/ so the example entry stays main.zig (corpus rule:
// examples/z98/z9torr/main.zig exists, so other .zig files are ignored).

const std = @import("std");
const rl = @import("../ratelimit.zig");

fn writeU64(v_in: u64) void {
    var v: u64 = v_in;
    if (v == 0) {
        var z: []const u8 = "0";
        std.io.write(z);
        return;
    }
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    while (v > 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        v = v / 10;
        n += 1;
    }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = tmp[n - 1 - i];
    }
    std.io.write(buf[0..n]);
}

fn fail(msg: []const u8) void {
    var p: []const u8 = "ratelimit_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    // --- Test 1: 10 KB/s over 60 s, greedy drain, no over-admit -------------
    var b = rl.bucketInit(10000);
    var admitted: u64 = 0;
    var t: u32 = 0;
    while (t <= 60000) : (t += 1) {
        rl.refill(&b, t);
        while (rl.take(&b, 1)) {
            admitted += 1;
        }
        var ceiling: u64 = @intCast(u64, b.capacity) +
            (@intCast(u64, b.rate) * @intCast(u64, t)) / @intCast(u64, 1000);
        if (admitted > ceiling) fail("over-admit at t < 60s");
    }
    if (admitted < 540000) fail("admitted < 600000 - 10%");
    if (admitted > 660000) fail("admitted > 600000 + 10%");

    // --- Test 2: take blocks when empty; succeeds after refill -------------
    var c = rl.bucketInit(1000);
    while (rl.take(&c, 1)) {}
    if (rl.take(&c, 1)) fail("take succeeded on an empty bucket");
    rl.refill(&c, 0);
    rl.refill(&c, 1000);
    if (!rl.take(&c, 1000)) fail("take(1000) failed after 1 s refill");
    if (rl.take(&c, 1)) fail("bucket admitted more than one second of tokens");

    // --- Test 3: refill caps at capacity; elapsed wraps --------------------
    var d = rl.bucketInit(500);
    rl.refill(&d, 10000);
    if (d.tokens != 500) fail("refill did not cap at capacity");
    var e = rl.bucketInit(1000);
    e.last_refill_ms = 4294967295;
    rl.refill(&e, 0);
    if (e.tokens != 1000) fail("wrapped elapsed produced wrong token count");
    if (e.last_refill_ms != 0) fail("wrapped refill did not advance last_refill_ms");

    var p: []const u8 = "ratelimit_test: PASS admitted=";
    std.io.write(p);
    writeU64(admitted);
    var q: []const u8 = " (want 540000..660000)\n";
    std.io.write(q);
    std.os.exit(0);
}
