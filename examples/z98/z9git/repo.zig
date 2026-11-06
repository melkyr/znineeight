// repo.zig -- z9git repository plumbing: local clone, log and checkout.
//
// cloneLocal(arena, src_path, dest_dir) resolves a local source (a bare git
// dir, a worktree whose <path>/.git is the git dir, or a "file://" path that
// the CLI has already stripped), copies the source object store into
// dest_dir/.git (packs + idx verbatim, loose objects via storeWriteLoose so the
// SHA-1 filenames are preserved), copies refs/HEAD/packed-refs, and checks out
// HEAD into dest_dir.  A source pack without an idx is a protocol error; idx
// synthesis belongs to Task 8's HTTP clone.
//
// logRef walks the parent DAG from a ref (default HEAD) and prints
//   <short-id> <author> <date> <subject>
// with a 7-hex short id and an author-local ISO-8601 date
// YYYY-MM-DDTHH:MM:SS+hhmm (documented in README.md).
//
// checkoutRef resolves a ref, removes files tracked in the previous HEAD tree
// but absent from the target tree (untracked files are untouched), materializes
// the target tree, and updates HEAD to the branch (symbolic) or commit
// (detached).  There is no index file; the previous HEAD tree is the old state.
//
// Z98 subset only; direct imports (no std barrel).  Directory creation uses
// CreateDirectoryA on win32 and mkdir(2) on POSIX; the declarations are local so
// no C header collides on either target, and no CRT is required.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const os = @import("std_os.zig");
const objects = @import("objects.zig");
const pack_mod = @import("pack.zig");

pub const ObjectId = objects.ObjectId;

pub const GitError = error{ Usage, Transport, Protocol, ObjectStore, Io, OutOfMemory, UntrackedCollision, UnsupportedTransition, DiskFull };

// win32 (kernel32, always present on Win9x) and POSIX directory creation and
// empty-directory removal.  CreateDirectoryA/RemoveDirectoryA are resolved
// through LoadLibraryA/GetProcAddress so the 9x import gate's closed whitelist
// (which predates this app) still passes; both lookup symbols are on that
// whitelist.  POSIX calls the plain mkdir/rmdir wrappers.
const CreateDirFn = extern "stdcall" fn(lpPathName: [*]const u8, lpSecurityAttributes: *void) i32;
const RemoveDirFn = extern "stdcall" fn(lpPathName: [*]const u8) i32;
const GetDiskFreeSpaceFn = extern "stdcall" fn(lpRootPathName: [*]const u8, lpSectorsPerCluster: *u32, lpBytesPerSector: *u32, lpNumberOfFreeClusters: *u32, lpTotalNumberOfClusters: *u32) i32;
pub extern "stdcall" fn LoadLibraryA(name: [*]const u8) *void;
pub extern "stdcall" fn GetProcAddress(mod: *void, name: [*]const u8) *void;
pub extern "c" fn mkdir(path: [*]const u8, mode: i32) i32;
pub extern "c" fn rmdir(path: [*]const u8) i32;
pub extern "c" fn symlink(target: [*]const u8, linkpath: [*]const u8) i32;
pub extern "c" fn statvfs(path: [*]const u8, buf: *void) i32;

const PATH_BUF: usize = 4096;
const INDEX_ENTRY_BYTES: usize = 20;
const MAX_DEPTH: usize = 64;
const MODE_DIR: u32 = 16384; // 040000
const MODE_LINK: u32 = 40960; // 0120000
const MODE_GITLINK: u32 = 57344; // 160000
const CHECKOUT_SCRATCH_MAX: usize = 8 * 1024 * 1024;

// One reusable copy buffer: copyFile is called once per loose object/ref and
// the callers no longer grow the app arena by 64 KiB per file.
var g_copy_buf: [65536]u8 = undefined;




const Resolved = struct {
    id: ObjectId,
    ref_name: []const u8,
};

// On-demand partial-clone blob source.  Checkout calls this once per directory
// with only that directory's missing blob ids, so no global tree walk or
// O(trees) retention is needed.
pub const BlobFetcher = struct {
    state: *void,
    fetch_fn: fn (*void, []const u8, usize) GitError!void,
};


const TreeEntry = struct {
    mode: u32,

    name: []const u8,
    id: ObjectId,
    is_dir: bool,
};

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn idEql(a: ObjectId, b: ObjectId) bool {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn startsWith(s: []const u8, prefix: []const u8) bool {
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

fn lenAdd(a: usize, b: usize) !usize {
    if (a > 0xFFFFFFFF or b > 0xFFFFFFFF or a > 0xFFFFFFFF - b) return error.OutOfMemory;
    return a + b;
}

fn join2(arena: *arena_mod.Arena, a: []const u8, b: []const u8) GitError![]u8 {
    const n = lenAdd(a.len, b.len) catch return error.OutOfMemory;
    const raw = arena_mod.alloc(arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    i = 0;
    while (i < b.len) : (i += 1) raw[a.len + i] = b[i];
    return raw[0..n];
}

fn join3(arena: *arena_mod.Arena, a: []const u8, b: []const u8, c: []const u8) GitError![]u8 {
    const ab = lenAdd(a.len, b.len) catch return error.OutOfMemory;
    const n = lenAdd(ab, c.len) catch return error.OutOfMemory;
    const raw = arena_mod.alloc(arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    i = 0;
    while (i < b.len) : (i += 1) raw[a.len + i] = b[i];
    i = 0;
    while (i < c.len) : (i += 1) raw[ab + i] = c[i];
    return raw[0..n];
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

fn trimSpace(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and isSpace(s[start])) : (start += 1) {}
    var end: usize = s.len;
    while (end > start and isSpace(s[end - 1])) : (end -= 1) {}
    return s[start..end];
}

fn findByte(data: []const u8, start: usize, ch: u8) isize {
    var i: usize = start;
    while (i < data.len) : (i += 1) {
        if (data[i] == ch) return @intCast(isize, i);
    }
    return -1;
}

fn findSlice(data: []const u8, start: usize, needle: []const u8) isize {
    if (needle.len == 0) return @intCast(isize, start);
    if (data.len < needle.len) return -1;
    var i: usize = start;
    while (i + needle.len <= data.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (data[i + j] != needle[j]) break;
        }
        if (j == needle.len) return @intCast(isize, i);
    }
    return -1;
}

fn hexVal(c: u8) i32 {
    if (c >= '0' and c <= '9') return @intCast(i32, c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(i32, c - 'a') + 10;
    if (c >= 'A' and c <= 'F') return @intCast(i32, c - 'A') + 10;
    return -1;
}

fn hexOut(out: []u8, v: u8) void {
    const hi = v >> 4;
    const lo = v & 0x0F;
    out[0] = if (hi < 10) '0' + hi else 'a' + (hi - 10);
    out[1] = if (lo < 10) '0' + lo else 'a' + (lo - 10);
}

fn hexId(id: ObjectId, out: []u8) void {
    if (out.len < 40) return;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        hexOut(out[i * 2 .. i * 2 + 2], id[i]);
    }
}

fn parseId(s: []const u8, out: *ObjectId) bool {
    if (s.len < 40) return false;
    var id: ObjectId = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const hi = hexVal(s[i * 2]);
        const lo = hexVal(s[i * 2 + 1]);
        if (hi < 0 or lo < 0) return false;
        id[i] = @intCast(u8, hi * 16 + lo);
    }
    copyId(out, id);
    return true;
}

fn copyId(dst: *ObjectId, src: ObjectId) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) dst[i] = src[i];
}

fn makeResolved(id: ObjectId, ref_name: []const u8) Resolved {
    var r: Resolved = undefined;
    copyId(&r.id, id);
    r.ref_name = ref_name;
    return r;
}

fn parseIdParts(dir: []const u8, name: []const u8, out: *ObjectId) bool {
    if (dir.len != 2 or name.len != 38) return false;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        var a: u8 = undefined;
        var b: u8 = undefined;
        if (i == 0) {
            a = dir[0];
            b = dir[1];
        } else {
            a = name[(i - 1) * 2];
            b = name[(i - 1) * 2 + 1];
        }
        const hi = hexVal(a);
        const lo = hexVal(b);
        if (hi < 0 or lo < 0) return false;
        out[i] = @intCast(u8, hi * 16 + lo);
    }
    return true;
}

fn nullVoid() *void {
    return @ptrCast(*void, @intToPtr(*void, 0));
}

fn cstr(path: []const u8, buf: []u8) bool {
    if (path.len + 1 > buf.len) return false;
    var i: usize = 0;
    while (i < path.len) : (i += 1) buf[i] = path[i];
    buf[path.len] = 0;
    return true;
}

fn isNull(p: *void) bool {
    return @ptrToInt(p) == 0;
}

// 0 = unresolved, 1 = resolved, 2 = unavailable.  Cached after the first call
// so kernel32 is looked up once; the handle stays loaded for the process.
var g_create_dir: CreateDirFn = undefined;
var g_remove_dir: RemoveDirFn = undefined;
var g_dir_api_state: u8 = 0;

fn resolveDirApi() void {
    if (g_dir_api_state != 0) return;
    g_dir_api_state = 2;
    if (!@isWindows()) return;
    var libbuf: [16]u8 = undefined;
    if (!cstr("kernel32.dll", libbuf[0..])) return;
    const lib = LoadLibraryA(@ptrCast([*]const u8, &libbuf[0]));
    if (isNull(lib)) return;
    var fnbuf: [32]u8 = undefined;
    if (!cstr("CreateDirectoryA", fnbuf[0..])) return;
    const create = GetProcAddress(lib, @ptrCast([*]const u8, &fnbuf[0]));
    if (isNull(create)) return;
    if (!cstr("RemoveDirectoryA", fnbuf[0..])) return;
    const remove = GetProcAddress(lib, @ptrCast([*]const u8, &fnbuf[0]));
    if (isNull(remove)) return;
    g_create_dir = @ptrCast(CreateDirFn, create);
    g_remove_dir = @ptrCast(RemoveDirFn, remove);
    g_dir_api_state = 1;
}

fn createDirWin(path: [*]const u8) i32 {
    resolveDirApi();
    if (g_dir_api_state != 1) return 0;
    return g_create_dir(path, nullVoid());
}

fn removeDirWin(path: [*]const u8) i32 {
    resolveDirApi();
    if (g_dir_api_state != 1) return 0;
    return g_remove_dir(path);
}

// Create one directory component; an existing directory is success.
fn makeDirOne(path: []const u8) GitError!void {
    if (path.len == 0) return;
    if (file_mod.exists(path)) return;
    var buf: [PATH_BUF]u8 = undefined;
    if (!cstr(path, buf[0..])) return error.Io;
    if (@isWindows()) {
        if (createDirWin(@ptrCast([*]const u8, &buf[0])) == 0) {
            if (file_mod.exists(path)) return;
            return error.Io;
        }
    } else {
        if (mkdir(@ptrCast([*]const u8, &buf[0]), 493) != 0) {
            if (file_mod.exists(path)) return;
            return error.Io;
        }
    }
}

// Best-effort removal of an empty directory.  A non-empty directory (for
// example one holding user-untracked files) is left in place: the tracked
// files inside it were already removed by removeTreePath, and checkout must
// not fail just because an untracked file keeps the directory alive.
fn removeDirIfEmpty(path: []const u8) void {
    if (!file_mod.exists(path)) return;
    var buf: [PATH_BUF]u8 = undefined;
    if (!cstr(path, buf[0..])) return;
    if (@isWindows()) {
        _ = removeDirWin(@ptrCast([*]const u8, &buf[0]));
    } else {
        _ = rmdir(@ptrCast([*]const u8, &buf[0]));
    }
}

