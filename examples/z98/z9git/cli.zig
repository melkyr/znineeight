// cli.zig -- z9git command-line parsing and the exit-code contract.
//
// Commands:
//   z9git clone <url> [dir] [--depth <n>] [--partial] [--max-down <KB/s>]
//   z9git fetch --deepen <n>
//   z9git log [ref]
//   z9git checkout <ref>
//   z9git -h | --help
//
// Exit codes (shared with main.zig):
//   0 ok
//   1 usage error
//   2 transport error (including http/https, which Task 8 adds)
//   3 protocol error (bad ref, missing pack idx, corrupt revision data)
//   4 object-store error
//   5 io error (including out of memory)
//
// Z98 subset only; direct imports (no std barrel).

const arena_mod = @import("std_arena.zig");
const os = @import("std_os.zig");

pub const EXIT_OK: i32 = 0;
pub const EXIT_USAGE: i32 = 1;
pub const EXIT_TRANSPORT: i32 = 2;
pub const EXIT_PROTOCOL: i32 = 3;
pub const EXIT_OBJECT_STORE: i32 = 4;
pub const EXIT_IO: i32 = 5;

pub const Command = enum { none, help, clone, fetch, log, checkout };

pub const Args = struct {
    cmd: Command,
    url: []const u8,
    dest: []const u8,
    has_dest: bool,
    reference: []const u8,
    has_ref: bool,
    max_down_kbps: u32,
    arena_mb: u32,
    depth: u32,
    deepen: u32,
    partial: bool,
    help: bool,
    bad: bool,
};


pub const DEFAULT_ARENA_MB: u32 = 32;
pub const MIN_ARENA_MB: u32 = 16;

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        if (s[i] != prefix[i]) return false;
    }
    return true;
}

fn endsWith(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        if (s[s.len - suffix.len + i] != suffix[i]) return false;
    }
    return true;
}

fn parseU32(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > 4294967295) return null;
    }
    return @intCast(u32, v);
}

fn parseArenaMb(s: []const u8) ?u32 {
    const v = parseU32(s) orelse return null;
    if (v < MIN_ARENA_MB) return null;
    return v;
}

pub fn usage() void {
    writeMsg("usage: z9git clone <url> [dir] [--depth <n>] [--partial] [--max-down <KB/s>] [--arena-mb <N>]\n");
    writeMsg("       z9git fetch --deepen <n> [--arena-mb <N>]\n");
    writeMsg("       z9git log [ref] [--arena-mb <N>]\n");
    writeMsg("       z9git checkout <ref> [--arena-mb <N>]\n");
    writeMsg("       z9git -h\n");
    writeMsg("  transports: <path> or file://<path>; http:// and https:// (smart HTTP)\n");
    writeMsg("  resume: interrupted http(s) clones keep .git/z9git-state and a verified\n");
    writeMsg("          prefix pack; re-run clone or fetch --deepen <n> to continue\n");
    writeMsg("  shallow: --depth <n> writes .git/shallow; log stops at the boundary\n");
    writeMsg("  partial: --partial requests filter=blob:none and fetches checkout blobs\n");
    writeMsg("           on demand (recommended with --depth for modem/large repos)\n");
    writeMsg("  arena: --arena-mb <N> default 32, minimum 16, no hard upper bound;\n");
    writeMsg("         allocated dynamically so the OS can page, reset per phase, and\n");
    writeMsg("         large objects/packs spill to disk (external idx/temp sort)\n");
    writeMsg("exit codes: 0 ok, 1 usage, 2 transport, 3 protocol, 4 object-store, 5 io\n");
}


fn writeMsg(s: []const u8) void {
    if (s.len != 0) @stdoutWrite(s.ptr, s.len);
}

