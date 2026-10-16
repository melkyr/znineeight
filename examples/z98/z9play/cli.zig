// cli.zig — z9play command-line parsing (z9play M0/M1/M3: --info/--dump-setup/
// --pcm/--help/--version; M4: --wav; M5: interactive playback).
//
// Pure Z98: free functions, no generics, strict @intCast, string literals via
// `var s: []const u8 = "..."`. M0 exposes the metadata query; M1 adds the
// `--dump-setup` setup-summary query; M4 adds the `--wav` Player gate. M5 adds
// interactive playback: a bare `<file.ogg>` positional selects MODE_PLAY, and
// the flags `--volume N` / `--start SEC` / `--loop` / `--quiet` carry the
// playback options. Exactly one request mode is accepted per invocation (a
// conflicting or duplicate request is a usage error); the playback flags are
// rejected when combined with a request mode. Exit codes follow the design spec
// §5: a malformed command line is exit 1 and `--help`/`--version` are exit 0
// (the open/decoder/audio codes 2/3/4 are raised in main once the file is read).

const std = @import("std");

// Request mode selectors. `mode` is never 0 in a value returned by parseArgs.
pub const MODE_INFO: u8 = 1;
pub const MODE_DUMP_SETUP: u8 = 2;
pub const MODE_PCM: u8 = 3;
pub const MODE_WAV: u8 = 4;
pub const MODE_PLAY: u8 = 5;

// Parsed arguments: exactly one request (`--info`, `--dump-setup`, `--pcm`,
// `--wav`, or playback) and its target file path(s). `out_path` is empty except
// for `--pcm`/`--wav`; the remaining fields are the playback options from
// MODE_PLAY (ignored by the other modes).
pub const Args = struct {
    mode: u8,
    path: []const u8,
    out_path: []const u8,
    volume: u8,
    start_ms: u64,
    loop: bool,
    quiet: bool,
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
    var l1: []const u8 = "usage: z9play <file.ogg> [playback options] | --info <file.ogg> | --dump-setup <file.ogg>\n";
    std.io.write(l1);
    var l2: []const u8 = "  --info <file.ogg>        print stream metadata (channels, rate, duration, tags)\n";
    std.io.write(l2);
    var l3: []const u8 = "  --dump-setup <file.ogg>  print the Vorbis setup summary (counts of codebooks/floors/residues/mappings/modes)\n";
    std.io.write(l3);
    var l4: []const u8 = "  --pcm <in.ogg> <out.wav> decode to a canonical 44-byte-header PCM WAV (s16, interleaved)\n";
    std.io.write(l4);
    var l4b: []const u8 = "  --wav <in.ogg> <out.wav> play through the Player core into the hermetic WAV sink (M4 gate)\n";
    std.io.write(l4b);
    var l4c: []const u8 = "  <file.ogg> [--volume N] [--start SEC] [--loop] [--quiet]\n";
    std.io.write(l4c);
    var l4d: []const u8 = "                           play an OGG file interactively (space pause, +/- volume, q quit)\n";
    std.io.write(l4d);
    var l4e: []const u8 = "  --volume N               playback volume, 0..100 (default 80)\n";
    std.io.write(l4e);
    var l4f: []const u8 = "  --start SEC              skip to SEC seconds before playing\n";
    std.io.write(l4f);
    var l4g: []const u8 = "  --loop                   repeat the file until quit\n";
    std.io.write(l4g);
    var l4h: []const u8 = "  --quiet                  suppress the per-second status line\n";
    std.io.write(l4h);
    var l5: []const u8 = "  -h, --help               show this help\n";
    std.io.write(l5);
    var l6: []const u8 = "  --version                show version\n";
    std.io.write(l6);
}

pub fn version() void {
    var s: []const u8 = "z9play 0.1.0 (M5)\n";
    std.io.write(s);
}

fn usageError() void {
    usage();
    std.os.exit(1);
}

// `--start` takes an integer number of seconds. A non-integer / invalid value
// (including a missing operand) prints an informative message before the usage
// summary and still exits 1, so the failure is self-explanatory rather than a
// bare usage dump. Other flags keep the plain `usageError` behaviour.
fn startError() void {
    var msg: []const u8 = "z9play: --start expects an integer number of seconds\n";
    std.io.write(msg);
    usage();
    std.os.exit(1);
}

// Parse one invocation. `--help`/`--version` print and exit 0; a malformed
// command line prints usage and exits 1. Request modes (`--info`/`--dump-setup`/
// `--pcm`/`--wav`) are mutually exclusive and take their file operand(s)
// inline; a bare positional `<file.ogg>` selects the M5 playback mode. The
// playback flags (`--volume N` 0..100, `--start SEC`, `--loop`, `--quiet`) may
// appear in any order around the positional and are rejected when combined
// with a request mode. On success returns the selected mode, its target
// path(s), and the playback options (volume defaults to 80).
fn parseU64(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        var c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > 1000000000) return null;
    }
    return v;
}

pub fn parseArgs(argc: i32, argv: [*][*]u8) Args {
    const n: usize = @intCast(usize, argc);
    var path: []const u8 = "";
    var out_path: []const u8 = "";
    var mode: u8 = 0;
    var volume: u8 = 80;
    var start_ms: u64 = 0;
    var loop: bool = false;
    var quiet: bool = false;
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
        } else if (eq(tok, "--volume")) {
            if (mode != 0 and mode != MODE_PLAY) usageError();
            mode = MODE_PLAY;
            i += 1;
            if (i >= n) usageError();
            if (parseU64(argAt(argv, i))) |v| {
                if (v > 100) usageError();
                volume = @intCast(u8, v);
            } else {
                usageError();
            }
        } else if (eq(tok, "--start")) {
            if (mode != 0 and mode != MODE_PLAY) usageError();
            mode = MODE_PLAY;
            i += 1;
            if (i >= n) startError();
            if (parseU64(argAt(argv, i))) |v| {
                start_ms = v * 1000;
            } else {
                startError();
            }
        } else if (eq(tok, "--loop")) {
            if (mode != 0 and mode != MODE_PLAY) usageError();
            mode = MODE_PLAY;
            loop = true;
        } else if (eq(tok, "--quiet")) {
            if (mode != 0 and mode != MODE_PLAY) usageError();
            mode = MODE_PLAY;
            quiet = true;
        } else if (tok.len > 0 and tok[0] == '-') {
            usageError();
        } else {
            if (mode != 0 and mode != MODE_PLAY) usageError();
            if (mode == MODE_PLAY and path.len != 0) usageError();
            if (tok.len == 0) usageError();
            path = tok;
            mode = MODE_PLAY;
        }
    }
    if (mode == 0) usageError();
    if (mode == MODE_PLAY and path.len == 0) usageError();
    return Args{ .mode = mode, .path = path, .out_path = out_path, .volume = volume, .start_ms = start_ms, .loop = loop, .quiet = quiet };
}
