const std = @import("std");
const cli = @import("cli.zig");
const filemod = @import("std_file.zig");
const torrentlib = @import("torrent.zig");
const hexmod = @import("std_hex.zig");
const parse = @import("std_parse.zig");

// One torrent arena (spec §9), backed by a static buffer. Never reset.
var g_arena_buf: [4194304]u8 = undefined;

fn writeText(s: []const u8) void {
    std.io.write(s);
}

fn writeU64(v: u64) void {
    var buf: [24]u8 = undefined;
    var n = parse.itoa64(buf[0..], @intCast(i64, v));
    std.io.write(n);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    var av: [][*]u8 = argv[0..n];
    var args: cli.Args = cli.parseArgs(argc, av);
    if (!filemod.exists(args.torrent_path)) {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
    }

    var arena: std.arena.Arena = std.arena.init(g_arena_buf[0..]);
    var bytes: []u8 = filemod.readAll(&arena, args.torrent_path) catch {
        var msg: []const u8 = "z9torr: cannot read torrent file\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };

    const t: torrentlib.Torrent = torrentlib.load(&arena, bytes) catch {
        var msg: []const u8 = "z9torr: malformed torrent\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };

    var l_name: []const u8 = "name: ";
    writeText(l_name);
    writeText(t.name);
    var nl: []const u8 = "\n";
    writeText(nl);

    var l_len: []const u8 = "length: ";
    writeText(l_len);
    writeU64(t.total_length);
    writeText(nl);

    var l_pl: []const u8 = "piece length: ";
    writeText(l_pl);
    writeU64(@intCast(u64, t.piece_length));
    writeText(nl);

    var l_pc: []const u8 = "pieces: ";
    writeText(l_pc);
    writeU64(@intCast(u64, t.piece_hashes.len / 20));
    writeText(nl);

    var l_ih: []const u8 = "info_hash: ";
    writeText(l_ih);
    const hex: []u8 = hexmod.encodeLower(&arena, t.info_hash[0..20]) catch {
        var msg: []const u8 = "z9torr: malformed torrent\n";
        std.io.write(msg);
        std.os.exit(@intCast(i32, cli.exitCodeFor(cli.FailureClass.torrent)));
        return;
    };
    writeText(hex);
    writeText(nl);
}