// mkdir -p for '/'-separated paths (absolute POSIX paths and relative paths).
fn mkdirPath(path: []const u8) GitError!void {
    if (path.len == 0) return;
    var start: usize = 0;
    if (path[0] == '/') start = 1;
    var i: usize = start;
    while (i <= path.len) : (i += 1) {
        if (i == path.len or path[i] == '/' or path[i] == '\\') {
            if (i > 0) {
                const part = path[0..i];
                const drive = part.len == 2 and part[1] == ':';
                const root = part.len == 1 and (part[0] == '/' or part[0] == '\\');
                if (!(part.len == 0 or drive or root or eq(part, "."))) {
                    try makeDirOne(part);
                }
            }
        }
    }
}

fn copyFile(arena: *arena_mod.Arena, src: []const u8, dst: []const u8) GitError!void {
    var in = file_mod.open(arena, src, file_mod.Mode.Read) catch return error.Io;
    defer file_mod.close(&in);
    var out = file_mod.open(arena, dst, file_mod.Mode.Write) catch return error.Io;
    defer file_mod.close(&out);
    const cap: usize = 65536;
    const buf = g_copy_buf[0..cap];
    while (true) {
        const n = file_mod.read(&in, buf) catch return error.Io;
        if (n == 0) break;
        var off: usize = 0;
        while (off < n) {
            const w = file_mod.write(&out, buf[off..n]) catch return error.Io;
            if (w == 0) return error.Io;
            off += w;
        }
    }
    file_mod.flush(&out) catch return error.Io;
}

fn copyTree(arena: *arena_mod.Arena, src_dir: []const u8, dst_dir: []const u8) GitError!void {
    try mkdirPath(dst_dir);
    var d = file_mod.openDir(arena, src_dir) catch return error.Io;
    defer file_mod.closeDir(&d);
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch return error.Io;
        const e = maybe orelse break;
        if (eq(e.name, ".") or eq(e.name, "..")) continue;
        const sp = try join3(arena, src_dir, "/", e.name);
        const dp = try join3(arena, dst_dir, "/", e.name);
        if (e.is_dir) {
            try copyTree(arena, sp, dp);
        } else {
            try copyFile(arena, sp, dp);
        }
    }
}

// --- disk preflight ---------------------------------------------------------
//
// The estimates are deliberately conservative heuristics: the pack is on disk
// already, but the worktree, the synthesized idx and the external-sort temp
// files need room too. A statvfs/GetDiskFreeSpace failure is treated as
// "unknown" and skips the check rather than fabricating a limit. Win9x FAT32
// volumes top out at 2-4 GiB and Linux 2.0/ext2 at ~2 GiB; the POSIX std_file
// layer itself is 64-bit, so a larger filesystem is not an app limitation.

const DISK_SLACK_BYTES: u64 = 16 * 1024 * 1024;
const U64_MAX: u64 = 0xFFFFFFFFFFFFFFFF;

fn leU32At(b: []const u8, off: usize) u32 {
    var v: u32 = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var mul: u32 = 1;
        var k: usize = 0;
        while (k < i) : (k += 1) mul = mul * 256;
        v += @intCast(u32, b[off + i]) * mul;
    }
    return v;
}

var g_get_disk_free: GetDiskFreeSpaceFn = undefined;
var g_disk_api_state: u8 = 0;

fn resolveDiskApi() void {
    if (g_disk_api_state != 0) return;
    g_disk_api_state = 2;
    if (!@isWindows()) return;
    var libbuf: [16]u8 = undefined;
    if (!cstr("kernel32.dll", libbuf[0..])) return;
    const lib = LoadLibraryA(@ptrCast([*]const u8, &libbuf[0]));
    if (isNull(lib)) return;
    var fnbuf: [24]u8 = undefined;
    if (!cstr("GetDiskFreeSpaceA", fnbuf[0..])) return;
    const fnp = GetProcAddress(lib, @ptrCast([*]const u8, &fnbuf[0]));
    if (isNull(fnp)) return;
    g_get_disk_free = @ptrCast(GetDiskFreeSpaceFn, fnp);
    g_disk_api_state = 1;
}

fn freeBytes(path: []const u8) ?u64 {
    if (@isWindows()) {
        resolveDiskApi();
        if (g_disk_api_state != 1) return null;
        var root: [8]u8 = undefined;
        if (path.len >= 2 and path[1] == ':') {
            root[0] = path[0];
            root[1] = ':';
            root[2] = '\\';
            root[3] = 0;
        } else {
            root[0] = 'C';
            root[1] = ':';
            root[2] = '\\';
            root[3] = 0;
        }
        var spc: u32 = 0;
        var bps: u32 = 0;
        var freec: u32 = 0;
        var totalc: u32 = 0;
        if (g_get_disk_free(@ptrCast([*]const u8, &root[0]), &spc, &bps, &freec, &totalc) == 0) {
            return null;
        }
        if (spc == 0 or bps == 0) return null;
        const per: u64 = @intCast(u64, spc) * @intCast(u64, bps);
        if (per == 0) return null;
        const fc: u64 = @intCast(u64, freec);
        if (fc > U64_MAX / per) return U64_MAX;
        return fc * per;
    } else {
        var cbuf: [PATH_BUF]u8 = undefined;
        if (!cstr(path, cbuf[0..])) return null;
        // i386 Linux without _FILE_OFFSET_BITS: 32-bit fsblkcnt_t fields,
        // so f_bsize @0, f_frsize @4, f_bavail @16 (the 64-bit LFS layout has
        // f_bavail @24 and is not used by the emitted build).
        var st: [256]u8 = undefined;
        if (statvfs(@ptrCast([*]const u8, &cbuf[0]), @ptrCast(*void, &st[0])) != 0) return null;
        const bsize: u64 = @intCast(u64, leU32At(st[0..], 0));
        var frsize: u64 = @intCast(u64, leU32At(st[0..], 4));
        if (frsize == 0) frsize = bsize;
        if (frsize == 0) return null;
        const avail: u64 = @intCast(u64, leU32At(st[0..], 16));
        if (avail > U64_MAX / frsize) return U64_MAX;
        return avail * frsize;
    }
}

pub fn diskPreflight(path: []const u8, need_bytes: u64) GitError!void {
    if (freeBytes(path)) |free| {
        if (need_bytes > free) return error.DiskFull;
    }
}

fn satAdd64(a: u64, b: u64) u64 {
    if (a > U64_MAX - b) return U64_MAX;
    return a + b;
}

fn satMul64(a: u64, b: u64) u64 {
    if (a != 0 and b > U64_MAX / a) return U64_MAX;
    return a * b;
}

// Pack + idx + external-sort temp + worktree estimate. `pack_bytes` is the
// actual pack size when known (or the HTTP Content-Length); `object_count` is
// the PACK header count (0 when unknown). Worktree bytes are approximated by the
// packed size plus a per-object allowance: the pack is a lower bound and very
// compressible packs can exceed it, but the object count now always contributes
// the idx/temp/checkout terms on the Content-Length path.
pub fn diskPreflightEstimate(path: []const u8, pack_bytes: u64, object_count: u64) GitError!void {
    const idx_bytes = satAdd64(2048, satMul64(object_count, 40));
    const temp_bytes = satMul64(object_count, 192);
    const worktree_bytes = satAdd64(pack_bytes, satMul64(object_count, 512));
    var need = satAdd64(pack_bytes, idx_bytes);
    need = satAdd64(need, temp_bytes);
    need = satAdd64(need, worktree_bytes);
    need = satAdd64(need, DISK_SLACK_BYTES);
    try diskPreflight(path, need);
}

fn readPackCount(arena: *arena_mod.Arena, path: []const u8) u64 {
    var f = file_mod.open(arena, path, file_mod.Mode.Read) catch return 0;
    var h: [12]u8 = undefined;
    var got: usize = 0;
    while (got < 12) {
        const n = file_mod.read(&f, h[got..12]) catch {
            file_mod.close(&f);
            return 0;
        };
        if (n == 0) break;
        got += n;
    }
    file_mod.close(&f);
    if (got < 12) return 0;
    if (h[0] != 'P' or h[1] != 'A' or h[2] != 'C' or h[3] != 'K') return 0;
    if (h[4] != 0 or h[5] != 0 or h[6] != 0 or h[7] != 2) return 0;
    var c: u64 = 0;
    var i: usize = 8;
    while (i < 12) : (i += 1) c = (c << 8) | @intCast(u64, h[i]);
    return c;
}

fn packDirStats(arena: *arena_mod.Arena, pack_dir: []const u8, bytes: *u64, count: *u64) void {
    bytes.* = 0;
    count.* = 0;
    if (!file_mod.exists(pack_dir)) return;
    var d = file_mod.openDir(arena, pack_dir) catch return;
    defer file_mod.closeDir(&d);
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch break;
        const e = maybe orelse break;
        if (e.is_dir or !endsWith(e.name, ".pack")) continue;
        const p = join3(arena, pack_dir, "/", e.name) catch continue;
        var f = file_mod.open(arena, p, file_mod.Mode.Read) catch continue;
        const sz = file_mod.size(&f) catch {
            file_mod.close(&f);
            continue;
        };
        file_mod.close(&f);
        if (sz > 0) {
            const s: u64 = @intCast(u64, sz);
            if (bytes.* > U64_MAX - s) {
                bytes.* = U64_MAX;
            } else {
                bytes.* += s;
            }
        }
        const c = readPackCount(arena, p);
        if (count.* > U64_MAX - c) {
            count.* = U64_MAX;
        } else {
            count.* += c;
        }
    }
}

fn copyPacks(arena: *arena_mod.Arena, src_pack_dir: []const u8, dst_pack_dir: []const u8) GitError!void {
    if (!file_mod.exists(src_pack_dir)) return;
    var d = file_mod.openDir(arena, src_pack_dir) catch return error.Io;
    defer file_mod.closeDir(&d);
    pack_mod.setTempDir(dst_pack_dir);
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch return error.Io;
        const e = maybe orelse break;
        if (e.is_dir or !endsWith(e.name, ".pack")) continue;
        const stem = e.name[0 .. e.name.len - 5];
        const idx_name = try join2(arena, stem, ".idx");
        const sp = try join3(arena, src_pack_dir, "/", e.name);
        const si = try join3(arena, src_pack_dir, "/", idx_name);
        const dp = try join3(arena, dst_pack_dir, "/", e.name);
        const di = try join3(arena, dst_pack_dir, "/", idx_name);
        var sf = file_mod.open(arena, sp, file_mod.Mode.Read) catch return error.Io;
        const ssz = file_mod.size(&sf) catch {
            file_mod.close(&sf);
            return error.Io;
        };
        file_mod.close(&sf);
        if (ssz > 0) {
            const sc = readPackCount(arena, sp);
            try diskPreflightEstimate(dst_pack_dir, @intCast(u64, ssz), sc);
        }
        try copyFile(arena, sp, dp);
        if (file_mod.exists(si)) {
            try copyFile(arena, si, di);
        } else {
            pack_mod.idxSynthesize(arena, dp, di) catch |ie| {
                file_mod.remove(dp) catch {};
                file_mod.remove(di) catch {};
                if (ie == error.OutOfMemory) return error.OutOfMemory;
                if (ie == error.WriteFailed) return error.DiskFull;
                if (ie == error.OpenFailed) return error.Io;
                if (ie == error.ReadFailed) return error.Io;
                return error.ObjectStore;
            };
        }
    }
}

