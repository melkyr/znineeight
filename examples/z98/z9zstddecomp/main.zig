// main.zig -- z9zstddecomp: single-shot zstd frame decompressor CLI.
//
// Usage:
//   z9zstddecomp <in.zst> <out> [--dict <file>]
//                [--max-window-log <n>] [--max-output <n>]
//   z9zstddecomp -h | --help
//
// Reads the whole input through std_file, decodes it through std_zstd
// (zstdDecompress, or zstdDecompressDict when --dict is given), and writes the
// decoded bytes through std_file. --dict accepts either an RFC 8878 magic
// dictionary (0xEC30A437 prefix, id + entropy tables + content) or a raw
// content dictionary.
//
// --max-window-log defaults to 27 (the zstd maximum). --max-output defaults to
// 16 MiB and may not exceed the app's 32 MiB usable output capacity (a larger
// request is a usage error, rc1). When the frame declares an exact content
// size the decoder gets exactly that many bytes; otherwise the destination
// starts at 64 KiB and grows by doubling to the cap. The output buffer is
// static and is never reserved at --max-output size up front.
//
// Exit codes: 0 ok, 1 usage (including an unacceptably large --max-output), 2
// input open/read error (including --dict), 3 decode error (Corrupt or
// WindowTooBig), 4 output write error, 5 output exceeds --max-output.
//
// Z98 subset only; direct imports (no std barrel).

const zstd = @import("std_zstd.zig");
const file_mod = @import("std_file.zig");
const arena_mod = @import("std_arena.zig");
const os = @import("std_os.zig");

const DEFAULT_MAX_WINDOW_LOG: u8 = 27;
const DEFAULT_MAX_OUTPUT: usize = 16 * 1024 * 1024;
// The first decode attempt uses START_SIZE bytes; unknown-size frames then
// double up to the caller's cap. The output bytes come from a static buffer
// (never a --max-output-sized arena allocation), and OUTPUT_CAPACITY is the
// largest usable --max-output the app accepts.
const START_SIZE: usize = 64 * 1024;
const OUTPUT_CAPACITY: usize = 32 * 1024 * 1024;
const ARENA_SIZE: usize = 32 * 1024 * 1024;

var g_arena_buf: [ARENA_SIZE]u8 = undefined;
var g_out_buf: [OUTPUT_CAPACITY]u8 = undefined;

const Args = struct {
    in_path: []const u8,
    out_path: []const u8,
    dict_path: []const u8,
    has_dict: bool,
    max_window_log: u8,
    max_output: usize,
    help: bool,
    bad: bool,
};

const DecodeStatus = struct {
    ok: bool,
    too_small: bool,
    window_too_big: bool,
    n: u32,
};

fn writeMsg(s: []const u8) void {
    if (s.len != 0) @stdoutWrite(s.ptr, s.len);
}

fn fail(code: i32, msg: []const u8) noreturn {
    writeMsg(msg);
    os.exit(code);
}

fn usage() void {
    writeMsg("usage: z9zstddecomp <in.zst> <out> [--dict <file>] [--max-window-log <n>] [--max-output <n>]\n");
    writeMsg("  -h, --help              print this help and exit 0\n");
    writeMsg("  --dict <file>           zstd dictionary (magic or raw content)\n");
    writeMsg("  --max-window-log <n>    window cap log2 (default 27, zstd maximum)\n");
    writeMsg("  --max-output <n>        decoded output cap in bytes (default 16 MiB; capacity 32 MiB)\n");
    writeMsg("exit codes: 0 ok, 1 usage, 2 input open/read, 3 decode, 4 output write, 5 output too big\n");
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn parseU64(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > 4294967295) return null;
    }
    return v;
}

fn parseArgs() Args {
    var a = Args{
        .in_path = "",
        .out_path = "",
        .dict_path = "",
        .has_dict = false,
        .max_window_log = DEFAULT_MAX_WINDOW_LOG,
        .max_output = DEFAULT_MAX_OUTPUT,
        .help = false,
        .bad = false,
    };
    const n: usize = os.argc();
    var positional: usize = 0;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const tok: []const u8 = os.argv(i);
        if (eq(tok, "-h") or eq(tok, "--help")) {
            a.help = true;
            return a;
        } else if (eq(tok, "--dict")) {
            i += 1;
            if (i >= n) {
                a.bad = true;
                return a;
            }
            a.dict_path = os.argv(i);
            a.has_dict = true;
        } else if (eq(tok, "--max-window-log")) {
            i += 1;
            if (i >= n) {
                a.bad = true;
                return a;
            }
            if (parseU64(os.argv(i))) |v| {
                if (v > 27) {
                    a.bad = true;
                    return a;
                }
                a.max_window_log = @intCast(u8, v);
            } else {
                a.bad = true;
                return a;
            }
        } else if (eq(tok, "--max-output")) {
            i += 1;
            if (i >= n) {
                a.bad = true;
                return a;
            }
            if (parseU64(os.argv(i))) |v| {
                a.max_output = @intCast(usize, v);
            } else {
                a.bad = true;
                return a;
            }
        } else if (tok.len > 0 and tok[0] == '-') {
            a.bad = true;
            return a;
        } else {
            if (positional == 0) {
                a.in_path = tok;
            } else if (positional == 1) {
                a.out_path = tok;
            } else {
                a.bad = true;
                return a;
            }
            positional += 1;
        }
    }
    if (positional != 2) a.bad = true;
    return a;
}


