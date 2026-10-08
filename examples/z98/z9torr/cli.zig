const std = @import("std");

pub const Args = struct {
    torrent_path: []const u8,
    max_peers: u32,
    max_up: u32,
    max_down: u32,
};

pub const FailureClass = enum(u8) {
    usage = 1,
    torrent = 2,
    tracker = 3,
    peer = 4,
    disk = 5,
};

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn parseU32(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > @intCast(u64, 4294967295)) return null;
    }
    return @intCast(u32, v);
}

pub fn usage() void {
    var l1: []const u8 = "usage: z9torr [--help] [--max-peers N] [--max-up N] [--max-down N] <file.torrent>\n";
    std.io.write(l1);
    var l2: []const u8 = "  -h, --help       show this help\n";
    std.io.write(l2);
    var l3: []const u8 = "  --max-peers N    max concurrent peers (reject > 100)\n";
    std.io.write(l3);
    var l4: []const u8 = "  --max-up N       upload limit in bytes/s\n";
    std.io.write(l4);
    var l5: []const u8 = "  --max-down N     download limit in bytes/s (reject > 65535)\n";
    std.io.write(l5);
}

fn usageError() void {
    usage();
    std.os.exit(1);
}

pub fn parseArgs(argc: i32, argv: [*][*]u8) Args {
    var a: Args = Args{
        .torrent_path = "",
        .max_peers = 50,
        .max_up = 0,
        .max_down = 0,
    };
    var have_path: bool = false;
    const n: usize = @intCast(usize, argc);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--help") or eq(tok, "-h")) {
            usage();
            std.os.exit(0);
        } else if (eq(tok, "--max-peers")) {
            i += 1;
            if (i >= n) usageError();
            if (parseU32(argAt(argv, i))) |pv| {
                if (pv > 100) usageError();
                a.max_peers = pv;
            } else {
                usageError();
            }
        } else if (eq(tok, "--max-up")) {
            i += 1;
            if (i >= n) usageError();
            if (parseU32(argAt(argv, i))) |pv2| {
                a.max_up = pv2;
            } else {
                usageError();
            }
        } else if (eq(tok, "--max-down")) {
            i += 1;
            if (i >= n) usageError();
            if (parseU32(argAt(argv, i))) |pv3| {
                if (pv3 > 65535) usageError();
                a.max_down = pv3;
            } else {
                usageError();
            }
        } else if (tok.len > 0 and tok[0] == '-') {
            usageError();
        } else {
            if (have_path) usageError();
            a.torrent_path = tok;
            have_path = true;
        }
    }
    if (!have_path) usageError();
    return a;
}

pub fn exitCodeFor(class: FailureClass) u8 {
    switch (class) {
        .usage => return 1,
        .torrent => return 2,
        .tracker => return 3,
        .peer => return 4,
        .disk => return 5,
        else => return 0,
    }
}
