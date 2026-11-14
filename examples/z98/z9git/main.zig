// main.zig -- z9git: read-only Git client for Z98 (local transports).
//
// Usage:
//   z9git clone <url> [dir] [--depth <n>] [--partial] [--max-down <KB/s>]
//   z9git fetch --deepen <n>
//   z9git log [ref]
//   z9git checkout <ref>
//   z9git -h | --help
//
// Local sources: a bare git dir path, a worktree path (the <path>/.git inside
// it is used), and file://<path>.  http:// and https:// use the smart-HTTP
// transport in httpgit.zig (clone/fetch; shallow, partial and resume).
// --max-down is KB/s and is passed to the streaming clone as bytes/s.
//
// Exit codes: 0 ok, 1 usage, 2 transport, 3 protocol, 4 object-store, 5 io.
//
// Z98 subset only; direct imports (no std barrel).

const arena_mod = @import("std_arena.zig");
const os = @import("std_os.zig");
const cli = @import("cli.zig");
const repo = @import("repo.zig");
const httpgit = @import("httpgit.zig");

// Dynamic arena backing. The default is 32 MiB; --arena-mb may raise it with no
// hard upper bound (the OS can page it). POSIX uses anonymous mmap and Win32
// uses VirtualAlloc, both of which are pagefile-backed, so a large arena does
// not need to be resident.
extern "c" fn mmap(addr: *void, length: usize, prot: i32, flags: i32, fd: i32, offset: i32) *void;
extern "c" fn munmap(addr: *void, length: usize) i32;
extern "stdcall" fn VirtualAlloc(addr: *void, size: usize, alloc_type: u32, protect: u32) *void;
extern "stdcall" fn VirtualFree(addr: *void, size: usize, free_type: u32) i32;

const PAGES_READ_WRITE: i32 = 3;
const MAP_PRIVATE_ANON: i32 = 2 + 0x20;
const MEM_COMMIT_RESERVE: u32 = 0x1000 + 0x2000;
const PAGE_READWRITE: u32 = 0x04;

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn allocArenaBytes(mb: u32) ?[]u8 {
    if (mb < cli.MIN_ARENA_MB) return null;
    const bytes64: u64 = @intCast(u64, mb) * @intCast(u64, 1024 * 1024);
    // A 32-bit address space cannot hold a 4 GiB arena; any larger request is
    // an allocation failure, not a hard policy cap.
    if (bytes64 > @intCast(u64, 0xFFFFFFFF)) return null;
    const n: usize = @intCast(usize, bytes64);
    if (@isWindows()) {
        const p = VirtualAlloc(nullVoid(), n, MEM_COMMIT_RESERVE, PAGE_READWRITE);
        if (@ptrToInt(p) == 0) return null;
        return @ptrCast([*]u8, p)[0..n];
    } else {
        const p = mmap(nullVoid(), n, PAGES_READ_WRITE, MAP_PRIVATE_ANON, -1, 0);
        if (@ptrToInt(p) >= 0xFFFFF000) return null;
        return @ptrCast([*]u8, p)[0..n];
    }
}

fn freeArenaBytes(buf: []u8) void {
    if (buf.len == 0) return;
    if (@isWindows()) {
        _ = VirtualFree(@ptrCast(*void, buf.ptr), 0, 0x8000);
    } else {
        _ = munmap(@ptrCast(*void, buf.ptr), buf.len);
    }
}

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

fn runHttpClone(arena: *arena_mod.Arena, url: []const u8, dest: []const u8, max_down_kbps: u32, depth: u32, partial: bool) i32 {
    httpgit.httpCloneWithOpts(arena, url, dest, kbpsToBps(max_down_kbps), depth, partial) catch |e| {
        writeMsg(repo.errorMessage(e));
        return repo.exitCode(e);
    };
    return 0;
}

fn runFetch(arena: *arena_mod.Arena, deepen: u32) i32 {
    const dr = repo.discoverResult(arena);
    if (!dr.ok) {
        writeMsg(dr.msg);
        return dr.code;
    }
    httpgit.httpFetch(arena, dr.git_dir, deepen, 0) catch |e| {
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
    httpgit.httpCheckoutRef(arena, dr.git_dir, ref_name, 0) catch |e| {
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

    var arena_buf: []u8 = undefined;
    if (allocArenaBytes(args.arena_mb)) |b| {
        arena_buf = b;
    } else {
        fail(cli.EXIT_IO, "z9git: cannot allocate the requested arena (--arena-mb)\n");
    }
    var arena = arena_mod.init(arena_buf);

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
            rc = runHttpClone(&arena, args.url, dest, args.max_down_kbps, args.depth, args.partial);
        } else {
            if (args.depth != 0 or args.partial) {
                fail(cli.EXIT_USAGE, "z9git: --depth/--partial require an http(s) source\n");
            }
            rc = runClone(&arena, src, dest);
        }
        os.exit(rc);
    } else if (args.cmd == cli.Command.fetch) {
        const rc = runFetch(&arena, args.deepen);
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
