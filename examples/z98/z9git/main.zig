// main.zig -- z9git: read-only Git client for Z98 (local transports).
//
// Usage:
//   z9git clone <url> [dir] [--max-down <KB/s>]
//   z9git log [ref]
//   z9git checkout <ref>
//   z9git -h | --help
//
// Task 7 covers local sources only: a bare git dir path, a worktree path (the
// <path>/.git inside it is used), and file://<path>.  http:// and https:// are
// Task 8's smart-HTTP transport; this build reports them as a transport error
// (rc2) before touching the destination.
//
// Exit codes: 0 ok, 1 usage, 2 transport, 3 protocol, 4 object-store, 5 io.
//
// Z98 subset only; direct imports (no std barrel).

const arena_mod = @import("std_arena.zig");
const os = @import("std_os.zig");
const cli = @import("cli.zig");
const repo = @import("repo.zig");

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
        if (cli.startsWith(src, "file://")) {
            src = src[7..];
        } else if (cli.startsWith(src, "http://") or cli.startsWith(src, "https://")) {
            fail(cli.EXIT_TRANSPORT, "z9git: http/https transport is not implemented yet (Task 8)\n");
        } else if (containsScheme(src)) {
            fail(cli.EXIT_TRANSPORT, "z9git: unsupported transport scheme\n");
        }
        var dest: []const u8 = args.dest;
        if (!args.has_dest) {
            dest = cli.deriveDest(&arena, src);
            if (dest.len == 0) fail(cli.EXIT_IO, "z9git: out of memory\n");
        }
        const rc = runClone(&arena, src, dest);
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
