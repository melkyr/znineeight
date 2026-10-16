// fmt_test.zig — deterministic unit harness for z9play fmt.zig (M5 Task 1).
//
// Checks, all under `-fsafe`, with output exiting 0 on success / 1 on the first
// failure: `mmss` and `statusLine` are compared byte-for-byte against fixed
// expected strings, so a single changed byte fails loudly. Cases cover the
// documented example, the zero-padding boundaries, the full/overrun clamp, and
// the `--` duration guard when `dur_ms == 0`. A width-stability block (M5 T1 fix
// round 1) asserts the status line is a constant 47 bytes for every volume digit
// count (the `--` guard is the deliberate 44-byte exception).
//
// Build/run from the repo root (binding M5 Task 1 recipe):
//   mkdir -p /tmp/m5t1
//   timeout 120 /tmp/z9play_seed_v98/zig1_5_clean -fsafe -o /tmp/m5t1 \
//       examples/z98/z9play/tests/fmt_test.zig
//   sh /tmp/m5t1/build_target.sh linux /tmp/m5t1/prog
//   /tmp/m5t1/prog

const std = @import("std");
const fmt = @import("../fmt.zig");

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn fail(name: []const u8, got: []const u8, want: []const u8) void {
    var p: []const u8 = "fmt_test: FAIL ";
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

fn checkMmss(name: []const u8, ms: u64, want: []const u8) void {
    var buf: [fmt.MMSS_MAX]u8 = undefined;
    var got: []const u8 = fmt.mmss(buf[0..], ms);
    if (!eq(got, want)) fail(name, got, want);
}

fn checkStatus(name: []const u8, pos_ms: u64, dur_ms: u64, vol: u8, want: []const u8) void {
    var buf: [fmt.STATUS_LINE_MAX]u8 = undefined;
    var got: []const u8 = fmt.statusLine(buf[0..], pos_ms, dur_ms, vol);
    if (!eq(got, want)) fail(name, got, want);
}

fn failMsg(name: []const u8) void {
    var p: []const u8 = "fmt_test: FAIL ";
    std.io.write(p);
    std.io.write(name);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

// Width stability (M1): assert the rendered status line is exactly `want`
// bytes. The renderer returns a slice bounded by its own writes, so a line
// shorter or longer than the fixed width fails here.
fn checkWidth(name: []const u8, pos_ms: u64, dur_ms: u64, vol: u8, want: usize) void {
    var buf: [fmt.STATUS_LINE_MAX]u8 = undefined;
    var got: []const u8 = fmt.statusLine(buf[0..], pos_ms, dur_ms, vol);
    if (got.len != want) failMsg(name);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    // --- mmss: zero, sub-10 s, sub-10 min, the documented 03:15, > 60 min ---
    checkMmss("mmss-zero", 0, "00:00");
    checkMmss("mmss-sec-pad", 9000, "00:09");
    checkMmss("mmss-min-pad", 42000, "00:42");
    checkMmss("mmss-minute", 60000, "01:00");
    checkMmss("mmss-doc", 195000, "03:15");
    checkMmss("mmss-nines", 599000, "09:59");
    checkMmss("mmss-over60", 3661000, "61:01");
    checkMmss("mmss-trunc", 1999, "00:01");

    // --- statusLine: documented layout, floor fill, full clamp, guard ---
    // The plan example's bar fill is illustrative (42/195 is 21.5%, four of
    // twenty cells). The volume field is a fixed 3 chars, right-aligned, so
    // these lines are constant width (47) despite 1/2/3-digit volume.
    checkStatus("status-doc", 42000, 195000, 80,
        "00:42 / 03:15  vol  80%  [####----------------]");
    // Exact brief bar bytes at the 8/20 mark (78 s of 195 s).
    checkStatus("status-eighth", 78000, 195000, 80,
        "01:18 / 03:15  vol  80%  [########------------]");
    // Start: empty bar; three-digit volume.
    checkStatus("status-start", 0, 195000, 100,
        "00:00 / 03:15  vol 100%  [--------------------]");
    // End: full bar (position == duration).
    checkStatus("status-full", 195000, 195000, 50,
        "03:15 / 03:15  vol  50%  [####################]");
    // Overrun clamps to the full bar (position past duration).
    checkStatus("status-overrun", 999000, 195000, 5,
        "16:39 / 03:15  vol   5%  [####################]");
    // Duration guard: `--` and an empty bar; no div-by-zero.
    checkStatus("status-guard", 42000, 0, 80,
        "00:42 / --  vol  80%  [--------------------]");
    // Zero volume.
    checkStatus("status-vol0", 0, 1000, 0,
        "00:00 / 00:01  vol   0%  [--------------------]");

    // --- width stability (M1): fixed 3-char volume field -> constant width ---
    // Every stable-duration line is 47 bytes for any volume digit count and any
    // position; the `--` guard is the one deliberate exception (its duration
    // field is 2 chars, not 5) and is pinned to exactly 3 bytes shorter.
    checkWidth("width-vol0", 42000, 195000, 0, 47);
    checkWidth("width-vol5", 42000, 195000, 5, 47);
    checkWidth("width-vol9", 42000, 195000, 9, 47);
    checkWidth("width-vol10", 42000, 195000, 10, 47);
    checkWidth("width-vol80", 42000, 195000, 80, 47);
    checkWidth("width-vol99", 42000, 195000, 99, 47);
    checkWidth("width-vol100", 42000, 195000, 100, 47);
    checkWidth("width-vol255", 42000, 195000, 255, 47);
    checkWidth("width-pos-start", 0, 195000, 100, 47);
    checkWidth("width-pos-end", 195000, 195000, 100, 47);
    checkWidth("width-guard", 42000, 0, 80, 44);

    var ok: []const u8 = "fmt_test: PASS mmss=ok status=exact guard=ok\n";
    std.io.write(ok);
    std.os.exit(0);
}