fn looseBytes(arena: *arena_mod.Arena, src_git: []const u8) u64 {
    const src_objects = join2(arena, src_git, "/objects") catch return 0;
    if (!file_mod.exists(src_objects)) return 0;
    var d = file_mod.openDir(arena, src_objects) catch return 0;
    defer file_mod.closeDir(&d);
    var total: u64 = 0;
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch break;
        const e = maybe orelse break;
        if (!e.is_dir or e.name.len != 2) continue;
        if (eq(e.name, "pack") or eq(e.name, "info")) continue;
        const sp_dir = join3(arena, src_objects, "/", e.name) catch continue;
        var sd = file_mod.openDir(arena, sp_dir) catch continue;
        defer file_mod.closeDir(&sd);
        while (true) {
            const fmaybe = file_mod.readDir(arena, &sd) catch break;
            const f = fmaybe orelse break;
            if (f.is_dir or f.name.len != 38) continue;
            const sp = join3(arena, sp_dir, "/", f.name) catch continue;
            var sf = file_mod.open(arena, sp, file_mod.Mode.Read) catch continue;
            const sz = file_mod.size(&sf) catch {
                file_mod.close(&sf);
                continue;
            };
            file_mod.close(&sf);
            if (sz > 0) {
                const s: u64 = @intCast(u64, sz);
                total = satAdd64(total, s);
            }
        }
    }
    return total;
}

fn copyLoose(arena: *arena_mod.Arena, src_git: []const u8, dst_git: []const u8) GitError!void {
    const src_objects = try join2(arena, src_git, "/objects");
    if (!file_mod.exists(src_objects)) return;
    const loose_total = looseBytes(arena, src_git);
    if (loose_total > 0) {
        const loose_need = satAdd64(satMul64(loose_total, 2), DISK_SLACK_BYTES);
        try diskPreflight(dst_git, loose_need);
    }
    var d = file_mod.openDir(arena, src_objects) catch return error.Io;
    defer file_mod.closeDir(&d);
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch return error.Io;
        const e = maybe orelse break;
        if (!e.is_dir or e.name.len != 2) continue;
        if (eq(e.name, "pack") or eq(e.name, "info")) continue;
        const sp_dir = try join3(arena, src_objects, "/", e.name);
        var sd = file_mod.openDir(arena, sp_dir) catch return error.Io;
        defer file_mod.closeDir(&sd);
        var created = false;
        while (true) {
            const fmaybe = file_mod.readDir(arena, &sd) catch return error.Io;
            const f = fmaybe orelse break;
            if (f.is_dir or f.name.len != 38) continue;
            var id: ObjectId = undefined;
            if (!parseIdParts(e.name, f.name, &id)) continue;
            if (!created) {
                const dd = try join3(arena, dst_git, "/objects/", e.name);
                try mkdirPath(dd);
                created = true;
            }
            const sp = try join3(arena, sp_dir, "/", f.name);
            const dp = try objects.loosePath(arena, dst_git, id);
            try copyFile(arena, sp, dp);
        }
    }
}

fn copyMeta(arena: *arena_mod.Arena, head_dir: []const u8, common_dir: []const u8, dst_git: []const u8) GitError!void {
    const src_refs = try join2(arena, common_dir, "/refs");
    if (file_mod.exists(src_refs)) {
        const dst_refs = try join2(arena, dst_git, "/refs");
        try copyTree(arena, src_refs, dst_refs);
    }
    const src_head = try join2(arena, head_dir, "/HEAD");
    if (!file_mod.exists(src_head)) return error.ObjectStore;
    const dst_head = try join2(arena, dst_git, "/HEAD");
    try copyFile(arena, src_head, dst_head);
    const src_pr = try join2(arena, common_dir, "/packed-refs");
    if (file_mod.exists(src_pr)) {
        const dst_pr = try join2(arena, dst_git, "/packed-refs");
        try copyFile(arena, src_pr, dst_pr);
    }
    const src_shallow = try join2(arena, common_dir, "/shallow");
    if (file_mod.exists(src_shallow)) {
        const dst_shallow = try join2(arena, dst_git, "/shallow");
        try copyFile(arena, src_shallow, dst_shallow);
    }
}

// A linked worktree's gitdir carries a `commondir` file pointing at the main
// repository (objects/refs live there); HEAD stays in the worktree gitdir.
fn commonDir(arena: *arena_mod.Arena, git_dir: []const u8) GitError![]const u8 {
    const path = try join2(arena, git_dir, "/commondir");
    if (!file_mod.exists(path)) return git_dir;
    const raw = file_mod.readAll(arena, path) catch return error.Io;
    const s = trimSpace(raw);
    if (s.len == 0) return git_dir;
    const absolute = s[0] == '/' or (s.len >= 2 and s[1] == ':');
    if (absolute) return s;
    return try join3(arena, git_dir, "/", s);
}

fn dirExists(arena: *arena_mod.Arena, path: []const u8) bool {
    var d = file_mod.openDir(arena, path) catch return false;
    file_mod.closeDir(&d);
    return true;
}

fn sourceGitDir(arena: *arena_mod.Arena, src_path: []const u8, out: *[]const u8) GitError!void {
    const dotgit = try join2(arena, src_path, "/.git");
    if (file_mod.exists(dotgit)) {
        if (dirExists(arena, dotgit)) {
            out.* = dotgit;
            return;
        }
        const raw = file_mod.readAll(arena, dotgit) catch return error.Transport;
        const s = trimSpace(raw);
        if (!startsWith(s, "gitdir: ")) return error.Transport;
        const target = trimSpace(s[8..]);
        if (target.len == 0) return error.Transport;
        const absolute = target[0] == '/' or (target.len >= 2 and target[1] == ':');
        if (absolute) {
            out.* = target;
        } else {
            out.* = try join3(arena, src_path, "/", target);
        }
        return;
    }
    const head = try join2(arena, src_path, "/HEAD");
    const objs = try join2(arena, src_path, "/objects");
    if (file_mod.exists(head) and file_mod.exists(objs)) {
        out.* = src_path;
        return;
    }
    return error.Transport;
}

fn lookupPacked(arena: *arena_mod.Arena, git_dir: []const u8, name: []const u8, out: *Resolved) GitError!bool {
    const path = try join2(arena, git_dir, "/packed-refs");
    if (!file_mod.exists(path)) return false;
    const raw = file_mod.readAll(arena, path) catch return error.Io;
    var pos: usize = 0;
    while (pos < raw.len) {
        const eol = findByte(raw, pos, '\n');
        const end: usize = if (eol < 0) raw.len else @intCast(usize, eol);
        const line = trimSpace(raw[pos..end]);
        if (line.len != 0 and line[0] != '#') {
            const sp = findByte(line, 0, ' ');
            if (sp > 0) {
                const id_s = line[0..@intCast(usize, sp)];
                const name_s = trimSpace(line[@intCast(usize, sp) + 1 ..]);
                if (eq(name_s, name)) {
                    var id: ObjectId = undefined;
                    if (parseId(id_s, &id)) {
                        out.* = makeResolved(id, name);
                        return true;
                    }
                }
            }
        }
        if (eol < 0) break;
        pos = end + 1;
    }
    return false;
}

fn readNamedRef(arena: *arena_mod.Arena, git_dir: []const u8, name: []const u8, out: *Resolved, depth: usize) GitError!bool {
    if (depth > 16) return false;
    const path = try join3(arena, git_dir, "/", name);
    if (file_mod.exists(path)) {
        const raw = file_mod.readAll(arena, path) catch return error.Io;
        const s = trimSpace(raw);
        if (startsWith(s, "ref: ")) {
            const target = trimSpace(s[5..]);
            return readNamedRef(arena, git_dir, target, out, depth + 1);
        }
        var id: ObjectId = undefined;
        if (parseId(s, &id)) {
            out.* = makeResolved(id, name);
            return true;
        }
        return false;
    }
    return lookupPacked(arena, git_dir, name, out);
}

fn resolveHead(arena: *arena_mod.Arena, git_dir: []const u8, out: *Resolved) GitError!bool {
    const path = try join2(arena, git_dir, "/HEAD");
    if (!file_mod.exists(path)) return false;
    const raw = file_mod.readAll(arena, path) catch return error.Io;
    const s = trimSpace(raw);
    if (startsWith(s, "ref: ")) {
        const target = trimSpace(s[5..]);
        return readNamedRef(arena, git_dir, target, out, 0);
    }
    var id: ObjectId = undefined;
    if (parseId(s, &id)) {
        out.* = makeResolved(id, "");
        return true;
    }
    return false;
}

fn resolveUserRef(arena: *arena_mod.Arena, git_dir: []const u8, name: []const u8) GitError!Resolved {
    if (name.len == 0 or eq(name, "HEAD")) {
        var r: Resolved = undefined;
        if (!(try resolveHead(arena, git_dir, &r))) return error.Protocol;
        return r;
    }
    if (startsWith(name, "refs/")) {
        var r: Resolved = undefined;
        if (try readNamedRef(arena, git_dir, name, &r, 0)) return r;
    } else {
        var r: Resolved = undefined;
        if (try readNamedRef(arena, git_dir, name, &r, 0)) return r;
        const h = try join2(arena, "refs/heads/", name);
        if (try readNamedRef(arena, git_dir, h, &r, 0)) return r;
        const t = try join2(arena, "refs/tags/", name);
        if (try readNamedRef(arena, git_dir, t, &r, 0)) return r;
        const g = try join2(arena, "refs/", name);
        if (try readNamedRef(arena, git_dir, g, &r, 0)) return r;
    }
    var id: ObjectId = undefined;
    if (parseId(name, &id)) {
        return makeResolved(id, "");
    }
    return error.Protocol;
}

fn readTyped(arena: *arena_mod.Arena, store: *objects.Store, id: ObjectId, out: *objects.TypedObject) GitError!void {
    objects.storeReadTyped(arena, store, id, out) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.ObjectStore;
    };
}

fn openStore(arena: *arena_mod.Arena, git_dir: []const u8, store: *objects.Store) GitError!void {
    objects.storeOpen(arena, git_dir, store) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        if (e == error.Io) return error.Io;
        return error.ObjectStore;
    };
}

fn peelToCommit(arena: *arena_mod.Arena, store: *objects.Store, id: ObjectId, out: *ObjectId) GitError!void {
    var cur: ObjectId = undefined;
    copyId(&cur, id);
    var depth: usize = 0;
    while (depth < 16) : (depth += 1) {
        var obj: objects.TypedObject = undefined;
        try readTyped(arena, store, cur, &obj);
        defer objects.freeTyped(&obj);
        if (obj.ty == objects.ObjType.commit) {
            copyId(out, cur);
            return;
        }
        if (obj.ty == objects.ObjType.tag) {
            if (startsWith(obj.data, "object ")) {
                const eol = findByte(obj.data, 0, '\n');
                const end: usize = if (eol < 0) obj.data.len else @intCast(usize, eol);
                var next: ObjectId = undefined;
                if (parseId(trimSpace(obj.data[7..end]), &next)) {
                    copyId(&cur, next);
                    continue;
                }
            }
        }
        return error.Protocol;
    }
    return error.Protocol;
}

fn commitTree(arena: *arena_mod.Arena, store: *objects.Store, id: ObjectId, out: *ObjectId) GitError!void {
    var obj: objects.TypedObject = undefined;
    try readTyped(arena, store, id, &obj);
    defer objects.freeTyped(&obj);
    if (obj.ty != objects.ObjType.commit) return error.Protocol;
    if (!startsWith(obj.data, "tree ")) return error.Protocol;
    const eol = findByte(obj.data, 0, '\n');
    const end: usize = if (eol < 0) obj.data.len else @intCast(usize, eol);
    if (parseId(trimSpace(obj.data[5..end]), out)) return;
    return error.Protocol;
}

