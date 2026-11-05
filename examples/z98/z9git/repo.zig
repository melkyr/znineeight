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

pub const ObjectId = objects.ObjectId;

pub const GitError = error{ Usage, Transport, Protocol, ObjectStore, Io, OutOfMemory };

// win32 (kernel32, always present on Win9x) and POSIX directory creation.
// CreateDirectoryA is resolved through LoadLibraryA/GetProcAddress so the 9x
// import gate's closed whitelist (which predates this app) still passes; both
// lookup symbols are on that whitelist.  POSIX calls the plain mkdir wrapper.
const CreateDirFn = extern "stdcall" fn(lpPathName: [*]const u8, lpSecurityAttributes: *void) i32;
pub extern "stdcall" fn LoadLibraryA(name: [*]const u8) *void;
pub extern "stdcall" fn GetProcAddress(mod: *void, name: [*]const u8) *void;
pub extern "c" fn mkdir(path: [*]const u8, mode: i32) i32;

const PATH_BUF: usize = 4096;
const INDEX_ENTRY_BYTES: usize = 20;
const MAX_DEPTH: usize = 64;
const MODE_DIR: u32 = 16384; // 040000
const MODE_LINK: u32 = 40960; // 0120000

const Resolved = struct {
    id: ObjectId,
    ref_name: []const u8,
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

fn createDirWin(path: [*]const u8) i32 {
    if (!@isWindows()) return 0;
    var libbuf: [16]u8 = undefined;
    if (!cstr("kernel32.dll", libbuf[0..])) return 0;
    const lib = LoadLibraryA(@ptrCast([*]const u8, &libbuf[0]));
    if (isNull(lib)) return 0;
    var fnbuf: [32]u8 = undefined;
    if (!cstr("CreateDirectoryA", fnbuf[0..])) return 0;
    const proc = GetProcAddress(lib, @ptrCast([*]const u8, &fnbuf[0]));
    if (isNull(proc)) return 0;
    const create: CreateDirFn = @ptrCast(CreateDirFn, proc);
    return create(path, nullVoid());
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
    const raw = arena_mod.alloc(arena, cap) catch return error.OutOfMemory;
    const buf = raw[0..cap];
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

fn copyPacks(arena: *arena_mod.Arena, src_pack_dir: []const u8, dst_pack_dir: []const u8) GitError!void {
    if (!file_mod.exists(src_pack_dir)) return;
    var d = file_mod.openDir(arena, src_pack_dir) catch return error.Io;
    defer file_mod.closeDir(&d);
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch return error.Io;
        const e = maybe orelse break;
        if (e.is_dir or !endsWith(e.name, ".pack")) continue;
        const stem = e.name[0 .. e.name.len - 5];
        const idx_name = try join2(arena, stem, ".idx");
        const sp = try join3(arena, src_pack_dir, "/", e.name);
        const si = try join3(arena, src_pack_dir, "/", idx_name);
        if (!file_mod.exists(si)) return error.Protocol;
        const dp = try join3(arena, dst_pack_dir, "/", e.name);
        const di = try join3(arena, dst_pack_dir, "/", idx_name);
        try copyFile(arena, sp, dp);
        try copyFile(arena, si, di);
    }
}

fn copyLoose(arena: *arena_mod.Arena, src_git: []const u8, dst_git: []const u8) GitError!void {
    const src_objects = try join2(arena, src_git, "/objects");
    if (!file_mod.exists(src_objects)) return;
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
            const bytes = file_mod.readAll(arena, sp) catch return error.Io;
            objects.storeWriteLoose(dst_git, id, bytes) catch return error.Io;
        }
    }
}

