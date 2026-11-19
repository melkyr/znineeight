// boot_walk.zig — native scripted-key driver for the real nav.boot path.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/boot_walk.zig
//   sh "$OUT/build_target.sh" linux "$OUT/boot_walk"
//   printf 'c' | "$OUT/boot_walk" <save-dir> [<content-dir>]
//
// Keys come from stdin through nav.boot's own input path (input.readKey /
// readKeyRaw), exactly like app.zig's console boot. argv[1] is the writable
// save dir; argv[2] is an optional content dir containing data.z98. The final
// line reports the boot result and state so the M7 tier can assert routing.

const io = @import("std_io");
const os = @import("std_os");
const arena_mod = @import("std_arena");
const def = @import("../def.zig");
const data = @import("../data.zig");
const content_boot = @import("../content_boot.zig");
const game = @import("../game.zig");
const nav = @import("../nav.zig");
const paths = @import("../paths.zig");
const save_ux = @import("../save_ux.zig");

var g_content_arena_buf: [256 * 1024]u8 = undefined;

fn copyInto(dst: []u8, src: []const u8) []const u8 {
    var i: usize = 0;
    while (i < src.len and i < dst.len) : (i += 1) dst[i] = src[i];
    return dst[0..i];
}

fn intFlag(v: bool) i32 {
    if (v) return 1;
    return 0;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);

    var dir_buf: [4096]u8 = undefined;
    var dir: []const u8 = undefined;
    if (os.argc() > 1) {
        const a = os.argv(1);
        if (a.len > dir_buf.len) {
            io.write("boot_walk: save dir path too long\n");
            os.exit(2);
            return;
        }
        dir = copyInto(dir_buf[0..], a);
    } else {
        dir = paths.dataDirOrFallback(dir_buf[0..]);
    }

    var content_buf: [4096]u8 = undefined;
    var content_dir: []const u8 = dir;
    if (os.argc() > 2) {
        const a = os.argv(2);
        if (a.len > content_buf.len) {
            io.write("boot_walk: content dir path too long\n");
            os.exit(2);
            return;
        }
        content_dir = copyInto(content_buf[0..], a);
    }

    var arena = arena_mod.init(g_content_arena_buf[0..]);
    _ = content_boot.loadFromDir(&arena, &data.g_tables, content_dir);

    var s: def.GameState = undefined;
    game.newGame(&s);
    const reached = nav.boot(&s, dir);

    io.write("\nboot ret=");
    io.printInt(intFlag(reached));
    io.write(" screen=");
    io.printInt(s.screen);
    io.write(" money=");
    io.printInt(s.world.money);
    io.write(" field_record_written=");
    io.printInt(s.world.field_record_written);
    io.write(" boss_variants_seen=");
    io.printInt(@intCast(i32, s.world.boss_variants_seen));
    io.write(" expedition_active=");
    io.printInt(s.exp.active);
    io.write(" save0=");
    io.printInt(intFlag(save_ux.saveSlotExists(dir, 0)));
    io.write("\n");
}
