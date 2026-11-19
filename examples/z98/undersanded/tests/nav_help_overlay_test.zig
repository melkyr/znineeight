// nav_help_overlay_test.zig — regression: an open help overlay owns the next
// key at the dock, so Esc/q dismiss it instead of saving/quitting.
//
// Run through nav_help_overlay.sh so stdin is the key stream and cwd is a
// scratch directory holding a sentinel save0.dat.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const file_mod = @import("std_file");
const def = @import("../def.zig");
const game = @import("../game.zig");
const nav = @import("../nav.zig");

const SAVE = "save0.dat";
const SENTINEL = "nav-help-sentinel\n";

var fails: usize = 0;
var file_buf: [4096]u8 = undefined;

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

pub fn main() void {
    // Sentinel save: any dock save would rewrite it (and create save.bak).
    file_mod.writeAll(SAVE, SENTINEL) catch {
        io.write("FAIL - sentinel write\n");
        os.exit(1);
        return;
    };

    var g: def.GameState = undefined;
    game.newGame(&g);
    g.screen = nav.NAV_DOCK;
    g.world.money = 777;

    // Key stream (from nav_help_overlay.sh): '?' Esc '?' q y.
    // With the overlay precedence bug, Esc saves and q/y quits (saving again);
    // with the fix both sequences just dismiss the help page.
    nav.navRun(&g);

    var arena = arena_mod.init(file_buf[0..]);
    const raw = file_mod.readAll(&arena, SAVE) catch {
        io.write("FAIL - sentinel missing after navRun\n");
        os.exit(1);
        return;
    };

    report("help_overlay_esc_does_not_save", eq(raw, SENTINEL));
    report("help_overlay_q_does_not_prompt_or_save", !file_mod.exists("save.bak"));
    report("help_overlay_returns_to_dock", g.screen == nav.NAV_DOCK);
    report("help_overlay_no_game_mutation", g.world.money == 777);

    if (fails != 0) {
        io.write("nav_help_overlay_test FAIL\n");
        os.exit(1);
    }
    io.write("nav_help_overlay_test PASS\n");
}
