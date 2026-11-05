// objects.zig -- z9git object store: pack first, loose fallback.
//
// storeOpen scans <git-dir>/objects/pack/*.idx and opens the matching pack.
// storeReadTyped resolves an object id by first searching every pack index and
// then the loose layout objects/xx/yyyy...  Pack deltas are reconstructed
// recursively (OFS_DELTA by offset, REF_DELTA by id), so a REF_DELTA base may
// live in a different pack or loose (the hybrid fixture).  Every materialized
// object is checked against SHA-1("type len\0" + data); a mismatch is Corrupt.
//
// A fixed 16-entry memo cache, keyed by id and by (pack, offset), keeps delta
// chains from materializing the same base repeatedly.  All storage is arena
// bounded; the cache never frees, it only evicts by wrapping the fixed ring.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const crypto = @import("std_crypto.zig");
const deflate = @import("std_deflate.zig");
const pack_mod = @import("pack.zig");
const delta_mod = @import("delta.zig");

pub const ObjectId = [20]u8;

pub const ObjType = enum(u8) { commit, tree, blob, tag };

pub const TypedObject = struct {
    ty: ObjType,
    data: []const u8,
};

const CACHE_SLOTS: usize = 16;
const MAX_DELTA_DEPTH: usize = 64;
const MAX_LEN: usize = 0xFFFFFFFF;
const MAX_U64: u64 = 0xFFFFFFFFFFFFFFFF;

const CacheEntry = struct {
    valid: bool,
    has_id: bool,
    has_pos: bool,
    id: ObjectId,
    pack_i: usize,
    offset: u64,
    ty: ObjType,
    data: []const u8,
};

// Store owns one open read handle per pack until storeClose (or process exit).
// The slices/pointers point into the caller's arena; storeOpen does not copy
// pack payloads.  Task 7 may call storeClose after it has finished reading.
pub const Store = struct {
    arena: *arena_mod.Arena,
    git_dir: []const u8,
    packs: []pack_mod.Pack,
    cache: [CACHE_SLOTS]CacheEntry,
    cache_next: usize,
};

const Resolved = struct {
    ty: ObjType,
    data: []const u8,
};

