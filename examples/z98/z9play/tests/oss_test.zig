// oss_test.zig — best-effort host smoke test for the OSS `/dev/dsp` backend
// (M4 Task 2).
//
// The build host has NO `/dev/dsp` (confirmed), so `audio_oss.open(44100, 2)`
// must fail *cleanly* with `error.OpenFailed` — never crash. This test asserts
// that outcome; if a device IS present it configures, writes a short block,
// drains and closes, and still passes. It also exercises the two argument
// rejections (`ConfigUnsupported` for a non-44100/48000 rate and for a channel
// count other than 1/2), and assembles the blueprint §2.2 `AudioOut` literal
// from the backend's public free functions (the compiler-defect D8 workaround:
// no backend function returns the vtable struct).
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/oss_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const audio = @import("../platform/audio.zig");
const oss = @import("../platform/audio_oss.zig");

fn fail(msg: []const u8) void {
    var p: []const u8 = "oss_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

// Assemble the AudioOut literal from the backend's free functions (the D8
// workaround shape). Never invoked on the placeholder state; its presence forces
// the multi-module vtable emission to compile, which is the defect D8 trigger.
fn vtableShape() void {
    var placeholder: *void = @ptrCast(*void, @intToPtr(*void, 0));
    var ao: audio.AudioOut = audio.AudioOut{
        .open_fn = oss.open,
        .write_fn = oss.write,
        .close_fn = oss.close,
        .drain_fn = oss.drain,
        .state = placeholder,
    };
    _ = &ao;
}

// True iff open(rate, ch) reports exactly ConfigUnsupported.
fn unsupported(rate: u32, ch: u8) bool {
    var c: *void = oss.open(rate, ch) catch |e| {
        return e == error.ConfigUnsupported;
    };
    _ = c;
    return false;
}

// 0 = /dev/dsp absent (OpenFailed, the expected host result); 1 = opened and
// exercised. Calls fail() on any other outcome, e.g. a crash-free OpenFailed
// contract violation.
fn probeDevice() i32 {
    var ctx: *void = oss.open(44100, 2) catch |e| {
        if (e == error.OpenFailed) return 0;
        if (e == error.ConfigUnsupported) {
            fail("open(44100,2) reported ConfigUnsupported");
            return -1;
        }
        fail("open(44100,2) unexpected error");
        return -1;
    };
    var s: [8]i16 = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
    var got: usize = oss.write(ctx, s[0..]) catch {
        fail("write failed on a present device");
        oss.close(ctx);
        return -1;
    };
    if (got != 8) {
        fail("short write on a present device");
        oss.close(ctx);
        return -1;
    }
    oss.drain(ctx) catch {
        fail("drain failed on a present device");
        oss.close(ctx);
        return -1;
    };
    oss.close(ctx);
    return 1;
}

pub fn main() void {
    vtableShape();
    var dev: i32 = probeDevice();

    if (!unsupported(22050, 2)) fail("open(22050,2) did not report ConfigUnsupported");
    if (!unsupported(44100, 3)) fail("open(44100,3) did not report ConfigUnsupported");

    var p: []const u8 = "oss_test: PASS open_dev=";
    std.io.write(p);
    if (dev == 0) {
        var a: []const u8 = "absent";
        std.io.write(a);
    } else {
        var b: []const u8 = "present";
        std.io.write(b);
    }
    var nl: []const u8 = " config_check=ok\n";
    std.io.write(nl);
    std.os.exit(0);
}
