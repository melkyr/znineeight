// stats_test.zig — deterministic snapshot harness for stats.statsRender.
//
// No wall clock, no randomness: five synthetic `tracker.Stats` values are
// rendered and each produced line is compared byte-for-byte against a fixed
// expected string. This pins the exact display format (percent, 40-char bar,
// MB pair, KB/s from the 5-sample window, peers, ETA) so later changes to the
// renderer that alter a single byte fail loudly.
//
// Build (binding recipe), entry is this file:
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -fsafe -o out testdata/stats_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog
//
// Lives under testdata/ so the example entry stays main.zig (corpus rule).

const std = @import("std");
const stats = @import("../stats.zig");
const tracker = @import("../tracker.zig");

fn eqSlice(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn fail(name: []const u8, got: []const u8, want: []const u8) void {
    var p: []const u8 = "stats_test: FAIL ";
    std.io.write(p);
    std.io.write(name);
    var g: []const u8 = "\n  got : ";
    std.io.write(g);
    std.io.write(got);
    var w: []const u8 = "\n  want: ";
    std.io.write(w);
    std.io.write(want);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn check(name: []const u8, s: *tracker.Stats, want: []const u8) void {
    var buf: [stats.STATS_LINE_MAX]u8 = undefined;
    var got: []const u8 = stats.statsRender(s, buf[0..]);
    if (!eqSlice(got, want)) fail(name, got, want);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    var w5: [5]u32 = [5]u32{ 348160, 348160, 348160, 348160, 348160 };
    var w1m: [5]u32 = [5]u32{ 1048576, 1048576, 1048576, 1048576, 1048576 };
    var w100k: [5]u32 = [5]u32{ 102400, 102400, 102400, 102400, 102400 };
    var w0: [5]u32 = [5]u32{ 0, 0, 0, 0, 0 };
    var wu: [5]u32 = [5]u32{ 0, 0, 0, 0, 0 };

    // Case 1: partial download, mid-run rate, minute ETA.
    var s1 = tracker.Stats{
        .downloaded = 1048576,
        .uploaded = 0,
        .left = 25165824,
        .peer_count = 4,
        .down_rate = 348160,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = w5,
        .window_up = wu,
        .window_idx = 0,
    };
    var e1: []const u8 = "4.0% [#---------------------------------------] 1.00MB/25.00MB 340KB/s peers=4 eta=1m12s";
    check("case1", &s1, e1);

    // Case 2: complete, zero rate -> guarded eta placeholder.
    var s2 = tracker.Stats{
        .downloaded = 26214400,
        .uploaded = 0,
        .left = 0,
        .peer_count = 1,
        .down_rate = 0,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = w0,
        .window_up = wu,
        .window_idx = 0,
    };
    var e2: []const u8 = "100.0% [########################################] 25.00MB/25.00MB 0KB/s peers=1 eta=--";
    check("case2", &s2, e2);

    // Case 3: empty at start, 100 s ETA (1m40s).
    var s3 = tracker.Stats{
        .downloaded = 0,
        .uploaded = 0,
        .left = 104857600,
        .peer_count = 2,
        .down_rate = 0,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = w1m,
        .window_up = wu,
        .window_idx = 3,
    };
    var e3: []const u8 = "0.0% [----------------------------------------] 0.00MB/100.00MB 1024KB/s peers=2 eta=1m40s";
    check("case3", &s3, e3);

    // Case 4: sub-minute ETA (50 s).
    var s4 = tracker.Stats{
        .downloaded = 0,
        .uploaded = 0,
        .left = 52428800,
        .peer_count = 3,
        .down_rate = 0,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = w1m,
        .window_up = wu,
        .window_idx = 0,
    };
    var e4: []const u8 = "0.0% [----------------------------------------] 0.00MB/50.00MB 1024KB/s peers=3 eta=50s";
    check("case4", &s4, e4);

    // Case 5: hours ETA (2h50m40s), 1000 MB total.
    var s5 = tracker.Stats{
        .downloaded = 0,
        .uploaded = 0,
        .left = 1048576000,
        .peer_count = 5,
        .down_rate = 0,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = w100k,
        .window_up = wu,
        .window_idx = 0,
    };
    var e5: []const u8 = "0.0% [----------------------------------------] 0.00MB/1000.00MB 100KB/s peers=5 eta=2h50m40s";
    check("case5", &s5, e5);

    // Case 6: heterogeneous rolling window (mean, not constant) + non-MB bytes.
    var s6 = tracker.Stats{
        .downloaded = 1500000,
        .uploaded = 0,
        .left = 2000000,
        .peer_count = 4,
        .down_rate = 0,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = [5]u32{ 1024, 2048, 3072, 4096, 5120 },
        .window_up = wu,
        .window_idx = 0,
    };
    var e6: []const u8 = "42.8% [#################-----------------------] 1.43MB/3.33MB 3KB/s peers=4 eta=10m51s";
    check("case6", &s6, e6);

    // Case 7: heterogeneous window where a wrong divisor (N != 5) changes the
    // rendered rate (mean 1843 -> 1KB/s; /4 -> 2304 -> 2KB/s); non-MB bytes.
    var s7 = tracker.Stats{
        .downloaded = 500000,
        .uploaded = 0,
        .left = 500000,
        .peer_count = 2,
        .down_rate = 0,
        .up_rate = 0,
        .started_ms = 0,
        .window_down = [5]u32{ 0, 2048, 0, 2048, 5120 },
        .window_up = wu,
        .window_idx = 0,
    };
    var e7: []const u8 = "50.0% [####################--------------------] 0.47MB/0.95MB 1KB/s peers=2 eta=4m31s";
    check("case7", &s7, e7);

    var p: []const u8 = "stats_test: PASS 7 snapshots\n";
    std.io.write(p);
    std.os.exit(0);
}