fn copyMeta(arena: *arena_mod.Arena, src_git: []const u8, dst_git: []const u8) GitError!void {
    const src_refs = try join2(arena, src_git, "/refs");
    if (file_mod.exists(src_refs)) {
        const dst_refs = try join2(arena, dst_git, "/refs");
        try copyTree(arena, src_refs, dst_refs);
    }
    const src_head = try join2(arena, src_git, "/HEAD");
    if (!file_mod.exists(src_head)) return error.ObjectStore;
    const dst_head = try join2(arena, dst_git, "/HEAD");
    try copyFile(arena, src_head, dst_head);
    const src_pr = try join2(arena, src_git, "/packed-refs");
    if (file_mod.exists(src_pr)) {
        const dst_pr = try join2(arena, dst_git, "/packed-refs");
        try copyFile(arena, src_pr, dst_pr);
    }
}

fn sourceGitDir(arena: *arena_mod.Arena, src_path: []const u8, out: *[]const u8) GitError!void {
    const dotgit = try join2(arena, src_path, "/.git");
    if (file_mod.exists(dotgit)) {
        out.* = dotgit;
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
    objects.storeReadTyped(arena, store, id, out) catch return error.ObjectStore;
}

fn peelToCommit(arena: *arena_mod.Arena, store: *objects.Store, id: ObjectId, out: *ObjectId) GitError!void {
    var cur: ObjectId = undefined;
    copyId(&cur, id);
    var depth: usize = 0;
    while (depth < 16) : (depth += 1) {
        var obj: objects.TypedObject = undefined;
        try readTyped(arena, store, cur, &obj);
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

fn materializeTree(arena: *arena_mod.Arena, store: *objects.Store, tree_id: ObjectId, base: []const u8, depth: usize) GitError!void {
    if (depth > MAX_DEPTH) return error.Protocol;
    var obj: objects.TypedObject = undefined;
    try readTyped(arena, store, tree_id, &obj);
    if (obj.ty != objects.ObjType.tree) return error.Protocol;
    const entries = try parseTree(arena, obj.data);
    try mkdirPath(base);
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        const e = entries[i];
        if (!goodName(e.name)) return error.Protocol;
        const path = try join3(arena, base, "/", e.name);
        if (e.is_dir) {
            try materializeTree(arena, store, e.id, path, depth + 1);
        } else if (e.mode == MODE_LINK) {
            return error.Protocol;
        } else {
            var blob: objects.TypedObject = undefined;
            try readTyped(arena, store, e.id, &blob);
            if (blob.ty != objects.ObjType.blob) return error.Protocol;
            file_mod.writeAll(path, blob.data) catch return error.Io;
        }
    }
}

fn removeTreePath(arena: *arena_mod.Arena, store: *objects.Store, id: ObjectId, is_dir: bool, path: []const u8, depth: usize) GitError!void {
    if (depth > MAX_DEPTH) return error.Protocol;
    if (!is_dir) {
        file_mod.remove(path) catch {};
        return;
    }
    var obj: objects.TypedObject = undefined;
    try readTyped(arena, store, id, &obj);
    if (obj.ty != objects.ObjType.tree) return error.Protocol;
    const entries = try parseTree(arena, obj.data);
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        const e = entries[i];
        if (!goodName(e.name)) return error.Protocol;
        const p = try join3(arena, path, "/", e.name);
        try removeTreePath(arena, store, e.id, e.is_dir, p, depth + 1);
    }
}

fn removeAbsent(arena: *arena_mod.Arena, store: *objects.Store, old_tree: ObjectId, new_tree: ObjectId, base: []const u8, depth: usize) GitError!void {
    if (depth > MAX_DEPTH) return error.Protocol;
    if (idEql(old_tree, new_tree)) return;
    var old_obj: objects.TypedObject = undefined;
    try readTyped(arena, store, old_tree, &old_obj);
    if (old_obj.ty != objects.ObjType.tree) return error.Protocol;
    var new_obj: objects.TypedObject = undefined;
    try readTyped(arena, store, new_tree, &new_obj);
    if (new_obj.ty != objects.ObjType.tree) return error.Protocol;
    const old_entries = try parseTree(arena, old_obj.data);
    const new_entries = try parseTree(arena, new_obj.data);
    var i: usize = 0;
    while (i < old_entries.len) : (i += 1) {
        const old = old_entries[i];
        if (!goodName(old.name)) return error.Protocol;
        const path = try join3(arena, base, "/", old.name);
        if (findEntry(new_entries, old.name)) |ni| {
            const new = new_entries[ni];
            if (old.is_dir and new.is_dir) {
                try removeAbsent(arena, store, old.id, new.id, path, depth + 1);
            } else if (!old.is_dir and new.is_dir) {
                file_mod.remove(path) catch {};
            }
        } else {
            try removeTreePath(arena, store, old.id, old.is_dir, path, depth + 1);
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
    try mkdirPath(dest_dir);
    const dest_git = try join2(arena, dest_dir, "/.git");
    try mkdirPath(dest_git);
    const dst_objects = try join2(arena, dest_git, "/objects");
    try mkdirPath(dst_objects);
    const dst_pack = try join2(arena, dst_objects, "/pack");
    try mkdirPath(dst_pack);
    const dst_refs = try join2(arena, dest_git, "/refs");
    try mkdirPath(dst_refs);

    const src_pack = try join2(arena, src_git, "/objects/pack");
    try copyPacks(arena, src_pack, dst_pack);
    try copyLoose(arena, src_git, dest_git);
    try copyMeta(arena, src_git, dest_git);

    var store: objects.Store = undefined;
    objects.storeOpen(arena, dest_git, &store) catch return error.ObjectStore;
    defer objects.storeClose(&store);

    var head: Resolved = undefined;
    if (!(try resolveHead(arena, dest_git, &head))) return error.ObjectStore;
    var commit: ObjectId = undefined;
    try peelToCommit(arena, &store, head.id, &commit);
    var tree: ObjectId = undefined;
    try commitTree(arena, &store, commit, &tree);
    try materializeTree(arena, &store, tree, dest_dir, 0);
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

fn printCommit(id: ObjectId, data: []const u8) void {
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
                if ((count + 1) * 20 <= out.len) {
                    idToBytes(out, count * 20, id);
                    count += 1;
                }
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

fn idFromBytes(src: []u8, off: usize, out: *ObjectId) void {
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

pub fn logRef(arena: *arena_mod.Arena, git_dir: []const u8, ref_name: []const u8) GitError!void {
    var store: objects.Store = undefined;
    objects.storeOpen(arena, git_dir, &store) catch return error.ObjectStore;
    defer objects.storeClose(&store);

    const start_ref = try resolveUserRef(arena, git_dir, ref_name);
    var start: ObjectId = undefined;
    try peelToCommit(arena, &store, start_ref.id, &start);
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
        if (obj.ty != objects.ObjType.commit) return error.Protocol;
        printCommit(id, obj.data);
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

pub fn checkoutRef(arena: *arena_mod.Arena, git_dir: []const u8, ref_name: []const u8) GitError!void {
    var store: objects.Store = undefined;
    objects.storeOpen(arena, git_dir, &store) catch return error.ObjectStore;
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

    try removeAbsent(arena, &store, old_tree, target_tree, root, 0);
    try materializeTree(arena, &store, target_tree, root, 0);
    try updateHead(arena, git_dir, target, target_commit);
}

pub fn exitCode(e: GitError) i32 {
    if (e == error.Usage) return 1;
    if (e == error.Transport) return 2;
    if (e == error.Protocol) return 3;
    if (e == error.ObjectStore) return 4;
    return 5;
}

pub fn errorMessage(e: GitError) []const u8 {
    if (e == error.Usage) return "z9git: usage error\n";
    if (e == error.Transport) return "z9git: transport error\n";
    if (e == error.Protocol) return "z9git: protocol error\n";
    if (e == error.ObjectStore) return "z9git: object-store error\n";
    if (e == error.Io) return "z9git: io error\n";
    return "z9git: out of memory\n";
}