pub fn parse() Args {
    var a = Args{
        .cmd = Command.none,
        .url = "",
        .dest = "",
        .has_dest = false,
        .reference = "",
        .has_ref = false,
        .max_down_kbps = 0,
        .arena_mb = DEFAULT_ARENA_MB,
        .depth = 0,
        .deepen = 0,
        .partial = false,
        .help = false,
        .bad = false,
    };
    const n: usize = os.argc();
    if (n < 2) {
        a.bad = true;
        return a;
    }

    const cmd = os.argv(1);
    if (eq(cmd, "-h") or eq(cmd, "--help")) {
        a.cmd = Command.help;
        a.help = true;
        return a;
    }
    if (eq(cmd, "clone")) {
        a.cmd = Command.clone;
        var positional: usize = 0;
        var i: usize = 2;
        while (i < n) : (i += 1) {
            const tok = os.argv(i);
            if (eq(tok, "-h") or eq(tok, "--help")) {
                a.cmd = Command.help;
                a.help = true;
                return a;
            }
            if (eq(tok, "--max-down")) {
                i += 1;
                if (i >= n) {
                    a.bad = true;
                    return a;
                }
                if (parseU32(os.argv(i))) |v| {
                    a.max_down_kbps = v;
                } else {
                    a.bad = true;
                    return a;
                }
            } else if (eq(tok, "--arena-mb")) {
                i += 1;
                if (i >= n) {
                    a.bad = true;
                    return a;
                }
                if (parseArenaMb(os.argv(i))) |v| {
                    a.arena_mb = v;
                    continue;
                } else {
                    a.bad = true;
                    return a;
                }
            } else if (eq(tok, "--depth")) {
                i += 1;
                if (i >= n) {
                    a.bad = true;
                    return a;
                }
                if (parseU32(os.argv(i))) |v| {
                    if (v == 0) {
                        a.bad = true;
                        return a;
                    }
                    a.depth = v;
                } else {
                    a.bad = true;
                    return a;
                }
            } else if (eq(tok, "--partial")) {
                a.partial = true;
            } else if (tok.len > 0 and tok[0] == '-') {

                a.bad = true;
                return a;
            } else {
                if (positional == 0) {
                    a.url = tok;
                } else if (positional == 1) {
                    a.dest = tok;
                    a.has_dest = true;
                } else {
                    a.bad = true;
                    return a;
                }
                positional += 1;
            }
        }
        if (positional < 1) a.bad = true;
        return a;
    }
    if (eq(cmd, "fetch")) {
        a.cmd = Command.fetch;
        var i: usize = 2;
        while (i < n) : (i += 1) {
            const tok = os.argv(i);
            if (eq(tok, "-h") or eq(tok, "--help")) {
                a.cmd = Command.help;
                a.help = true;
                return a;
            }
            if (eq(tok, "--deepen")) {
                i += 1;
                if (i >= n) {
                    a.bad = true;
                    return a;
                }
                if (parseU32(os.argv(i))) |v| {
                    if (v == 0) {
                        a.bad = true;
                        return a;
                    }
                    a.deepen = v;
                } else {
                    a.bad = true;
                    return a;
                }
            } else if (eq(tok, "--arena-mb")) {
                i += 1;
                if (i >= n) {
                    a.bad = true;
                    return a;
                }
                if (parseArenaMb(os.argv(i))) |v| {
                    a.arena_mb = v;
                } else {
                    a.bad = true;
                    return a;
                }
            } else {
                a.bad = true;
                return a;
            }
        }
        if (a.deepen == 0) a.bad = true;
        return a;
    }
    if (eq(cmd, "log")) {

        a.cmd = Command.log;
        var positional: usize = 0;
        var i: usize = 2;
        while (i < n) : (i += 1) {
            const tok = os.argv(i);
            if (eq(tok, "-h") or eq(tok, "--help")) {
                a.cmd = Command.help;
                a.help = true;
                return a;
            }
            if (eq(tok, "--arena-mb")) {
                i += 1;
                if (i >= n) {
                    a.bad = true;
                    return a;
                }
                if (parseArenaMb(os.argv(i))) |v| {
                    a.arena_mb = v;
                    continue;
                } else {
                    a.bad = true;
                    return a;
                }
            } else if (tok.len > 0 and tok[0] == '-') {
                a.bad = true;
                return a;
            }
            if (positional == 0) {
                a.reference = tok;
                a.has_ref = true;
            } else {
                a.bad = true;
                return a;
            }
            positional += 1;
        }
        return a;
    }
    if (eq(cmd, "checkout")) {
        a.cmd = Command.checkout;
        var positional: usize = 0;
        var i: usize = 2;
        while (i < n) : (i += 1) {
            const tok = os.argv(i);
            if (eq(tok, "-h") or eq(tok, "--help")) {
                a.cmd = Command.help;
                a.help = true;
                return a;
            }
            if (eq(tok, "--arena-mb")) {
                i += 1;
                if (i >= n) {
                    a.bad = true;
                    return a;
                }
                if (parseArenaMb(os.argv(i))) |v| {
                    a.arena_mb = v;
                    continue;
                } else {
                    a.bad = true;
                    return a;
                }
            } else if (tok.len > 0 and tok[0] == '-') {
                a.bad = true;
                return a;
            }
            if (positional == 0) {
                a.reference = tok;
                a.has_ref = true;
            } else {
                a.bad = true;
                return a;
            }
            positional += 1;
        }
        if (positional != 1) a.bad = true;
        return a;
    }
    a.bad = true;
    return a;
}

// Default clone destination: the source basename without a trailing slash or
// a ".git" suffix; "repo" when the source has no basename.
pub fn deriveDest(arena: *arena_mod.Arena, src: []const u8) []const u8 {
    var end = src.len;
    while (end > 0) {
        if (src[end - 1] != '/' and src[end - 1] != '\\') break;
        end -= 1;
    }
    var start = end;
    while (start > 0) {
        if (src[start - 1] == '/' or src[start - 1] == '\\') break;
        start -= 1;
    }
    var name = src[start..end];
    if (endsWith(name, ".git")) name = name[0 .. name.len - 4];
    if (name.len == 0) name = "repo";
    const raw = arena_mod.alloc(arena, name.len) catch return "";
    var i: usize = 0;
    while (i < name.len) : (i += 1) raw[i] = name[i];
    return raw[0..name.len];
}
