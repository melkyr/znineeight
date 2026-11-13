// main_console.zig — UNDERSANDED console entry (WINDOWS_CUI, spec §26).
//
// Thin entry: gfxOpenMemory (no window, headless-safe) + stdout, then the
// playable text fight (std_io; the GUI entry keeps the M1 skeleton).

const gfx = @import("std_gfx.zig");
const app = @import("app.zig");

pub fn main(argc: i32, argv: [*][*]u8) void {
    const g = gfx.gfxOpenMemory(80, 30) catch {
        var msg: []const u8 = "UNDERSANDED: gfxOpenMemory failed\n";
        @stderrWrite(msg.ptr, msg.len);
        @exit(@intCast(u8, 1));
        return;
    };

    app.runConsoleFight(g, argc, argv);
    gfx.gfxClose(g);
}