fn parseTree(arena: *arena_mod.Arena, data: []const u8) GitError![]TreeEntry {
    var count: usize = 0;
    var p: usize = 0;
    while (p < data.len) {
        const sp = findByte(data, p, ' ');
        if (sp < 0) return error.Protocol;
        const nul = findByte(data, @intCast(usize, sp) + 1, 0);
        if (nul < 0) return error.Protocol;
        const next = @intCast(usize, nul) + 1 + INDEX_ENTRY_BYTES;
        if (next > data.len) return error.Protocol;
        count += 1;
        p = next;
    }
    const raw = arena_mod.alloc(arena, count * @sizeOf(TreeEntry)) catch return error.OutOfMemory;
    const entries = @ptrCast([*]TreeEntry, raw)[0..count];
    p = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const sp = findByte(data, p, ' ');
        if (sp < 0) return error.Protocol;
        const nul = findByte(data, @intCast(usize, sp) + 1, 0);
        if (nul < 0) return error.Protocol;
        var mode: u32 = 0;
        var k: usize = p;
        while (k < @intCast(usize, sp)) : (k += 1) {
            const c = data[k];
            if (c < '0' or c > '7') return error.Protocol;
            mode = mode * 8 + @intCast(u32, c - '0');
        }
        var id: ObjectId = undefined;
        var j: usize = 0;
        while (j < 20) : (j += 1) id[j] = data[@intCast(usize, nul) + 1 + j];
        entries[i] = TreeEntry{
            .mode = mode,
            .name = data[@intCast(usize, sp) + 1 .. @intCast(usize, nul)],
            .id = id,
            .is_dir = mode == MODE_DIR,
        };
        p = @intCast(usize, nul) + 1 + INDEX_ENTRY_BYTES;
    }
    return entries;
}

fn goodName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (eq(name, ".") or eq(name, "..")) return false;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        if (name[i] == '/' or name[i] == '\\') return false;
    }
    return true;
}

fn findEntry(entries: []TreeEntry, name: []const u8) ?usize {
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (eq(entries[i].name, name)) return i;
    }
    return null;
}

// Preflight the whole target tree before checkout mutates anything.  A target
// path that exists in the worktree but is not in the previous HEAD tree is an
// untracked collision.  A tracked directory replaced by a file is refused
// (UnsupportedTransition) because removing a non-empty directory is not safe
// without an index.  File -> directory is allowed and turns into a remove +
// mkdir after this check.
fn preflightTree(arena: *arena_mod.Arena, scratch: *arena_mod.Arena, store: *objects.Store, has_old: bool, old_tree: ObjectId, new_tree: ObjectId, base: []const u8, depth: usize) GitError!void {
    if (depth > MAX_DEPTH) return error.Protocol;
    arena_mod.reset(scratch);
    var new_obj: objects.TypedObject = undefined;
    try readTyped(scratch, store, new_tree, &new_obj);
    if (new_obj.ty != objects.ObjType.tree) {
        objects.freeTyped(&new_obj);
        return error.Protocol;
    }
    const new_entries = parseTreeCopy(arena, new_obj.data) catch |e| {
        objects.freeTyped(&new_obj);
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Protocol;
    };
    objects.freeTyped(&new_obj);
    var old_entries: []TreeEntry = undefined;
    if (has_old) {
        arena_mod.reset(scratch);
        var old_obj: objects.TypedObject = undefined;
        try readTyped(scratch, store, old_tree, &old_obj);
        if (old_obj.ty != objects.ObjType.tree) {
            objects.freeTyped(&old_obj);
            return error.Protocol;
        }
        old_entries = parseTreeCopy(arena, old_obj.data) catch |e| {
            objects.freeTyped(&old_obj);
            if (e == error.OutOfMemory) return error.OutOfMemory;
            return error.Protocol;
        };
        objects.freeTyped(&old_obj);
    }
    arena_mod.reset(scratch);
    var i: usize = 0;
    while (i < new_entries.len) : (i += 1) {
        const new = new_entries[i];
        if (!goodName(new.name)) return error.Protocol;
        const path = try join3(arena, base, "/", new.name);
        var old_index: ?usize = null;
        if (has_old) old_index = findEntry(old_entries, new.name);
        if (old_index) |oi| {
            const old = old_entries[oi];
            const old_is_dir = old.is_dir or old.mode == MODE_GITLINK;
            const new_is_dir = new.is_dir or new.mode == MODE_GITLINK;
            if (old_is_dir and new_is_dir) {
                if (new.mode == MODE_GITLINK) {
                    // New empty submodule directory: no children to preflight.
                } else if (old.mode == MODE_GITLINK) {
                    // Empty gitlink directory replaced by a real tree: old is
                    // not a tree id, so preflight the new tree alone.
                    try preflightTree(arena, scratch, store, false, new.id, new.id, path, depth + 1);
                } else {
                    try preflightTree(arena, scratch, store, true, old.id, new.id, path, depth + 1);
                }
            } else if (old_is_dir and !new_is_dir) {
                if (old.mode == MODE_GITLINK) {
                    // Empty submodule directory replaced by a file/link.
                } else {
                    return error.UnsupportedTransition;
                }
            } else if (!old_is_dir and new_is_dir) {
                if (new.mode == MODE_GITLINK) {
                    // Empty directory replaces a file; removeAbsent/materialize
                    // handle the transition.
                } else {
                    try preflightTree(arena, scratch, store, false, new.id, new.id, path, depth + 1);
                }
            }
        } else {
            if (file_mod.exists(path)) return error.UntrackedCollision;
            if (new.is_dir) {
                try preflightTree(arena, scratch, store, false, new.id, new.id, path, depth + 1);
            }
        }
    }
}

fn parseTreeCopy(arena: *arena_mod.Arena, data: []const u8) GitError![]TreeEntry {
    var count: usize = 0;
    var p: usize = 0;
    while (p < data.len) {
        const sp = findByte(data, p, ' ');
        if (sp < 0) return error.Protocol;
        const nul = findByte(data, @intCast(usize, sp) + 1, 0);
        if (nul < 0) return error.Protocol;
        const next = @intCast(usize, nul) + 1 + INDEX_ENTRY_BYTES;
        if (next > data.len) return error.Protocol;
        count += 1;
        p = next;
    }
    const raw = arena_mod.alloc(arena, count * @sizeOf(TreeEntry)) catch return error.OutOfMemory;
    const entries = @ptrCast([*]TreeEntry, raw)[0..count];
    p = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const sp = findByte(data, p, ' ');
        if (sp < 0) return error.Protocol;
        const nul = findByte(data, @intCast(usize, sp) + 1, 0);
        if (nul < 0) return error.Protocol;
        var mode: u32 = 0;
        var k: usize = p;
        while (k < @intCast(usize, sp)) : (k += 1) {
            const c = data[k];
            if (c < '0' or c > '7') return error.Protocol;
            mode = mode * 8 + @intCast(u32, c - '0');
        }
        var id: ObjectId = undefined;
        var j: usize = 0;
        while (j < 20) : (j += 1) id[j] = data[@intCast(usize, nul) + 1 + j];
        const name_src = data[@intCast(usize, sp) + 1 .. @intCast(usize, nul)];
        const name_raw = arena_mod.alloc(arena, name_src.len) catch return error.OutOfMemory;
        j = 0;
        while (j < name_src.len) : (j += 1) name_raw[j] = name_src[j];
        entries[i] = TreeEntry{
            .mode = mode,
            .name = name_raw[0..name_src.len],
            .id = id,
            .is_dir = mode == MODE_DIR,
        };
        p = @intCast(usize, nul) + 1 + INDEX_ENTRY_BYTES;
    }
    return entries;
}

fn writeLink(path: []const u8, target: []const u8) GitError!void {
    // exists() follows symlinks, so a dangling link reports false and then
    // symlink() fails with EEXIST. Best-effort unlink (also a no-op when the
    // path is absent) removes a stale file or dangling link first.
    file_mod.remove(path) catch {};
    if (@isWindows()) {
        // Win9x has no symbolic links.  Write the target as a regular file,
        // the same representation Git for Windows uses with core.symlinks=false.
        file_mod.writeAll(path, target) catch return error.Io;
        return;
    }
    var pbuf: [PATH_BUF]u8 = undefined;
    var tbuf: [PATH_BUF]u8 = undefined;
    if (!cstr(path, pbuf[0..])) return error.Io;
    if (!cstr(target, tbuf[0..])) return error.Io;
    if (symlink(@ptrCast([*]const u8, &tbuf[0]), @ptrCast([*]const u8, &pbuf[0])) != 0) {
        return error.Io;
    }
}

fn checkoutScratchAlloc(arena: *arena_mod.Arena) ?[]u8 {
    var n = arena.capacity / 2;
    if (n > CHECKOUT_SCRATCH_MAX) n = CHECKOUT_SCRATCH_MAX;
    if (n < 64 * 1024) n = 64 * 1024;
    return pack_mod.dynAlloc(n);
}

const FileSinkState = struct {
    f: file_mod.File,
};

fn fileSinkWrite(state: *void, data: []const u8) !void {
    const s = @ptrCast(*FileSinkState, state);
    var off: usize = 0;
    while (off < data.len) {
        const n = file_mod.write(&s.f, data[off..]) catch return error.Io;
        if (n == 0) return error.Io;
        off += n;
    }
}

fn writeObjectToFile(scratch: *arena_mod.Arena, store: *objects.Store, id: ObjectId, path: []const u8) GitError!void {
    // exists() follows symlinks; a dangling link reports false but must still
    // be unlinked so the write does not recreate its target behind the link.
    file_mod.remove(path) catch {};
    const f = file_mod.open(scratch, path, file_mod.Mode.Write) catch return error.Io;
    var st = FileSinkState{ .f = f };
    var sink = objects.ObjectSink{ .state = @ptrCast(*void, &st), .write_fn = fileSinkWrite };
    objects.storeReadTo(scratch, store, id, &sink) catch |e| {
        file_mod.close(&st.f);
        if (e == error.OutOfMemory) return error.OutOfMemory;
        if (e == error.Io) return error.Io;
        return error.ObjectStore;
    };
    file_mod.flush(&st.f) catch {
        file_mod.close(&st.f);
        return error.Io;
    };
    file_mod.close(&st.f);
}

fn fetchMissingInTree(arena: *arena_mod.Arena, scratch: *arena_mod.Arena, store: *objects.Store, entries: []TreeEntry, fetcher: ?*BlobFetcher) GitError!void {
    const f = fetcher orelse return;
    const raw_ptr = arena_mod.alloc(arena, entries.len * 20) catch return error.OutOfMemory;
    const raw = raw_ptr[0 .. entries.len * 20];

    var count: usize = 0;
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (entries[i].is_dir or entries[i].mode == MODE_GITLINK) continue;
        arena_mod.reset(scratch);
        if (storeHas(scratch, store, entries[i].id)) continue;
        idToBytes(raw, count * 20, entries[i].id);
        count += 1;
    }
    if (count == 0) return;
    try f.fetch_fn(f.state, raw[0 .. count * 20], count);
}

