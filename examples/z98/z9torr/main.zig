const std = @import("std");
const cli = @import("cli.zig");
const filemod = @import("std_file.zig");

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    var av: [][*]u8 = argv[0..n];
    var args: cli.Args = cli.parseArgs(argc, av);
    if (!filemod.exists(args.torrent_path)) {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
    }
    var ok: []const u8 = "z9torr: torrent accepted (parsing lands in Task 2)\n";
    std.io.write(ok);
}
