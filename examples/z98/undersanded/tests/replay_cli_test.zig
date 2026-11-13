// replay_cli_test.zig — native driver for the `undtool --replay` line (§28).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/replay_cli_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/replay_cli_test"
//   "$OUT/replay_cli_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const file_mod = @import("std_file");
const undtool = @import("../undtool.zig");

const REPLAY_PATH = "/tmp/m3_replay_cli.rep";
const MISSING_PATH = "/tmp/m3_replay_cli_missing_zzz.rep";

const FIXTURE = "seed=98\ncreature=eel\nzone=Z3\nphase=night\ntool=sonar\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\nA restrain\n";

// Pinned output for FIXTURE through undtool.replayLine.
const GOLDEN = "replay outcome=1 actions=8 rng=1107243468 log=0:3:18:62;0:4:6:94;0:3:10:52;0:4:6:88;0:3:13:39;0:4:6:82;0:9:5:1;0:3:16:28;0:4:6:76;0:9:5:1;0:3:10:23;0:4:6:70;0:9:5:1;0:3:12:16;0:4:6:64;0:9:5:1;0:3:18:3;0:4:6:58;0:9:5:1;0:3:14:-6;0:5:0:0;";

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn tGoldenStable() bool {
    file_mod.writeAll(REPLAY_PATH, FIXTURE) catch return false;

    var a_buf: [8192]u8 = undefined;
    const a = undtool.replayLine(REPLAY_PATH, a_buf[0..]) orelse return false;
    var b_buf: [8192]u8 = undefined;
    const b = undtool.replayLine(REPLAY_PATH, b_buf[0..]) orelse return false;

    if (!eq(a, b)) return false;
    return eq(a, GOLDEN);
}

fn tMissingRejected() bool {
    var buf: [8192]u8 = undefined;
    return undtool.replayLine(MISSING_PATH, buf[0..]) == null;
}

fn tInvalidStreamRejected() bool {
    const bad = "seed=98\ncreature=eel\nzone=Z3\nphase=night\ntool=sonar\nA punch\n";
    file_mod.writeAll(REPLAY_PATH, bad) catch return false;
    var buf: [8192]u8 = undefined;
    return undtool.replayLine(REPLAY_PATH, buf[0..]) == null;
}

pub fn main() void {
    file_mod.remove(REPLAY_PATH) catch {};
    file_mod.remove(MISSING_PATH) catch {};

    report("replay_cli_golden_stable", tGoldenStable());
    report("replay_cli_missing_file_rejected", tMissingRejected());
    report("replay_cli_invalid_stream_rejected", tInvalidStreamRejected());

    file_mod.remove(REPLAY_PATH) catch {};
    file_mod.remove(MISSING_PATH) catch {};

    if (fails != 0) os.exit(1);
    io.write("replay_cli_test PASS\n");
}