fn idEql(a: ObjectId, b: ObjectId) bool {
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn typeName(ty: ObjType) []const u8 {
    if (ty == ObjType.commit) return "commit";
    if (ty == ObjType.tree) return "tree";
    if (ty == ObjType.blob) return "blob";
    return "tag";
}

fn tyFromKind(k: pack_mod.Kind) !ObjType {
    if (k == pack_mod.Kind.commit) return ObjType.commit;
    if (k == pack_mod.Kind.tree) return ObjType.tree;
    if (k == pack_mod.Kind.blob) return ObjType.blob;
    if (k == pack_mod.Kind.tag) return ObjType.tag;
    return error.Corrupt;
}

fn putDecimal(dst: []u8, value: u64) usize {
    var tmp: [20]u8 = undefined;
    var n: usize = 0;
    var v = value;
    if (v == 0) {
        dst[0] = '0';
        return 1;
    }
    while (v != 0) {
        tmp[n] = @intCast(u8, v % 10) + '0';
        n += 1;
        v = v / 10;
    }
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = tmp[n - 1 - i];
    return n;
}

fn objectId(ty: ObjType, data: []const u8, out: *ObjectId) void {
    var hdr: [40]u8 = undefined;
    const name = typeName(ty);
    var n: usize = 0;
    while (n < name.len) : (n += 1) hdr[n] = name[n];
    hdr[n] = ' ';
    n += 1;
    n += putDecimal(hdr[n..], @intCast(u64, data.len));
    hdr[n] = 0;
    n += 1;

    var h = crypto.sha1Init();
    crypto.sha1Update(&h, hdr[0..n]);
    crypto.sha1Update(&h, data);
    crypto.sha1Final(&h, out);
}

fn cacheFindId(s: *Store, id: ObjectId) ?*CacheEntry {
    var i: usize = 0;
    while (i < CACHE_SLOTS) : (i += 1) {
        const e = &s.cache[i];
        if (e.valid and e.has_id and idEql(e.id, id)) return e;
    }
    return null;
}

fn cacheFindPos(s: *Store, pack_i: usize, offset: u64) ?*CacheEntry {
    var i: usize = 0;
    while (i < CACHE_SLOTS) : (i += 1) {
        const e = &s.cache[i];
        if (e.valid and e.has_pos and e.pack_i == pack_i and e.offset == offset) return e;
    }
    return null;
}

fn cacheAdd(s: *Store, id: ObjectId, pack_i: usize, offset: u64, ty: ObjType, data: []const u8) void {
    const slot = s.cache_next % CACHE_SLOTS;
    s.cache_next += 1;
    const e = &s.cache[slot];
    e.valid = true;
    e.has_id = true;
    e.has_pos = true;
    var i: usize = 0;
    while (i < 20) : (i += 1) e.id[i] = id[i];
    e.pack_i = pack_i;
    e.offset = offset;
    e.ty = ty;
    e.data = data;
}

fn lenAdd(a: usize, b: usize) !usize {
    if (a > MAX_LEN or b > MAX_LEN or a > MAX_LEN - b) return error.OutOfMemory;
    return a + b;
}

fn join2(arena: *arena_mod.Arena, a: []const u8, b: []const u8) ![]u8 {
    const n = try lenAdd(a.len, b.len);
    const raw = arena_mod.alloc(arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    i = 0;
    while (i < b.len) : (i += 1) raw[a.len + i] = b[i];
    return raw[0..n];
}

fn join3(arena: *arena_mod.Arena, a: []const u8, b: []const u8, c: []const u8) ![]u8 {
    const ab = try lenAdd(a.len, b.len);
    const n = try lenAdd(ab, c.len);
    const raw = arena_mod.alloc(arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    i = 0;
    while (i < b.len) : (i += 1) raw[a.len + i] = b[i];
    i = 0;
    while (i < c.len) : (i += 1) raw[ab + i] = c[i];
    return raw[0..n];
}

fn endsWith(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    var i: usize = 0;
    while (i < suffix.len) : (i += 1) {
        if (s[s.len - suffix.len + i] != suffix[i]) return false;
    }
    return true;
}

fn countIdx(s: *Store, pack_dir: []const u8) usize {
    var d = file_mod.openDir(s.arena, pack_dir) catch return 0;
    var n: usize = 0;
    while (true) {
        const maybe = file_mod.readDir(s.arena, &d) catch break;
        const e = maybe orelse break;
        if (!e.is_dir and endsWith(e.name, ".idx")) n += 1;
    }
    file_mod.closeDir(&d);
    return n;
}

fn copyIdPath(arena: *arena_mod.Arena, git_dir: []const u8, id: ObjectId) ![]u8 {
    const obj = try join2(arena, git_dir, "/objects/");
    var hex2: [2]u8 = undefined;
    var hex38: [38]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const v = id[i];
        const hi = v >> 4;
        const lo = v & 0x0F;
        if (i == 0) {
            hex2[0] = if (hi < 10) '0' + hi else 'a' + (hi - 10);
            hex2[1] = if (lo < 10) '0' + lo else 'a' + (lo - 10);
        } else {
            hex38[(i - 1) * 2] = if (hi < 10) '0' + hi else 'a' + (hi - 10);
            hex38[(i - 1) * 2 + 1] = if (lo < 10) '0' + lo else 'a' + (lo - 10);
        }
    }
    const with_dir = try join3(arena, obj, hex2[0..], "/");
    return join2(arena, with_dir, hex38[0..]);
}

pub fn storeOpen(arena: *arena_mod.Arena, git_dir: []const u8, s: *Store) !void {
    s.arena = arena;
    var i: usize = 0;
    while (i < CACHE_SLOTS) : (i += 1) {
        s.cache[i].valid = false;
        s.cache[i].has_id = false;
        s.cache[i].has_pos = false;
    }
    s.cache_next = 0;

    const raw_dir = arena_mod.alloc(arena, git_dir.len) catch return error.OutOfMemory;
    i = 0;
    while (i < git_dir.len) : (i += 1) raw_dir[i] = git_dir[i];
    s.git_dir = raw_dir[0..git_dir.len];

    const pack_dir = try join2(arena, s.git_dir, "/objects/pack");
    const count = countIdx(s, pack_dir);
    const packs_raw = arena_mod.alloc(arena, count * @sizeOf(pack_mod.Pack)) catch return error.OutOfMemory;
    s.packs = @ptrCast([*]pack_mod.Pack, packs_raw)[0..count];

    if (count == 0) return;

    var d = file_mod.openDir(arena, pack_dir) catch {
        s.packs = s.packs[0..0];
        return;
    };
    var filled: usize = 0;
    while (true) {
        const maybe = file_mod.readDir(arena, &d) catch break;
        const e = maybe orelse break;
        if (e.is_dir or !endsWith(e.name, ".idx")) continue;
        if (filled >= count) break;
        const idx_path = try join3(arena, pack_dir, "/", e.name);
        const idx = try pack_mod.idxLoad(arena, idx_path);
        const stem = e.name[0 .. e.name.len - 4];
        const pack_name = try join2(arena, stem, ".pack");
        const pack_path = try join3(arena, pack_dir, "/", pack_name);
        s.packs[filled] = try pack_mod.packOpen(arena, pack_path, idx);
        filled += 1;
    }
    file_mod.closeDir(&d);
    s.packs = s.packs[0..filled];
}

// Release the pack read handles.  Additive (the pinned API is unchanged);
// Task 7 can call this before reusing the same process for another repo.
pub fn storeClose(s: *Store) void {
    var i: usize = 0;
    while (i < s.packs.len) : (i += 1) {
        file_mod.close(&s.packs[i].file);
    }
    s.packs = s.packs[0..0];
}

fn verifyId(id: ObjectId, ty: ObjType, data: []const u8) !void {
    var got: ObjectId = undefined;
    objectId(ty, data, &got);
    if (!idEql(got, id)) return error.Corrupt;
}

fn applyDelta(arena: *arena_mod.Arena, base: Resolved, raw: pack_mod.RawEntry) !Resolved {
    var src_len: usize = 0;
    var tgt_len: usize = 0;
    try delta_mod.deltaSizes(raw.payload, &src_len, &tgt_len);
    if (src_len != base.data.len) return error.Corrupt;
    const out_raw = arena_mod.alloc(arena, tgt_len) catch return error.OutOfMemory;
    const out = out_raw[0..tgt_len];
    try delta_mod.deltaApply(base.data, raw.payload, out);
    return Resolved{ .ty = base.ty, .data = out };
}

fn resolveAt(arena: *arena_mod.Arena, s: *Store, pack_i: usize, offset: u64, expected: ObjectId, check_expected: bool, depth: usize) !Resolved {
    if (depth > MAX_DELTA_DEPTH) return error.Corrupt;
    if (cacheFindPos(s, pack_i, offset)) |e| {
        if (check_expected) {
            if (!e.has_id or !idEql(e.id, expected)) return error.Corrupt;
        }
        return Resolved{ .ty = e.ty, .data = e.data };
    }

    const raw = try pack_mod.readEntry(arena, &s.packs[pack_i], offset);
    var res: Resolved = undefined;

    if (raw.kind == pack_mod.Kind.ofs_delta) {
        const base = try resolveAt(arena, s, pack_i, raw.base_off, raw.base_id, false, depth + 1);
        res = try applyDelta(arena, base, raw);
    } else if (raw.kind == pack_mod.Kind.ref_delta) {
        const base = try readById(arena, s, raw.base_id, depth + 1);
        res = try applyDelta(arena, base, raw);
    } else {
        const ty = try tyFromKind(raw.kind);
        res = Resolved{ .ty = ty, .data = raw.payload };
    }

    var id: ObjectId = undefined;
    objectId(res.ty, res.data, &id);
    if (check_expected) {
        if (!idEql(id, expected)) return error.Corrupt;
    }
    cacheAdd(s, id, pack_i, offset, res.ty, res.data);
    return res;
}

fn inflateLoose(arena: *arena_mod.Arena, compressed: []const u8) ![]u8 {
    var cap: usize = 64 * 1024;
    while (true) {
        const raw = arena_mod.alloc(arena, cap) catch return error.OutOfMemory;
        var used: usize = 0;
        const got = deflate.inflateZlib(compressed, raw[0..cap], &used) catch |e| {
            if (e == error.OutputTooSmall) {
                if (cap >= 0x40000000) return error.OutOfMemory;
                cap = cap * 2;
                continue;
            }
            return error.Corrupt;
        };
        if (used > compressed.len) return error.Corrupt;
        return raw[0..@intCast(usize, got)];
    }
}

fn parseLoose(arena: *arena_mod.Arena, id: ObjectId, compressed: []const u8) !Resolved {
    const inflated = try inflateLoose(arena, compressed);
    var nul: usize = 0;
    while (nul < inflated.len and inflated[nul] != 0) : (nul += 1) {}
    if (nul >= inflated.len) return error.Corrupt;
    var sp: usize = 0;
    while (sp < nul and inflated[sp] != ' ') : (sp += 1) {}
    if (sp >= nul or sp == 0) return error.Corrupt;

    const tname = inflated[0..sp];
    var ty: ObjType = ObjType.blob;
    if (sp == 6 and tname[0] == 'c' and tname[1] == 'o' and tname[2] == 'm' and tname[3] == 'm' and tname[4] == 'i' and tname[5] == 't') {
        ty = ObjType.commit;
    } else if (sp == 4 and tname[0] == 't' and tname[1] == 'r' and tname[2] == 'e' and tname[3] == 'e') {
        ty = ObjType.tree;
    } else if (sp == 4 and tname[0] == 'b' and tname[1] == 'l' and tname[2] == 'o' and tname[3] == 'b') {
        ty = ObjType.blob;
    } else if (sp == 3 and tname[0] == 't' and tname[1] == 'a' and tname[2] == 'g') {
        ty = ObjType.tag;
    } else {
        return error.Corrupt;
    }

    var lenv: u64 = 0;
    var i: usize = sp + 1;
    if (i >= nul) return error.Corrupt;
    while (i < nul) : (i += 1) {
        const c = inflated[i];
        if (c < '0' or c > '9') return error.Corrupt;
        const d: u64 = @intCast(u64, c - '0');
        if (lenv > (MAX_U64 - d) / 10) return error.Corrupt;
        lenv = lenv * 10 + d;
    }
    const body = inflated[nul + 1 ..];
    if (lenv != @intCast(u64, body.len)) return error.Corrupt;
    try verifyId(id, ty, body);
    return Resolved{ .ty = ty, .data = body };
}

fn readLoose(arena: *arena_mod.Arena, s: *Store, id: ObjectId) !Resolved {
    const path = try copyIdPath(arena, s.git_dir, id);
    if (!file_mod.exists(path)) return error.NotFound;
    const compressed = file_mod.readAll(arena, path) catch return error.Corrupt;
    return parseLoose(arena, id, compressed);
}

pub fn readById(arena: *arena_mod.Arena, s: *Store, id: ObjectId, depth: usize) !Resolved {
    if (depth > MAX_DELTA_DEPTH) return error.Corrupt;
    if (cacheFindId(s, id)) |e| {
        return Resolved{ .ty = e.ty, .data = e.data };
    }
    var i: usize = 0;
    while (i < s.packs.len) : (i += 1) {
        if (pack_mod.idxFind(&s.packs[i].idx, id)) |off| {
            return try resolveAt(arena, s, i, off, id, true, depth);
        }
    }
    return try readLoose(arena, s, id);
}

pub fn storeReadTyped(arena: *arena_mod.Arena, s: *Store, id: ObjectId, out: *TypedObject) !void {
    const res = try readById(arena, s, id, 0);
    out.* = TypedObject{ .ty = res.ty, .data = res.data };
}

pub fn storeWriteLoose(git_dir: []const u8, id: ObjectId, zlib_bytes: []const u8) !void {
    var hex2: [2]u8 = undefined;
    var hex38: [38]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const v = id[i];
        const hi = v >> 4;
        const lo = v & 0x0F;
        if (i == 0) {
            hex2[0] = if (hi < 10) '0' + hi else 'a' + (hi - 10);
            hex2[1] = if (lo < 10) '0' + lo else 'a' + (lo - 10);
        } else {
            hex38[(i - 1) * 2] = if (hi < 10) '0' + hi else 'a' + (hi - 10);
            hex38[(i - 1) * 2 + 1] = if (lo < 10) '0' + lo else 'a' + (lo - 10);
        }
    }

    var buf: [4096]u8 = undefined;
    var n: usize = 0;
    i = 0;
    while (i < git_dir.len and n < buf.len - 1) : (i += 1) {
        buf[n] = git_dir[i];
        n += 1;
    }
    if (i != git_dir.len) return error.OpenFailed;
    var prefix: [9]u8 = [_]u8{ '/', 'o', 'b', 'j', 'e', 'c', 't', 's', '/' };
    i = 0;
    while (i < prefix.len and n < buf.len - 1) : (i += 1) {
        buf[n] = prefix[i];
        n += 1;
    }
    if (i != prefix.len) return error.OpenFailed;
    buf[n] = hex2[0];
    n += 1;
    buf[n] = hex2[1];
    n += 1;
    buf[n] = '/';
    n += 1;
    i = 0;
    while (i < 38 and n < buf.len - 1) : (i += 1) {
        buf[n] = hex38[i];
        n += 1;
    }
    if (i != 38) return error.OpenFailed;

    file_mod.writeAll(buf[0..n], zlib_bytes) catch return error.WriteFailed;
}
