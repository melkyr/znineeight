// main.zig -- z9git: read-only Git client for Z98 (local transports).
//
// Usage:
//   z9git clone <url> [dir] [--max-down <KB/s>]
//   z9git log [ref]
//   z9git checkout <ref>
//   z9git -h | --help
//
// Local sources: a bare git dir path, a worktree path (the <path>/.git inside
// it is used), and file://<path>.  http:// and https:// use the smart-HTTP
// transport in httpgit.zig (clone only).  --max-down is KB/s and is passed to
// the streaming clone as bytes/s.
//
// Exit codes: 0 ok, 1 usage, 2 transport, 3 protocol, 4 object-store, 5 io.
//
// Z98 subset only; direct imports (no std barrel).

const arena_mod = @import("std_arena.zig");
const os = @import("std_os.zig");
const cli = @import("cli.zig");
const repo = @import("repo.zig");
const httpgit = @import("httpgit.zig");

const ARENA_SIZE: usize = 16 * 1024 * 1024;

var g_arena_buf: [ARENA_SIZE]u8 = undefined;

fn writeMsg(s: []const u8) void {
    if (s.len != 0) @stdoutWrite(s.ptr, s.len);
}

fn fail(code: i32, msg: []const u8) noreturn {
    writeMsg(msg);
    os.exit(code);
}

fn containsScheme(s: []const u8) bool {
    var i: usize = 0;
    while (i + 3 <= s.len) : (i += 1) {
        if (s[i] == ':' and s[i + 1] == '/' and s[i + 2] == '/') return true;
    }
    return false;
}

fn runClone(arena: *arena_mod.Arena, src: []const u8, dest: []const u8) i32 {
    repo.cloneLocal(arena, src, dest) catch |e| {
        writeMsg(repo.errorMessage(e));
        return repo.exitCode(e);
    };
    return 0;
}

// --max-down is KB/s (Ruling 8); the smart-HTTP sink takes bytes/s.
fn kbpsToBps(kbps: u32) u32 {
    const v: u64 = @intCast(u64, kbps) * 1024;
    if (v > 4294967295) return 4294967295;
    return @intCast(u32, v);
}

fn runHttpClone(arena: *arena_mod.Arena, url: []const u8, dest: []const u8, max_down_kbps: u32) i32 {
    httpgit.httpClone(arena, url, dest, kbpsToBps(max_down_kbps)) catch |e| {
        writeMsg(repo.errorMessage(e));
        return repo.exitCode(e);
    };
    return 0;
}

fn runLog(arena: *arena_mod.Arena, ref_name: []const u8) i32 {
    const dr = repo.discoverResult(arena);
    if (!dr.ok) {
        writeMsg(dr.msg);
        return dr.code;
    }
    repo.logRef(arena, dr.git_dir, ref_name) catch |e| {
        writeMsg(repo.errorMessage(e));
        return repo.exitCode(e);
    };
    return 0;
}

fn runCheckout(arena: *arena_mod.Arena, ref_name: []const u8) i32 {
    const dr = repo.discoverResult(arena);
    if (!dr.ok) {
        writeMsg(dr.msg);
        return dr.code;
    }
    repo.checkoutRef(arena, dr.git_dir, ref_name) catch |e| {
        writeMsg(repo.errorMessage(e));
        return repo.exitCode(e);
    };
    return 0;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    const args = cli.parse();
    if (args.help) {
        cli.usage();
        os.exit(cli.EXIT_OK);
    }
    if (args.bad) {
        cli.usage();
        os.exit(cli.EXIT_USAGE);
    }

    var arena = arena_mod.init(g_arena_buf[0..]);

    if (args.cmd == cli.Command.clone) {
        var src = args.url;
        var remote = false;
        if (cli.startsWith(src, "file://")) {
            src = src[7..];
        } else if (cli.startsWith(src, "http://") or cli.startsWith(src, "https://")) {
            remote = true;
        } else if (containsScheme(src)) {
            fail(cli.EXIT_TRANSPORT, "z9git: unsupported transport scheme\n");
        }
        var dest: []const u8 = args.dest;
        if (!args.has_dest) {
            dest = cli.deriveDest(&arena, if (remote) args.url else src);
            if (dest.len == 0) fail(cli.EXIT_IO, "z9git: out of memory\n");
        }
        var rc: i32 = 0;
        if (remote) {
            rc = runHttpClone(&arena, args.url, dest, args.max_down_kbps);
        } else {
            rc = runClone(&arena, src, dest);
        }
        os.exit(rc);
    } else if (args.cmd == cli.Command.log) {
        const ref_name: []const u8 = if (args.has_ref) args.reference else "";
        const rc = runLog(&arena, ref_name);
        os.exit(rc);
    } else if (args.cmd == cli.Command.checkout) {
        const rc = runCheckout(&arena, args.reference);
        os.exit(rc);
    }

    cli.usage();
    os.exit(cli.EXIT_USAGE);
}