fn prefetchTreeBlobs(arena: *arena_mod.Arena, scratch: *arena_mod.Arena, store: *objects.Store, tree_id: ObjectId, fetcher: *BlobFetcher, depth: usize) GitError!void {
    if (depth > MAX_DEPTH) return error.Protocol;
    arena_mod.reset(scratch);
    var obj: objects.TypedObject = undefined;
    try readTyped(scratch, store, tree_id, &obj);
    if (obj.ty != objects.ObjType.tree) {
        objects.freeTyped(&obj);
        return error.Protocol;
    }
    var tmp_bytes = obj.data.len * 4 + 8192;
    if (tmp_bytes < 65536) tmp_bytes = 65536;
    if (tmp_bytes > 64 * 1024 * 1024) tmp_bytes = 64 * 1024 * 1024;
    const tmp_raw = pack_mod.dynAlloc(tmp_bytes) orelse {
        objects.freeTyped(&obj);
        return error.OutOfMemory;
    };
    var tmp = arena_mod.init(tmp_raw[0..tmp_bytes]);
    const entries = parseTreeCopy(&tmp, obj.data) catch |e| {
        objects.freeTyped(&obj);
        pack_mod.dynFree(tmp_raw);
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Protocol;
    };
    objects.freeTyped(&obj);
    arena_mod.reset(scratch);
    try fetchMissingInTree(arena, scratch, store, entries, fetcher);
    const child_raw = pack_mod.dynAlloc(entries.len * 20 + 1) orelse {
        pack_mod.dynFree(tmp_raw);
        return error.OutOfMemory;
    };
    defer pack_mod.dynFree(child_raw);
    var child_count: usize = 0;
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        if (entries[i].is_dir) {
            idToBytes(child_raw, child_count * 20, entries[i].id);
            child_count += 1;
        }
    }
    pack_mod.dynFree(tmp_raw);
    i = 0;
    while (i < child_count) : (i += 1) {
        var cid: ObjectId = undefined;
        idFromBytes(child_raw, i * 20, &cid);
        try prefetchTreeBlobs(arena, scratch, store, cid, fetcher, depth + 1);
    }
}




fn materializeTreeWith(arena: *arena_mod.Arena, scratch: *arena_mod.Arena, store: *objects.Store, tree_id: ObjectId, base: []const u8, depth: usize, fetcher: ?*BlobFetcher) GitError!void {

    if (depth > MAX_DEPTH) return error.Protocol;
    arena_mod.reset(scratch);
    var obj: objects.TypedObject = undefined;
    try readTyped(scratch, store, tree_id, &obj);
    defer objects.freeTyped(&obj);
    if (obj.ty != objects.ObjType.tree) return error.Protocol;
    const entries = try parseTreeCopy(arena, obj.data);
    arena_mod.reset(scratch);
    try fetchMissingInTree(arena, scratch, store, entries, fetcher);
    try mkdirPath(base);

    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        const e = entries[i];
        if (!goodName(e.name)) return error.Protocol;
        const path = try join3(arena, base, "/", e.name);
        if (e.is_dir) {
            try materializeTreeWith(arena, scratch, store, e.id, path, depth + 1, fetcher);

        } else if (e.mode == MODE_GITLINK) {
            // Submodules are out of scope: leave an empty directory and never
            // fetch the referenced commit object. Remove any file or dangling
            // symlink at the path (exists() follows links) before mkdir.
            if (!dirExists(arena, path)) {
                file_mod.remove(path) catch {};
            }
            try mkdirPath(path);
        } else if (e.mode == MODE_LINK) {
            arena_mod.reset(scratch);
            var blob: objects.TypedObject = undefined;
            try readTyped(scratch, store, e.id, &blob);
            defer objects.freeTyped(&blob);
            if (blob.ty != objects.ObjType.blob) return error.Protocol;
            try writeLink(path, blob.data);
            arena_mod.reset(scratch);
        } else {
            arena_mod.reset(scratch);
            try writeObjectToFile(scratch, store, e.id, path);
            arena_mod.reset(scratch);
        }
    }
}
fn materializeTree(arena: *arena_mod.Arena, scratch: *arena_mod.Arena, store: *objects.Store, tree_id: ObjectId, base: []const u8, depth: usize) GitError!void {
    try materializeTreeWith(arena, scratch, store, tree_id, base, depth, null);
}


fn removeTrackedFile(path: []const u8) GitError!void {
    // Unlink unconditionally: exists() follows symlinks, so a dangling link
    // would otherwise be reported absent and left behind.
    file_mod.remove(path) catch {
        if (file_mod.exists(path)) return error.Io;
    };
}

fn removeTreePath(arena: *arena_mod.Arena, scratch: *arena_mod.Arena, store: *objects.Store, id: ObjectId, is_dir: bool, path: []const u8, depth: usize) GitError!void {
    if (depth > MAX_DEPTH) return error.Protocol;
    if (!is_dir) {
        try removeTrackedFile(path);
        return;
    }
    arena_mod.reset(scratch);
    var obj: objects.TypedObject = undefined;
    try readTyped(scratch, store, id, &obj);
    if (obj.ty != objects.ObjType.tree) {
        objects.freeTyped(&obj);
        return error.Protocol;
    }
    const entries = parseTreeCopy(arena, obj.data) catch |e| {
        objects.freeTyped(&obj);
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Protocol;
    };
    objects.freeTyped(&obj);
    arena_mod.reset(scratch);
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        const e = entries[i];
        if (!goodName(e.name)) return error.Protocol;
        const p = try join3(arena, path, "/", e.name);
        if (e.mode == MODE_GITLINK) {
            removeDirIfEmpty(p);
        } else {
            try removeTreePath(arena, scratch, store, e.id, e.is_dir, p, depth + 1);
        }
    }
    removeDirIfEmpty(path);
}

fn removeAbsent(arena: *arena_mod.Arena, scratch: *arena_mod.Arena, store: *objects.Store, old_tree: ObjectId, new_tree: ObjectId, base: []const u8, depth: usize) GitError!void {
    if (depth > MAX_DEPTH) return error.Protocol;
    if (idEql(old_tree, new_tree)) return;
    arena_mod.reset(scratch);
    var old_obj: objects.TypedObject = undefined;
    try readTyped(scratch, store, old_tree, &old_obj);
    if (old_obj.ty != objects.ObjType.tree) {
        objects.freeTyped(&old_obj);
        return error.Protocol;
    }
    const old_entries = parseTreeCopy(arena, old_obj.data) catch |e| {
        objects.freeTyped(&old_obj);
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Protocol;
    };
    objects.freeTyped(&old_obj);
    arena_mod.reset(scratch);
    var new_obj: objects.TypedObject = undefined;
    try readTyped(scratch, store, new_tree, &new_obj);
    if (new_obj.ty != objects.ObjType.tree) {
        objects.freeTyped(&new_obj);
        return error.Protocol;
    }
    const new_entries = parseTreeCopy(arena, new_obj.data) catch |e| {
        objects.freeTyped(&new_obj);
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.Protocol;
    };
    objects.freeTyped(&new_obj);
    arena_mod.reset(scratch);
    var i: usize = 0;
    while (i < old_entries.len) : (i += 1) {
        const old = old_entries[i];
        if (!goodName(old.name)) return error.Protocol;
        const path = try join3(arena, base, "/", old.name);
        if (findEntry(new_entries, old.name)) |ni| {
            const new = new_entries[ni];
            const old_is_dir = old.is_dir or old.mode == MODE_GITLINK;
            const new_is_dir = new.is_dir or new.mode == MODE_GITLINK;
            if (old_is_dir and new_is_dir) {
                if (new.mode == MODE_GITLINK) {
                    // Mode 160000 is an empty directory; never recurse into its
                    // commit id. A real old directory still needs its tracked
                    // files removed before the empty submodule dir is created.
                    if (old.mode != MODE_GITLINK) {
                        try removeTreePath(arena, scratch, store, old.id, old.is_dir, path, depth + 1);
                    }
                    removeDirIfEmpty(path);
                    try mkdirPath(path);
                } else if (old.mode == MODE_GITLINK) {
                    // Empty gitlink dir replaced by a real tree: drop the empty
                    // dir, then materialize the new tree.
                    removeDirIfEmpty(path);
                } else {
                    try removeAbsent(arena, scratch, store, old.id, new.id, path, depth + 1);
                }
            } else if (old_is_dir and !new_is_dir) {
                if (old.mode == MODE_GITLINK) {
                    // Empty submodule dir replaced by a file/link.
                    removeDirIfEmpty(path);
                } else {
                    return error.UnsupportedTransition;
                }
            } else if (!old_is_dir and new_is_dir) {
                try removeTrackedFile(path);
            }
        } else {
            if (old.mode == MODE_GITLINK) {
                removeDirIfEmpty(path);
            } else {
                try removeTreePath(arena, scratch, store, old.id, old.is_dir, path, depth + 1);
            }
        }
    }
}

fn worktreeRoot(arena: *arena_mod.Arena, git_dir: []const u8) GitError![]u8 {
    if (eq(git_dir, ".git")) return ".";
    if (endsWith(git_dir, "/.git")) {
        const raw = arena_mod.alloc(arena, git_dir.len - 5) catch return error.OutOfMemory;
        var i: usize = 0;
        while (i < git_dir.len - 5) : (i += 1) raw[i] = git_dir[i];
        if (git_dir.len - 5 == 0) return ".";
        return raw[0 .. git_dir.len - 5];
    }
    return ".";
}

fn updateHead(arena: *arena_mod.Arena, git_dir: []const u8, r: Resolved, commit: ObjectId) GitError!void {
    const path = try join2(arena, git_dir, "/HEAD");
    if (startsWith(r.ref_name, "refs/heads/")) {
        const content = try join3(arena, "ref: ", r.ref_name, "\n");
        file_mod.writeAll(path, content) catch return error.Io;
    } else {
        var buf: [41]u8 = undefined;
        hexId(commit, buf[0..40]);
        buf[40] = '\n';
        file_mod.writeAll(path, buf[0..41]) catch return error.Io;
    }
}

pub fn discover(arena: *arena_mod.Arena, out: *[]const u8) GitError!void {
    const cwd = os.cwd(arena) catch return error.Io;
    const cwd_ptr = cwd.ptr;
    var len: usize = cwd.len;
    var depth: usize = 0;
    while (depth < 256) : (depth += 1) {
        const dir = cwd_ptr[0..len];
        const dot = try join2(arena, dir, "/.git");
        if (file_mod.exists(dot)) {
            out.* = dot;
            return;
        }
        const head = try join2(arena, dir, "/HEAD");
        const objs = try join2(arena, dir, "/objects");
        if (file_mod.exists(head) and file_mod.exists(objs)) {
            out.* = dir;
            return;
        }
        var cut: usize = len;
        while (cut > 0) {
            if (cwd_ptr[cut - 1] == '/') break;
            cut -= 1;
        }
        if (cut <= 1) break;
        len = cut - 1;
        if (len == 0) break;
    }
    return error.ObjectStore;
}

pub const DiscoverResult = struct {
    ok: bool,
    git_dir: []const u8,
    code: i32,
    msg: []const u8,
};

pub fn discoverResult(arena: *arena_mod.Arena) DiscoverResult {
    var dir: []const u8 = undefined;
    discover(arena, &dir) catch |e| {
        return DiscoverResult{ .ok = false, .git_dir = "", .code = exitCode(e), .msg = errorMessage(e) };
    };
    return DiscoverResult{ .ok = true, .git_dir = dir, .code = 0, .msg = "" };
}

