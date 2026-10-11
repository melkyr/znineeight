// cli.zig — z9play command-line parsing (z9play M0/M1/M3: --info/--dump-setup/
// --pcm/--help/--version).
//
// Pure Z98: free functions, no generics, strict @intCast, string literals via
// `var s: []const u8 = "..."`. M0 exposes the metadata query; M1 adds the
// `--dump-setup` setup-summary query. Exactly one request mode is accepted per
// invocation (a conflicting or duplicate request is a usage error); the M5
// playback flags (`<file.ogg> --volume/--start/--loop/--quiet`) land later and
// extend this module. Exit codes follow the design spec §5: a malformed command
// line is exit 1 and `--help`/`--version` are exit 0 (the open/decoder codes 2
// and 3 are raised in main once the file is read).

const std = @import("std");

// Request mode selectors. `mode` is never 0 in a value returned by parseArgs.
pub const MODE_INFO: u8 = 1;
pub const MODE_DUMP_SETUP: u8 = 2;
pub const MODE_PCM: u8 = 3;
pub const MODE_WAV: u8 = 4;

// Parsed arguments: exactly one request (`--info`, `--dump-setup`, `--pcm` or
// `--wav`) and its target file path(s). `out_path` is empty except for
// `--pcm`/`--wav`.
pub const Args = struct {
    mode: u8,
    path: []const u8,
    out_path: []const u8,
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
    var l1: []const u8 = "usage: z9play --info <file.ogg> | --dump-setup <file.ogg>\n";
    std.io.write(l1);
    var l2: []const u8 = "  --info <file.ogg>        print stream metadata (channels, rate, duration, tags)\n";
    std.io.write(l2);
    var l3: []const u8 = "  --dump-setup <file.ogg>  print the Vorbis setup summary (counts of codebooks/floors/residues/mappings/modes)\n";
    std.io.write(l3);
    var l4: []const u8 = "  --pcm <in.ogg> <out.wav> decode to a canonical 44-byte-header PCM WAV (s16, interleaved)\n";
    std.io.write(l4);
    var l4b: []const u8 = "  --wav <in.ogg> <out.wav> play through the Player core into the hermetic WAV sink (M4 gate)\n";
    std.io.write(l4b);
    var l5: []const u8 = "  -h, --help               show this help\n";
    std.io.write(l5);
    var l6: []const u8 = "  --version                show version\n";
    std.io.write(l6);
}

pub fn version() void {
    var s: []const u8 = "z9play 0.1.0 (M4)\n";
    std.io.write(s);
}

fn usageError() void {
    usage();
    std.os.exit(1);
}

// Parse one request. `--help`/`--version` print and exit 0; a malformed command
// line (unknown flag, a request with no/empty file, a conflicting or duplicate
// request, or no request) prints usage and exits 1. On success returns the
// selected mode and its target path (plus the output path for `--pcm`).
pub fn parseArgs(argc: i32, argv: [*][*]u8) Args {
    const n: usize = @intCast(usize, argc);
    var path: []const u8 = "";
    var out_path: []const u8 = "";
    var mode: u8 = 0;
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
            if (mode != 0) usageError();
            i += 1;
            if (i >= n) usageError();
            path = argAt(argv, i);
            if (path.len == 0) usageError();
            mode = MODE_INFO;
        } else if (eq(tok, "--dump-setup")) {
            if (mode != 0) usageError();
            i += 1;
            if (i >= n) usageError();
            path = argAt(argv, i);
            if (path.len == 0) usageError();
            mode = MODE_DUMP_SETUP;
        } else if (eq(tok, "--pcm")) {
            if (mode != 0) usageError();
            i += 1;
            if (i >= n) usageError();
            path = argAt(argv, i);
            if (path.len == 0) usageError();
            i += 1;
            if (i >= n) usageError();
            out_path = argAt(argv, i);
            if (out_path.len == 0) usageError();
            mode = MODE_PCM;
        } else if (eq(tok, "--wav")) {
            if (mode != 0) usageError();
            i += 1;
            if (i >= n) usageError();
            path = argAt(argv, i);
            if (path.len == 0) usageError();
            i += 1;
            if (i >= n) usageError();
            out_path = argAt(argv, i);
            if (out_path.len == 0) usageError();
            mode = MODE_WAV;
        } else {
            usageError();
        }
    }
    if (mode == 0) usageError();
    return Args{ .mode = mode, .path = path, .out_path = out_path };
}
