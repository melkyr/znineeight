// main.zig — UNDERSANDED GUI entry (WINDOWS_GUI, spec §26).
//
// Thin entry: open the terminal-mode std_gfx window titled UNDERSANDED, run
// the shared skeleton, then close cleanly.

const gfx = @import("std_gfx.zig");
const app = @import("app.zig");

pub fn main(argc: i32, argv: [*][*]u8) void {
    const g = gfx.gfxOpen("UNDERSANDED", 80, 30) catch {
        var msg: []const u8 = "UNDERSANDED: gfxOpen failed\n";
        @stderrWrite(msg.ptr, msg.len);
        gfx.gfxShowError("UNDERSANDED", "gfxOpen failed");
        @exit(@intCast(u8, 1));
        return;
    };

    app.run(g, argc, argv, false);
    gfx.gfxClose(g);
}
