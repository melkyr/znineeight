// undtool_native.zig — UNDERSANDED native (Linux) tool gate runner (spec §26/§34).
//
// The M3 gate runs the tool dispatcher headless on Linux: `--sim`, `--replay`,
// `--test-rules`, and `--dump-grid` all live in undtool.zig and never touch
// std_gfx. The console entry main_console.zig links the Win9x-only std_gfx
// (DirectDraw, <windows.h>) for the playable text fight, so it cannot link
// natively; this gfx-free entry is the native gate runner (undtool.nix) that
// build.sh emits with `-osl`.

const undtool = @import("undtool.zig");

pub fn main(argc: i32, argv: [*][*]u8) void {
    undtool.run(argc, argv);
}
