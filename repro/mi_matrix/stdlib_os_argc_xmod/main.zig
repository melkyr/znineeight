// stdlib_os_argc_xmod — STDLIB std_os (L1) argc/argv round-trip GREEN fixture.
//
// Operator ruling 2026-09-17: std_os.initArgs(argc, argv) is called by the user
// from their main; argc()/argv(i) read the saved values. The emitted C main
// wrapper passes argc/argv to the Z98 main only when it declares parameters
// (c89_emit.zig emitMainWrapper), so this fixture's main takes (argc, argv)
// and forwards them to initArgs. No compiler capture hook is involved.
//
// Contract (blueprint §3 L1): argv slices alias the pointers passed to
// initArgs (no copy); argc()/argv(i) are pure reads.
//
// GREEN (contract): deterministic byte-exact stdout `os argc ok\n` (RUNRC=0).
// A mismatch increments g_fail and calls @panic; the final line is
// `os argc ok` only when g_fail == 0.
const std = @import("std");
const os = @import("std_os.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);

    // argc round-trip: the wrapper forwards the C argc unchanged.
    ck(os.argc() == @intCast(usize, argc), "argc round-trip");
    ck(os.argc() >= 1, "argc >= 1");

    // argv(0) is the program path: a non-empty NUL-terminated C string. The
    // returned slice excludes the NUL, so its last byte is a real character.
    var a0 = os.argv(0);
    ck(a0.len > 0, "argv(0) non-empty");
    ck(a0[a0.len - 1] != 0, "argv(0) slice excludes NUL");

    // Aliasing contract: argv(i) slices the exact pointer handed to initArgs.
    // (Pointer identity, not contents: the path itself is run-dependent and is
    // deliberately never printed — R6 determinism.)
    var i: usize = 0;
    while (i < os.argc()) : (i += 1) {
        ck(os.argv(i).ptr == argv[i], "argv(i) aliases initArgs pointer");
    }

    // std.zig re-export smoke check.
    ck(std.os.argc() == os.argc(), "std.os re-export");

    if (g_fail == 0) {
        std.io.write("os argc ok\n");
    } else {
        std.io.write("os argc FAIL\n");
    }
}
