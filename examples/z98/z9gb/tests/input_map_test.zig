// input_map_test.zig — configurable keyboard map, ini round-trip, capture.
//
// Run as a normal executable under both -ffast and -fsafe. Every check is
// counted; the process exits 0 only when all checks pass.

const std = @import("std");
const filemod = @import("std_file");
const strmod = @import("std_str");
const config = @import("../input_config.zig");
const backend = @import("../platform/backend.zig");

const P1: []const u8 = "/tmp/z9gb_input_map_test_a.ini";
const P2: []const u8 = "/tmp/z9gb_input_map_test_b.ini";

var g_pass: u32 = 0;
var g_fail: u32 = 0;

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

fn checkU8(label: []const u8, got: u8, want: u8) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got));
    std.io.write(" want=");
    printU(@intCast(usize, want));
    std.io.write("\n");
}

fn checkBool(label: []const u8, got: bool, want: bool) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write("\n");
}

fn checkContains(label: []const u8, hay: []const u8, needle: []const u8) void {
    if (strmod.indexOf(hay, needle) != null) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write("\n");
}

fn zeroKeys(keys: []u8) void {
    var i: usize = 0;
    while (i < keys.len) : (i += 1) keys[i] = 0;
}

fn checkAllRaws(label: []const u8, cfg: *const config.InputConfig, kind: u8) void {
    checkU8(label, cfg.right.raw, 0xCD);
    checkU8(label, cfg.left.raw, 0xCB);
    checkU8(label, cfg.up.raw, 0xC8);
    checkU8(label, cfg.down.raw, 0xD0);
    checkU8(label, cfg.a.raw, 0x2C);
    checkU8(label, cfg.b.raw, 0x2D);
    checkU8(label, cfg.select.raw, 0x0E);
    checkU8(label, cfg.start.raw, 0x1C);
    checkU8(label, cfg.quit.raw, 0x01);
    checkU8(label, cfg.right.kind, kind);
    checkU8(label, cfg.quit.kind, kind);
}

fn writeText(path: []const u8, text: []const u8) bool {
    filemod.remove(path) catch {};
    filemod.writeAll(path, text) catch return false;
    return true;
}

fn testDefaults() void {
    var cfg = config.configDefaults(config.KIND_DINPUT8);
    checkAllRaws("default table", &cfg, config.KIND_DINPUT8);

    filemod.remove(P1) catch {};
    var absent_cfg = config.configDefaults(config.KIND_FALLBACK);
    const st = config.configLoad(P1, config.KIND_FALLBACK, &absent_cfg);
    checkBool("absent ini status", st == config.LoadStatus.absent, true);
    checkAllRaws("absent ini keeps defaults", &absent_cfg, config.KIND_FALLBACK);
}

fn testRoundTrip() void {
    var cfg = config.configDefaults(config.KIND_DINPUT8);
    cfg.a.raw = 0x39;
    cfg.left.raw = 0x4B;
    checkBool("save round-trip file", config.configSave(P1, &cfg), true);

    var got = config.configDefaults(config.KIND_FALLBACK);
    const st = config.configLoad(P1, config.KIND_DINPUT8, &got);
    checkBool("round-trip loaded", st == config.LoadStatus.loaded, true);
    checkU8("round-trip a raw", got.a.raw, 0x39);
    checkU8("round-trip left raw", got.left.raw, 0x4B);
    checkU8("round-trip right raw", got.right.raw, 0xCD);
    checkU8("round-trip kind", got.a.kind, config.KIND_DINPUT8);

    var buf: [2048]u8 = undefined;
    const n = config.configSerialize(buf[0..], &cfg);
    const text: []const u8 = buf[0..n];
    checkContains("diag custom fixed=none", text, "; a raw=0x39 fixed=none\n");
    checkContains("diag legacy fixed=left", text, "; left raw=0x4B fixed=none\n");
    checkContains("diag default fixed=right", text, "; right raw=0xCD fixed=right\n");
}

fn testDuplicate() void {
    const dup = "[keys]\nbackend=dinput8\nright=0x2C\nleft=0xCB\nup=0xC8\ndown=0xD0\na=0x2C\nb=0x2D\nselect=0x0E\nstart=0x1C\nquit=0x01\n";
    checkBool("duplicate ini written", writeText(P1, dup), true);
    var cfg = config.configDefaults(config.KIND_DINPUT8);
    cfg.a.raw = 0x7A;
    const st = config.configLoad(P1, config.KIND_DINPUT8, &cfg);
    checkBool("duplicate ini status", st == config.LoadStatus.duplicate, true);
    checkU8("duplicate ini falls back to defaults", cfg.a.raw, 0x2C);

    var def = config.configDefaults(config.KIND_DINPUT8);
    checkBool("capture duplicate detected", config.isDuplicate(&def, 0, 0x2C), true);
    checkBool("capture unique accepted", config.isDuplicate(&def, 0, 0x39), false);
}