fn decodeOnce(src: []const u8, dst: []u8, dict_bytes: []const u8,
              has_dict: bool, max_window_log: u8) DecodeStatus {
    var result = DecodeStatus{
        .ok = false,
        .too_small = false,
        .window_too_big = false,
        .n = 0,
    };
    var n: u32 = 0;
    if (has_dict) {
        n = zstd.zstdDecompressDict(src, dst, dict_bytes, max_window_log) catch |e| {
            if (e == error.OutputTooSmall) {
                result.too_small = true;
            } else if (e == error.WindowTooBig) {
                result.window_too_big = true;
            }
            return result;
        };
    } else {
        n = zstd.zstdDecompress(src, dst, max_window_log) catch |e| {
            if (e == error.OutputTooSmall) {
                result.too_small = true;
            } else if (e == error.WindowTooBig) {
                result.window_too_big = true;
            }
            return result;
        };
    }
    result.ok = true;
    result.n = n;
    return result;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    const opts = parseArgs();
    if (opts.help) {
        usage();
        os.exit(0);
    }
    if (opts.bad) {
        usage();
        os.exit(1);
    }

    if (opts.max_output > OUTPUT_CAPACITY) {
        fail(1, "z9zstddecomp: --max-output exceeds usable output capacity (32 MiB)\n");
    }

    var arena = arena_mod.init(g_arena_buf[0..]);
    const input = file_mod.readAll(&arena, opts.in_path) catch |e| {
        if (e == error.OutOfMemory) {
            fail(1, "z9zstddecomp: input exceeds the app arena; use a smaller input\n");
            return;
        }
        fail(2, "z9zstddecomp: cannot read input\n");
        return;
    };

    var dict_bytes: []const u8 = "";
    if (opts.has_dict) {
        dict_bytes = file_mod.readAll(&arena, opts.dict_path) catch |e| {
            if (e == error.OutOfMemory) {
                fail(1, "z9zstddecomp: dictionary exceeds the app arena\n");
                return;
            }
            fail(2, "z9zstddecomp: cannot read dictionary\n");
            return;
        };
    }

    const declared = zstd.zstdFrameContentSize(input);
    var size: usize = 0;
    var exact: bool = false;
    if (declared) |d| {
        if (d > @intCast(u64, opts.max_output)) {
            fail(5, "z9zstddecomp: output exceeds --max-output\n");
        }
        size = @intCast(usize, d);
        exact = true;
    } else {
        size = START_SIZE;
        if (size > opts.max_output) size = opts.max_output;
    }

    var done: bool = false;
    var written: u32 = 0;
    while (!done) {
        const st = decodeOnce(input, g_out_buf[0..size], dict_bytes,
                              opts.has_dict, opts.max_window_log);
        if (st.ok) {
            written = st.n;
            done = true;
        } else if (st.too_small) {
            if (exact) {
                fail(3, "z9zstddecomp: declared content size exceeds actual output\n");
            }
            if (size >= opts.max_output) {
                fail(5, "z9zstddecomp: output exceeds --max-output\n");
            }
            var next: usize = size * 2;
            if (next < size or next > opts.max_output) next = opts.max_output;
            if (next == size) {
                fail(5, "z9zstddecomp: output exceeds --max-output\n");
            }
            size = next;
        } else if (st.window_too_big) {
            fail(3, "z9zstddecomp: frame window exceeds --max-window-log\n");
        } else {
            fail(3, "z9zstddecomp: corrupt or unsupported zstd stream\n");
        }
    }

    const out_len: usize = @intCast(usize, written);
    file_mod.writeAll(opts.out_path, g_out_buf[0..out_len]) catch {
        fail(4, "z9zstddecomp: cannot write output\n");
        return;
    };
    os.exit(0);
}