pub fn cloneLocal(arena: *arena_mod.Arena, src_path: []const u8, dest_dir: []const u8) GitError!void {
    var src_git: []const u8 = undefined;
    try sourceGitDir(arena, src_path, &src_git);
    const src_common = try commonDir(arena, src_git);
    try mkdirPath(dest_dir);
    const dest_git = try join2(arena, dest_dir, "/.git");
    try mkdirPath(dest_git);
    const dst_objects = try join2(arena, dest_git, "/objects");
    try mkdirPath(dst_objects);
    const dst_pack = try join2(arena, dst_objects, "/pack");
    try mkdirPath(dst_pack);
    const dst_refs = try join2(arena, dest_git, "/refs");
    try mkdirPath(dst_refs);

    const src_pack = try join2(arena, src_common, "/objects/pack");
    try copyPacks(arena, src_pack, dst_pack);
    try copyLoose(arena, src_common, dest_git);
    try copyMeta(arena, src_git, src_common, dest_git);

    var pack_bytes: u64 = 0;
    var pack_count: u64 = 0;
    packDirStats(arena, dst_pack, &pack_bytes, &pack_count);
    if (pack_bytes > 0) {
        try diskPreflightEstimate(dest_git, pack_bytes, pack_count);
    }

    var store: objects.Store = undefined;
    try openStore(arena, dest_git, &store);
    defer objects.storeClose(&store);

    var head: Resolved = undefined;
    if (!(try resolveHead(arena, dest_git, &head))) return error.ObjectStore;
    var commit: ObjectId = undefined;
    try peelToCommit(arena, &store, head.id, &commit);
    var tree: ObjectId = undefined;
    try commitTree(arena, &store, commit, &tree);
    const scratch_raw = checkoutScratchAlloc(arena) orelse return error.OutOfMemory;
    defer pack_mod.dynFree(scratch_raw);
    var scratch = arena_mod.init(scratch_raw[0..scratch_raw.len]);
    try materializeTree(arena, &scratch, &store, tree, dest_dir, 0);
}
pub fn prepareCloneDirs(arena: *arena_mod.Arena, dest_dir: []const u8) GitError![]const u8 {
    try mkdirPath(dest_dir);
    const dest_git = try join2(arena, dest_dir, "/.git");
    try mkdirPath(dest_git);
    const dst_objects = try join2(arena, dest_git, "/objects");
    try mkdirPath(dst_objects);
    const dst_pack = try join2(arena, dst_objects, "/pack");
    try mkdirPath(dst_pack);
    const dst_refs = try join2(arena, dest_git, "/refs");
    try mkdirPath(dst_refs);
    return dest_git;
}

pub const RefEntry = struct { name: []const u8, id: ObjectId };

fn refNameSafe(name: []const u8) bool {
    if (!startsWith(name, "refs/")) return false;
    if (name.len > 1024) return false;
    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        if (name[i] == '\\' or name[i] == ':' or name[i] == 0) return false;
    }
    var start: usize = 0;
    while (start <= name.len) {
        var end = start;
        while (end < name.len and name[end] != '/') : (end += 1) {}
        const comp = name[start..end];
        if (comp.len == 0 or eq(comp, ".") or eq(comp, "..")) return false;
        if (end == name.len) break;
        start = end + 1;
    }
    return true;
}

// Write the refs advertised by a smart-HTTP server, then a symbolic or
// detached HEAD. Task 8 calls this before checkoutHead.
pub fn installRefsOnly(arena: *arena_mod.Arena, dest_dir: []const u8, refs: []const RefEntry) GitError!void {
    const dest_git = try join2(arena, dest_dir, "/.git");
    try mkdirPath(dest_git);
    const dst_refs = try join2(arena, dest_git, "/refs");
    try mkdirPath(dst_refs);
    var i: usize = 0;
    while (i < refs.len) : (i += 1) {
        const r = refs[i];
        if (!refNameSafe(r.name)) return error.Protocol;
        const path = try join3(arena, dest_git, "/", r.name);
        var cut: usize = path.len;
        while (cut > 0) {
            if (path[cut - 1] == '/') break;
            cut -= 1;
        }
        if (cut == 0) return error.Protocol;
        try mkdirPath(path[0 .. cut - 1]);
        var buf: [41]u8 = undefined;
        hexId(r.id, buf[0..40]);
        buf[40] = '\n';
        file_mod.writeAll(path, buf[0..41]) catch return error.Io;
    }
}

pub fn installRefs(arena: *arena_mod.Arena, dest_dir: []const u8, refs: []const RefEntry, head_target: []const u8, head_id: ObjectId, has_head_id: bool) GitError!void {
    try installRefsOnly(arena, dest_dir, refs);
    const dest_git = try join2(arena, dest_dir, "/.git");
    const head_path = try join2(arena, dest_git, "/HEAD");
    if (startsWith(head_target, "refs/")) {
        const content = try join3(arena, "ref: ", head_target, "\n");
        file_mod.writeAll(head_path, content) catch return error.Io;
    } else if (has_head_id) {
        var buf: [41]u8 = undefined;
        hexId(head_id, buf[0..40]);
        buf[40] = '\n';
        file_mod.writeAll(head_path, buf[0..41]) catch return error.Io;
    } else {
        return error.Protocol;
    }
}


pub fn checkoutHeadWith(arena: *arena_mod.Arena, dest_dir: []const u8, fetcher: ?*BlobFetcher) GitError!void {

    const dest_git = try join2(arena, dest_dir, "/.git");
    const pack_dir = try join2(arena, dest_git, "/objects/pack");
    var pack_bytes: u64 = 0;
    var pack_count: u64 = 0;
    packDirStats(arena, pack_dir, &pack_bytes, &pack_count);
    if (pack_bytes > 0) {
        try diskPreflightEstimate(dest_git, pack_bytes, pack_count);
    }
    var store: objects.Store = undefined;
    try openStore(arena, dest_git, &store);
    defer objects.storeClose(&store);

    var head: Resolved = undefined;
    if (!(try resolveHead(arena, dest_git, &head))) return error.ObjectStore;
    var commit: ObjectId = undefined;
    try peelToCommit(arena, &store, head.id, &commit);
    var tree: ObjectId = undefined;
    try commitTree(arena, &store, commit, &tree);
    const scratch_raw = checkoutScratchAlloc(arena) orelse return error.OutOfMemory;
    defer pack_mod.dynFree(scratch_raw);
    var scratch = arena_mod.init(scratch_raw[0..scratch_raw.len]);
    if (fetcher) |f| {
        try prefetchTreeBlobs(arena, &scratch, &store, tree, f, 0);
        const gd = store.git_dir;
        objects.storeClose(&store);
        try openStore(arena, gd, &store);
    }
    try materializeTreeWith(arena, &scratch, &store, tree, dest_dir, 0, null);


}

pub fn checkoutHead(arena: *arena_mod.Arena, dest_dir: []const u8) GitError!void {
    try checkoutHeadWith(arena, dest_dir, null);
}


fn parseAuthor(s: []const u8, name: *[]const u8, ts: *i64, tz: *i64) void {
    name.* = s;
    ts.* = 0;
    tz.* = 0;
    const sp = findSlice(s, 0, " <");
    if (sp < 0) return;
    const si: usize = @intCast(usize, sp);
    if (si != 0) name.* = s[0..si];
    const gt = findSlice(s, si, "> ");
    if (gt < 0) return;
    var p: usize = @intCast(usize, gt) + 2;
    var neg = false;
    if (p < s.len and s[p] == '-') {
        neg = true;
        p += 1;
    }
    var v: i64 = 0;
    while (p < s.len) : (p += 1) {
        const c = s[p];
        if (c < '0' or c > '9') break;
        v = v * 10 + @intCast(i64, c - '0');
    }
    if (neg) v = -v;
    ts.* = v;
    while (p < s.len and s[p] == ' ') : (p += 1) {}
    if (p >= s.len) return;
    var sign: i64 = 1;
    if (s[p] == '-') {
        sign = -1;
        p += 1;
    } else if (s[p] == '+') {
        p += 1;
    }
    var hour: i64 = 0;
    var minute: i64 = 0;
    var digits: usize = 0;
    while (p < s.len and digits < 2) : (digits += 1) {
        const c = s[p];
        if (c < '0' or c > '9') return;
        hour = hour * 10 + @intCast(i64, c - '0');
        p += 1;
    }
    digits = 0;
    while (p < s.len and digits < 2) : (digits += 1) {
        const c = s[p];
        if (c < '0' or c > '9') return;
        minute = minute * 10 + @intCast(i64, c - '0');
        p += 1;
    }
    tz.* = sign * (hour * 3600 + minute * 60);
}

fn append(out: []u8, n: *usize, s: []const u8) void {
    if (n.* + s.len > out.len) return;
    var i: usize = 0;
    while (i < s.len) : (i += 1) out[n.* + i] = s[i];
    n.* += s.len;
}

fn appendChar(out: []u8, n: *usize, c: u8) void {
    if (n.* >= out.len) return;
    out[n.*] = c;
    n.* += 1;
}

fn appendDec(out: []u8, n: *usize, value: i64, width: usize) void {
    var tmp: [32]u8 = undefined;
    var count: usize = 0;
    var v = value;
    if (v == 0) {
        tmp[0] = '0';
        count = 1;
    } else {
        while (v > 0) : (v = v / 10) {
            tmp[count] = @intCast(u8, v % 10) + '0';
            count += 1;
        }
    }
    while (count < width) : (count += 1) tmp[count] = '0';
    var i: usize = count;
    while (i > 0) : (i -= 1) appendChar(out, n, tmp[i - 1]);
}

fn floorDiv(a: i64, b: i64) i64 {
    var q = a / b;
    const r = a % b;
    if (r != 0 and ((r < 0) != (b < 0))) q -= 1;
    return q;
}

fn formatDate(out: []u8, secs: i64, tz_seconds: i64) usize {
    const local = secs + tz_seconds;
    const days = floorDiv(local, 86400);
    const sod = local - days * 86400;
    var z = days + 719468;
    const era = if (z >= 0) z / 146097 else (z - 146096) / 146097;
    const doe = z - era * 146097;
    const yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    var y = yoe + era * 400;
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp = (5 * doy + 2) / 153;
    const d = doy - (153 * mp + 2) / 5 + 1;
    const m = mp + (if (mp < 10) @as(i64, 3) else @as(i64, -9));
    if (m <= 2) y += 1;

    var n: usize = 0;
    appendDec(out, &n, y, 4);
    appendChar(out, &n, '-');
    appendDec(out, &n, m, 2);
    appendChar(out, &n, '-');
    appendDec(out, &n, d, 2);
    appendChar(out, &n, 'T');
    appendDec(out, &n, sod / 3600, 2);
    appendChar(out, &n, ':');
    appendDec(out, &n, (sod % 3600) / 60, 2);
    appendChar(out, &n, ':');
    appendDec(out, &n, sod % 60, 2);
    if (tz_seconds < 0) {
        appendChar(out, &n, '-');
    } else {
        appendChar(out, &n, '+');
    }
    const atz = if (tz_seconds < 0) -tz_seconds else tz_seconds;
    appendDec(out, &n, atz / 3600, 2);
    appendDec(out, &n, (atz % 3600) / 60, 2);
    return n;
}

fn writeOut(s: []const u8) void {
    if (s.len != 0) @stdoutWrite(s.ptr, s.len);
}

