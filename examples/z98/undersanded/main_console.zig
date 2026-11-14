// main_console.zig — UNDERSANDED console entry (WINDOWS_CUI, spec §26).
//
// Thin entry: gfxOpenMemory (no window, headless-safe) + stdout, then the
// playable text fight (std_io; the GUI entry keeps the M1 skeleton).

const gfx = @import("std_gfx.zig");
const os = @import("std_os.zig");
const app = @import("app.zig");
const undtool = @import("undtool.zig");

// Tool routing (§26): any `--` argument goes to the dispatcher BEFORE the
// playable console, so tool paths never read sample.txt or open a fight UI.
fn hasFlag() bool {
    const nargs = os.argc();
    var i: usize = 0;
    while (i < nargs) : (i += 1) {
        const a = os.argv(i);
        if (a.len >= 2 and a[0] == '-' and a[1] == '-') return true;
    }
    return false;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    if (hasFlag()) {
        undtool.run(argc, argv);
        return;
    }

    const g = gfx.gfxOpenMemory(80, 30) catch {
        var msg: []const u8 = "UNDERSANDED: gfxOpenMemory failed\n";
        @stderrWrite(msg.ptr, msg.len);
        @exit(@intCast(u8, 1));
        return;
    };

    app.runConsoleFight(g, argc, argv);
    gfx.gfxClose(g);
}