fn testBackendMismatch() void {
    const fb = "[keys]\nbackend=fallback\nright=0xCD\nleft=0xCB\nup=0xC8\ndown=0xD0\na=0x2C\nb=0x2D\nselect=0x0E\nstart=0x1C\nquit=0x01\n";
    checkBool("fallback ini written", writeText(P1, fb), true);
    var cfg = config.configDefaults(config.KIND_DINPUT8);
    cfg.a.raw = 0x7A;
    const st1 = config.configLoad(P1, config.KIND_DINPUT8, &cfg);
    checkBool("fallback under dinput8 status", st1 == config.LoadStatus.backend_mismatch, true);
    checkU8("mismatch falls back to defaults", cfg.a.raw, 0x2C);
    checkBool("mismatch yields warning", config.loadWarning(st1).len != 0, true);

    const d8 = "[keys]\nbackend=dinput8\nright=0xCD\nleft=0xCB\nup=0xC8\ndown=0xD0\na=0x2C\nb=0x2D\nselect=0x0E\nstart=0x1C\nquit=0x01\n";
    checkBool("dinput8 ini written", writeText(P2, d8), true);
    var cfg2 = config.configDefaults(config.KIND_FALLBACK);
    const st2 = config.configLoad(P2, config.KIND_FALLBACK, &cfg2);
    checkBool("dinput8 under fallback status", st2 == config.LoadStatus.backend_mismatch, true);
    checkU8("reverse mismatch falls back", cfg2.a.raw, 0x2C);
}

fn testApply() void {
    var cfg = config.configDefaults(config.KIND_DINPUT8);
    var idx: u8 = 0;
    while (idx < 9) : (idx += 1) {
        var raw: [256]u8 = undefined;
        zeroKeys(raw[0..]);
        const b = config.bindingAt(&cfg, idx);
        raw[@intCast(usize, b.raw)] = 0x80;
        var st = backend.InputState{ .buttons = 0, .quit = false };
        config.configApply(raw[0..], &cfg, &st);
        if (idx == 8) {
            checkBool("apply quit", st.quit, true);
            checkU8("apply quit no button", st.buttons, 0);
        } else {
            checkU8("apply buttons", st.buttons, @intCast(u8, @as(u8, 1) << idx));
            checkBool("apply not quit", st.quit, false);
        }
    }

    var raw2: [256]u8 = undefined;
    zeroKeys(raw2[0..]);
    var st2 = backend.InputState{ .buttons = 0xFF, .quit = true };
    config.configApply(raw2[0..], &cfg, &st2);
    checkU8("apply clears idle buttons", st2.buttons, 0);
    checkBool("apply clears idle quit", st2.quit, false);
}

fn testCapture() void {
    var cap: config.CaptureState = undefined;
    var keys: [256]u8 = undefined;
    zeroKeys(keys[0..]);
    keys[0x2C] = 0x80;
    config.captureBegin(&cap, keys[0..]);
    checkBool("held key ignored at prompt start", config.captureStep(&cap, keys[0..]) < 0, true);

    zeroKeys(keys[0..]);
    checkBool("release still no capture", config.captureStep(&cap, keys[0..]) < 0, true);
    keys[0x2C] = 0x80;
    checkBool("capture after release", config.captureStep(&cap, keys[0..]) == 0x2C, true);
    checkBool("capture latches once", config.captureStep(&cap, keys[0..]) < 0, true);

    const raws = [9]u8{ 0xCD, 0xCB, 0xC8, 0xD0, 0x2C, 0x2D, 0x0E, 0x1C, 0x01 };
    var i: usize = 0;
    while (i < 9) : (i += 1) {
        zeroKeys(keys[0..]);
        config.captureBegin(&cap, keys[0..]);
        keys[@intCast(usize, raws[i])] = 0x80;
        checkBool("one capture per prompt", config.captureStep(&cap, keys[0..]) == @intCast(i32, raws[i]), true);
    }
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;
    testDefaults();
    testRoundTrip();
    testDuplicate();
    testBackendMismatch();
    testApply();
    testCapture();
    filemod.remove(P1) catch {};
    filemod.remove(P2) catch {};

    if (g_fail == 0) {
        std.io.write("input map ok ");
        printU(@intCast(usize, g_pass));
        std.io.write(" checks\n");
        std.os.exit(0);
    }
    std.io.write("FAIL ");
    printU(@intCast(usize, g_fail));
    std.io.write(" failed, ");
    printU(@intCast(usize, g_pass));
    std.io.write(" passed\n");
    std.os.exit(1);
}