fn printCommit(id: ObjectId, data: []const u8) GitError!void {
    var author: []const u8 = "";
    var ts: i64 = 0;
    var tz: i64 = 0;
    var subject: []const u8 = "";
    var pos: usize = 0;
    while (pos < data.len) {
        const eol = findByte(data, pos, '\n');
        const end: usize = if (eol < 0) data.len else @intCast(usize, eol);
        if (end == pos) {
            const mstart = if (eol < 0) data.len else end + 1;
            const meol = findByte(data, mstart, '\n');
            const mend: usize = if (meol < 0) data.len else @intCast(usize, meol);
            subject = trimSpace(data[mstart..mend]);
            break;
        }
        const line = data[pos..end];
        if (startsWith(line, "author ")) {
            parseAuthor(line[7..], &author, &ts, &tz);
        }
        if (eol < 0) break;
        pos = end + 1;
    }
    var buf: [1024]u8 = undefined;
    var n: usize = 0;
    var hex: [40]u8 = undefined;
    hexId(id, hex[0..]);
    append(buf[0..], &n, hex[0..7]);
    appendChar(buf[0..], &n, ' ');
    append(buf[0..], &n, author);
    appendChar(buf[0..], &n, ' ');
    var date: [32]u8 = undefined;
    const dn = formatDate(date[0..], ts, tz);
    const needed: usize = 7 + 1 + author.len + 1 + dn + 1 + subject.len + 1;
    if (needed > buf.len) return error.Protocol;
    append(buf[0..], &n, date[0..dn]);
    appendChar(buf[0..], &n, ' ');
    append(buf[0..], &n, subject);
    appendChar(buf[0..], &n, '\n');
    writeOut(buf[0..n]);
}

fn parseParents(data: []const u8, out: []u8) !usize {
    var count: usize = 0;
    var pos: usize = 0;
    while (pos < data.len) {
        const eol = findByte(data, pos, '\n');
        const end: usize = if (eol < 0) data.len else @intCast(usize, eol);
        if (end == pos) break;
        if (end - pos >= 7 and startsWith(data[pos..end], "parent ")) {
            var id: ObjectId = undefined;
            if (parseId(data[pos + 7 .. end], &id)) {
                if (count >= out.len / 20) return error.Protocol;
                idToBytes(out, count * 20, id);
                count += 1;
            }
        }
        if (eol < 0) break;
        pos = end + 1;
    }
    return count;
}

fn idToBytes(dst: []u8, off: usize, id: ObjectId) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) dst[off + i] = id[i];
}

fn idFromBytes(src: []const u8, off: usize, out: *ObjectId) void {
    var i: usize = 0;
    while (i < 20) : (i += 1) out[i] = src[off + i];
}


fn visitedHas(seen: []u8, count: usize, id: ObjectId) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var same = true;
        var k: usize = 0;
        while (k < 20) : (k += 1) {
            if (seen[i * 20 + k] != id[k]) {
                same = false;
                break;
            }
        }
        if (same) return true;
    }
    return false;
}

fn parseTagTarget(data: []const u8, out: *ObjectId) bool {
    if (!startsWith(data, "object ")) return false;
    if (data.len < 47) return false;
    return parseId(data[7..47], out);
}

fn idInRaw(raw: []const u8, count: usize, id: ObjectId) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var same = true;
        var k: usize = 0;
        while (k < 20) : (k += 1) {
            if (raw[i * 20 + k] != id[k]) {
                same = false;
                break;
            }
        }
        if (same) return true;
    }
    return false;
}

// Read `.git/shallow` into packed 20-byte ids.  A missing file is an empty
// boundary; malformed lines are ignored so a partial write cannot wedge log.
pub fn readShallow(arena: *arena_mod.Arena, git_dir: []const u8, out_raw: *[]u8, out_count: *usize) GitError!void {
    out_count.* = 0;
    const zero = arena_mod.alloc(arena, 0) catch return error.OutOfMemory;
    out_raw.* = zero[0..0];
    const path = try join2(arena, git_dir, "/shallow");
    if (!file_mod.exists(path)) return;

    const data = file_mod.readAll(arena, path) catch return error.Io;
    var cap: usize = data.len / 41 + 1;
    if (cap == 0) cap = 1;
    const raw = arena_mod.alloc(arena, cap * 20) catch return error.OutOfMemory;
    var pos: usize = 0;
    var count: usize = 0;
    while (pos < data.len) {
        var end = pos;
        while (end < data.len and data[end] != '\n' and data[end] != '\r') : (end += 1) {}
        if (end - pos >= 40) {
            var id: ObjectId = undefined;
            if (parseId(data[pos .. pos + 40], &id)) {
                idToBytes(raw[0 .. cap * 20], count * 20, id);
                count += 1;
            }
        }
        pos = end;
        while (pos < data.len and (data[pos] == '\n' or data[pos] == '\r')) : (pos += 1) {}
    }
    out_raw.* = raw[0 .. cap * 20];
    out_count.* = count;
}

pub fn writeShallow(arena: *arena_mod.Arena, git_dir: []const u8, raw: []const u8, count: usize) GitError!void {
    const path = try join2(arena, git_dir, "/shallow");
    if (count == 0) {
        file_mod.remove(path) catch {};
        return;
    }
    const text = arena_mod.alloc(arena, count * 41) catch return error.OutOfMemory;
    var pos: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        var id: ObjectId = undefined;
        idFromBytes(raw, i * 20, &id);
        hexId(id, text[pos .. pos + 40]);
        text[pos + 40] = '\n';
        pos += 41;
    }
    file_mod.writeAll(path, text[0..pos]) catch return error.Io;
}


const LocalRefList = struct {
    items: []RefEntry,
    len: usize,
    cap: usize,
};

fn localRefFind(list: *const LocalRefList, name: []const u8) bool {
    var i: usize = 0;
    while (i < list.len) : (i += 1) {
        if (eq(list.items[i].name, name)) return true;
    }
    return false;
}

fn localRefAdd(arena: *arena_mod.Arena, list: *LocalRefList, name: []const u8, id: ObjectId) GitError!void {
    if (localRefFind(list, name)) return;
    if (list.len == list.cap) {
        var ncap = list.cap * 2;
        if (ncap == 0) ncap = 16;
        const raw = arena_mod.alloc(arena, ncap * @sizeOf(RefEntry)) catch return error.OutOfMemory;

        var i: usize = 0;
        const next = @ptrCast([*]RefEntry, raw)[0..ncap];

        i = 0;
        while (i < list.len) : (i += 1) next[i] = list.items[i];
        list.items = next;
        list.cap = ncap;
    }
    list.items[list.len].name = name;
    var k: usize = 0;
    while (k < 20) : (k += 1) list.items[list.len].id[k] = id[k];
    list.len += 1;
}

fn collectRefsDir(arena: *arena_mod.Arena, git_dir: []const u8, rel: []const u8, list: *LocalRefList) GitError!void {
    const path = try join3(arena, git_dir, "/", rel);
    var d = file_mod.openDir(arena, path) catch return;
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch break;
        const e = maybe orelse break;
        if (eq(e.name, ".") or eq(e.name, "..")) continue;
        const child_rel = try join3(arena, rel, "/", e.name);
        const child_path = try join3(arena, git_dir, "/", child_rel);
        if (e.is_dir) {
            try collectRefsDir(arena, git_dir, child_rel, list);
            continue;
        }
        const data = file_mod.readAll(arena, child_path) catch continue;
        const line = trimSpace(data);
        if (line.len < 40) continue;
        var id: ObjectId = undefined;
        if (!parseId(line[0..40], &id)) continue;
        try localRefAdd(arena, list, child_rel, id);
    }
    file_mod.closeDir(&d);
}

fn collectPackedRefs(arena: *arena_mod.Arena, git_dir: []const u8, list: *LocalRefList) GitError!void {
    const path = try join2(arena, git_dir, "/packed-refs");
    if (!file_mod.exists(path)) return;
    const data = file_mod.readAll(arena, path) catch return;
    var pos: usize = 0;
    while (pos < data.len) {
        var end = pos;
        while (end < data.len and data[end] != '\n') : (end += 1) {}
        const line = data[pos..end];
        pos = end + 1;
        if (line.len < 42) continue;
        if (line[0] == '#' or line[0] == '^') continue;
        if (line[40] != ' ') continue;
        var id: ObjectId = undefined;
        if (!parseId(line[0..40], &id)) continue;
        const name = line[41..];
        if (!startsWith(name, "refs/")) continue;
        try localRefAdd(arena, list, name, id);
    }
}

// Local refs are the only have/install authority.  Loose refs win over
// packed-refs; refs/pull/* are never installed by z9git.
pub fn localRefs(arena: *arena_mod.Arena, git_dir: []const u8) GitError![]RefEntry {
    const raw0 = arena_mod.alloc(arena, 16 * @sizeOf(RefEntry)) catch return error.OutOfMemory;
    var list = LocalRefList{
        .items = @ptrCast([*]RefEntry, raw0)[0..16],
        .len = 0,
        .cap = 16,
    };

    try collectRefsDir(arena, git_dir, "refs", &list);
    try collectPackedRefs(arena, git_dir, &list);
    var i: usize = 0;
    var out_len: usize = 0;
    while (i < list.len) : (i += 1) {
        if (startsWith(list.items[i].name, "refs/pull/")) continue;
        list.items[out_len] = list.items[i];
        out_len += 1;
    }
    return list.items[0..out_len];
}

fn shallowHas(raw: []const u8, count: usize, id: ObjectId) bool {
    return idInRaw(raw, count, id);
}



fn storeHas(arena: *arena_mod.Arena, s: *objects.Store, id: ObjectId) bool {
    const lp = objects.loosePath(arena, s.git_dir, id) catch return false;
    if (file_mod.exists(lp)) return true;
    var i: usize = 0;
    while (i < s.packs.len) : (i += 1) {
        const off = pack_mod.idxFind(&s.packs[i].idx, id) catch null;
        if (off != null) return true;
    }
    return false;
}

// True when every object reachable from `tip` is present locally.  In a partial
// clone blobs are intentionally absent, so `ignore_blobs` limits the check to
// the commit/tree closure the upload-pack `have` fallback can safely promise.


