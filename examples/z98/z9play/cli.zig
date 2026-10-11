// cli.zig — z9play command-line parsing (z9play M0: --info/--help/--version).
//
// Pure Z98: free functions, no generics, strict @intCast, string literals via
// `var s: []const u8 = "..."`. M0 exposes only the metadata query; the M5
// playback flags (`<file.ogg> --volume/--start/--loop/--quiet`) land later and
// extend this module. Exit codes follow the design spec §5: a malformed command
// line is exit 1 and `--help`/`--version` are exit 0 (the open/decoder codes 2
// and 3 are raised in main once the file is read).

const std = @import("std");

// Parsed M0 arguments: exactly one `--info <file>` request.
pub const InfoArgs = struct {
    path: []const u8,
};

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

// The i-th argv entry as a slice, up to its NUL terminator.
fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

pub fn usage() void {
    var l1: []const u8 = "usage: z9play --info <file.ogg>\n";
    std.io.write(l1);
    var l2: []const u8 = "  --info <file.ogg>  print stream metadata (channels, rate, duration, tags)\n";
    std.io.write(l2);
    var l3: []const u8 = "  -h, --help         show this help\n";
    std.io.write(l3);
    var l4: []const u8 = "  --version          show version\n";
    std.io.write(l4);
}

pub fn version() void {
    var s: []const u8 = "z9play 0.1.0 (M0)\n";
    std.io.write(s);
}

fn usageError() void {
    usage();
    std.os.exit(1);
}

// Parse M0 arguments. `--help`/`--version` print and exit 0; a malformed
// command line prints usage and exits 1. On success returns the `--info`
// target path.
pub fn parseArgs(argc: i32, argv: [*][*]u8) InfoArgs {
    const n: usize = @intCast(usize, argc);
    var path: []const u8 = "";
    var have_info: bool = false;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        var tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--help") or eq(tok, "-h")) {
            usage();
            std.os.exit(0);
        } else if (eq(tok, "--version")) {
            version();
            std.os.exit(0);
        } else if (eq(tok, "--info")) {
            if (have_info) usageError();
            i += 1;
            if (i >= n) usageError();
            path = argAt(argv, i);
            if (path.len == 0) usageError();
            have_info = true;
        } else {
            usageError();
        }
    }
    if (!have_info) usageError();
    return InfoArgs{ .path = path };
}
