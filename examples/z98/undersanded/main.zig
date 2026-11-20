// main.zig — UNDERSANDED GUI entry (WINDOWS_GUI, spec §26).
//
// Thin entry: open the one std_gfx window titled UNDERSANDED, run the shared
// playable loop, then close cleanly.

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

    // 80x30 cells at 8x16 need a 640x480 client. The window is created with
    // outer dimensions, so correct the client before any frame is drawn; this
    // also keeps cell row 29 visible when px attach fails.
    _ = gfx.gfxSetClientSize(g, 640, 480);

    app.run(g, argc, argv, false);
    gfx.gfxClose(g);
}