// True when every object reachable from `tip` is present locally.  Shallow
// boundaries are terminal for the parent walk.  In a partial clone blobs are
// intentionally absent, so `ignore_blobs` limits the check to the
// commit/tree closure the upload-pack `have` fallback can safely promise.
// Traversal overflow means "incomplete" (never Protocol).
pub fn closureComplete(arena: *arena_mod.Arena, git_dir: []const u8, tip: ObjectId, shallow_raw: []const u8, shallow_count: usize, ignore_blobs: bool) GitError!bool {
    const sraw = pack_mod.dynAlloc(16 * 1024 * 1024) orelse return error.OutOfMemory;
    defer pack_mod.dynFree(sraw);
    var sarena = arena_mod.init(sraw[0 .. 16 * 1024 * 1024]);
    var store: objects.Store = undefined;
    try openStore(&sarena, git_dir, &store);
    defer objects.storeClose(&store);

    const wraw = pack_mod.dynAlloc(8 * 1024 * 1024) orelse return error.OutOfMemory;
    defer pack_mod.dynFree(wraw);
    var work = arena_mod.init(wraw[0 .. 8 * 1024 * 1024]);

    const cap: usize = 65536;
    const stack_raw = pack_mod.dynAlloc(cap * 20) orelse return error.OutOfMemory;
    defer pack_mod.dynFree(stack_raw);
    const seen_raw = pack_mod.dynAlloc(cap * 20) orelse return error.OutOfMemory;
    defer pack_mod.dynFree(seen_raw);
    const stack = stack_raw[0 .. cap * 20];
    const seen = seen_raw[0 .. cap * 20];




    var sp: usize = 0;
    var seen_count: usize = 0;
    idToBytes(stack[0 .. cap * 20], sp * 20, tip);
    sp += 1;
    while (sp > 0) {
        sp -= 1;
        var id: ObjectId = undefined;
        idFromBytes(stack[0 .. cap * 20], sp * 20, &id);
        if (visitedHas(seen[0 .. cap * 20], seen_count, id)) continue;
        if (seen_count >= cap) return false;
        idToBytes(seen[0 .. cap * 20], seen_count * 20, id);
        seen_count += 1;

        arena_mod.reset(&work);
        var obj: objects.TypedObject = undefined;
        readTyped(&work, &store, id, &obj) catch return false;









        if (obj.ty == objects.ObjType.blob) {
            objects.freeTyped(&obj);
            continue;
        }
        if (obj.ty == objects.ObjType.commit) {
            var tree: ObjectId = undefined;
            commitTree(&work, &store, id, &tree) catch {

                objects.freeTyped(&obj);
                return false;
            };

            var parents: [32 * 20]u8 = undefined;
            const pc = parseParents(obj.data, parents[0..]) catch {
                objects.freeTyped(&obj);
                return false;


            };
            if (!shallowHas(shallow_raw, shallow_count, id)) {
                if (sp + pc + 1 > cap) {
                    objects.freeTyped(&obj);
                    return false;


                }
                var j: usize = 0;
                while (j < pc) : (j += 1) {
                    var pid: ObjectId = undefined;
                    idFromBytes(parents[0..], j * 20, &pid);
                    idToBytes(stack[0 .. cap * 20], sp * 20, pid);
                    sp += 1;
                }
            }
            if (sp + 1 > cap) {
                objects.freeTyped(&obj);
                return false;


            }
            idToBytes(stack[0 .. cap * 20], sp * 20, tree);
            sp += 1;
        } else if (obj.ty == objects.ObjType.tree) {
            const entries = parseTree(&work, obj.data) catch {





                objects.freeTyped(&obj);
                return false;


            };
            if (sp + entries.len > cap) {
                objects.freeTyped(&obj);
                return false;


            }
            var j: usize = 0;
            while (j < entries.len) : (j += 1) {
                if (entries[j].mode == MODE_GITLINK) continue;
                if (ignore_blobs and !entries[j].is_dir) continue;
                idToBytes(stack[0 .. cap * 20], sp * 20, entries[j].id);
                sp += 1;
            }
        } else {
            var target: ObjectId = undefined;
            if (!parseTagTarget(obj.data, &target)) {
                objects.freeTyped(&obj);
                return false;


            }
            if (sp + 1 > cap) {
                objects.freeTyped(&obj);
                return false;


            }
            idToBytes(stack[0 .. cap * 20], sp * 20, target);
            sp += 1;
        }
        objects.freeTyped(&obj);
    }

    return true;

}





fn appendHave(arena: *arena_mod.Arena, out_raw: *[]u8, out_len: *usize, out_cap: *usize, id: ObjectId) GitError!void {


    if (idInRaw(out_raw.*, out_len.*, id)) return;
    try idsAppend(arena, out_raw, out_len, out_cap, id);
}

// Haves come from local refs (or verified state candidates), never from the
// server advertisement.  A shallow boundary makes its commit's closure complete.
pub fn collectHaves(arena: *arena_mod.Arena, git_dir: []const u8, refs: []const RefEntry, shallow_raw: []const u8, shallow_count: usize, partial: bool, out_raw: *[]u8, out_count: *usize) GitError!void {



    var out_len: usize = 0;
    var out_cap: usize = 0;
    const zero = arena_mod.alloc(arena, 0) catch return error.OutOfMemory;
    out_raw.* = zero[0..0];
    var i: usize = 0;
    while (i < refs.len) : (i += 1) {
        if (!(try closureComplete(arena, git_dir, refs[i].id, shallow_raw, shallow_count, partial))) continue;

        try appendHave(arena, out_raw, &out_len, &out_cap, refs[i].id);
    }
    out_count.* = out_len;
}



pub fn verifyHaves(arena: *arena_mod.Arena, git_dir: []const u8, candidate_raw: []const u8, candidate_count: usize, shallow_raw: []const u8, shallow_count: usize, partial: bool, out_raw: *[]u8, out_count: *usize) GitError!void {



    var out_len: usize = 0;
    var out_cap: usize = 0;
    const zero = arena_mod.alloc(arena, 0) catch return error.OutOfMemory;
    out_raw.* = zero[0..0];
    var i: usize = 0;
    while (i < candidate_count) : (i += 1) {
        var id: ObjectId = undefined;
        idFromBytes(candidate_raw, i * 20, &id);
        if (!(try closureComplete(arena, git_dir, id, shallow_raw, shallow_count, partial))) continue;

        try appendHave(arena, out_raw, &out_len, &out_cap, id);
    }

    out_count.* = out_len;
}

// Only refs whose closure is locally complete may be installed.  An incomplete
// new/moved ref is left uninstalled instead of being written with missing
// objects.
pub fn filterRefsForInstall(arena: *arena_mod.Arena, git_dir: []const u8, refs: []const RefEntry, shallow_raw: []const u8, shallow_count: usize, partial: bool) GitError![]RefEntry {


    const raw = arena_mod.alloc(arena, refs.len * @sizeOf(RefEntry)) catch return error.OutOfMemory;
    const out = @ptrCast([*]RefEntry, raw)[0..refs.len];
    var n: usize = 0;
    var i: usize = 0;
    while (i < refs.len) : (i += 1) {
        if (!(try closureComplete(arena, git_dir, refs[i].id, shallow_raw, shallow_count, partial))) continue;

        out[n] = refs[i];
        n += 1;
    }
    return out[0..n];
}





fn idsAppend(arena: *arena_mod.Arena, buf: *[]u8, len: *usize, cap: *usize, id: ObjectId) GitError!void {
    if (len.* == cap.*) {
        var ncap = cap.* * 2;
        if (ncap == 0) ncap = 256;
        const raw = arena_mod.alloc(arena, ncap * 20) catch return error.OutOfMemory;
        var i: usize = 0;
        while (i < len.* * 20) : (i += 1) raw[i] = buf.*[i];
        buf.* = raw[0 .. ncap * 20];
        cap.* = ncap;
    }
    idToBytes(buf.*, len.* * 20, id);
    len.* += 1;
}

// Blob ids reachable from `ref_name`'s tree that are not present locally.  The
// partial-clone checkout uses this to request exactly the missing blobs.

pub fn logRef(arena: *arena_mod.Arena, git_dir: []const u8, ref_name: []const u8) GitError!void {

    var store: objects.Store = undefined;
    try openStore(arena, git_dir, &store);
    defer objects.storeClose(&store);

    const start_ref = try resolveUserRef(arena, git_dir, ref_name);
    var start: ObjectId = undefined;
    try peelToCommit(arena, &store, start_ref.id, &start);
    var shallow_raw: []u8 = undefined;
    var shallow_count: usize = 0;
    try readShallow(arena, git_dir, &shallow_raw, &shallow_count);

    const cap: usize = 65536;
    const stack = arena_mod.alloc(arena, cap * 20) catch return error.OutOfMemory;
    const seen = arena_mod.alloc(arena, cap * 20) catch return error.OutOfMemory;
    var sp: usize = 0;
    var seen_count: usize = 0;
    idToBytes(stack[0 .. cap * 20], sp * 20, start);
    sp += 1;
    while (sp > 0) {
        sp -= 1;
        var id: ObjectId = undefined;
        idFromBytes(stack[0 .. cap * 20], sp * 20, &id);
        if (visitedHas(seen[0 .. cap * 20], seen_count, id)) continue;
        if (seen_count >= cap) return error.Protocol;
        idToBytes(seen[0 .. cap * 20], seen_count * 20, id);
        seen_count += 1;
        var obj: objects.TypedObject = undefined;
        try readTyped(arena, &store, id, &obj);
        defer objects.freeTyped(&obj);
        if (obj.ty != objects.ObjType.commit) return error.Protocol;
        try printCommit(id, obj.data);
        if (idInRaw(shallow_raw, shallow_count, id)) continue;
        var parents: [32 * 20]u8 = undefined;
        const pc = parseParents(obj.data, parents[0..]) catch return error.Protocol;
        var j: usize = pc;
        while (j > 0) {
            j -= 1;
            if (sp >= cap) return error.Protocol;
            var parent_id: ObjectId = undefined;
            idFromBytes(parents[0..], j * 20, &parent_id);
            idToBytes(stack[0 .. cap * 20], sp * 20, parent_id);
            sp += 1;
        }


    }
}

pub fn checkoutRefWith(arena: *arena_mod.Arena, git_dir: []const u8, ref_name: []const u8, fetcher: ?*BlobFetcher) GitError!void {

    var store: objects.Store = undefined;
    try openStore(arena, git_dir, &store);
    defer objects.storeClose(&store);

    var old_head: Resolved = undefined;
    if (!(try resolveHead(arena, git_dir, &old_head))) return error.ObjectStore;
    var old_commit: ObjectId = undefined;
    try peelToCommit(arena, &store, old_head.id, &old_commit);
    var old_tree: ObjectId = undefined;
    try commitTree(arena, &store, old_commit, &old_tree);

    const target = try resolveUserRef(arena, git_dir, ref_name);
    var target_commit: ObjectId = undefined;
    try peelToCommit(arena, &store, target.id, &target_commit);
    var target_tree: ObjectId = undefined;
    try commitTree(arena, &store, target_commit, &target_tree);
    const root = try worktreeRoot(arena, git_dir);

    const scratch_raw = checkoutScratchAlloc(arena) orelse return error.OutOfMemory;
    defer pack_mod.dynFree(scratch_raw);
    var scratch = arena_mod.init(scratch_raw[0..scratch_raw.len]);
    try preflightTree(arena, &scratch, &store, true, old_tree, target_tree, root, 0);
    try removeAbsent(arena, &scratch, &store, old_tree, target_tree, root, 0);
    if (fetcher) |f| {
        try prefetchTreeBlobs(arena, &scratch, &store, target_tree, f, 0);
        const gd = store.git_dir;
        objects.storeClose(&store);
        try openStore(arena, gd, &store);
    }
    try materializeTreeWith(arena, &scratch, &store, target_tree, root, 0, null);


    try updateHead(arena, git_dir, target, target_commit);
}
pub fn checkoutRef(arena: *arena_mod.Arena, git_dir: []const u8, ref_name: []const u8) GitError!void {
    try checkoutRefWith(arena, git_dir, ref_name, null);
}


pub fn exitCode(e: GitError) i32 {
    if (e == error.Usage) return 1;
    if (e == error.Transport) return 2;
    if (e == error.Protocol) return 3;
    if (e == error.UntrackedCollision) return 3;
    if (e == error.UnsupportedTransition) return 3;
    if (e == error.ObjectStore) return 4;
    return 5;
}

pub fn errorMessage(e: GitError) []const u8 {
    if (e == error.Usage) return "z9git: usage error\n";
    if (e == error.Transport) return "z9git: transport error\n";
    if (e == error.Protocol) return "z9git: protocol error\n";
    if (e == error.UntrackedCollision) return "z9git: checkout would overwrite an untracked path\n";
    if (e == error.UnsupportedTransition) return "z9git: checkout cannot replace a tracked directory with a file\n";
    if (e == error.ObjectStore) return "z9git: object-store error\n";
    if (e == error.DiskFull) return "z9git: not enough free disk space for the pack, idx, temp files and worktree\n";
    if (e == error.Io) return "z9git: io error\n";
    return "z9git: out of memory\n";
}
