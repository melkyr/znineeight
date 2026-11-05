// store_test.zig -- unit harness for the z9git pack/idx/loose object store.
//
// Build/run (repo root):
//   "$ZIG" -osl --output-dir "$OUT" examples/z98/z9git/tests/store_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/store_test"
//   "$OUT/store_test" examples/z98/z9git/tests <scratch>
//
// Arg 1 is the tests directory (contains testdata/ and goldens/); arg 2 is a
// scratch directory the harness pre-creates.  Prints one line per case plus a
// final pass/fail count; exits 1 on any failure.

const arena_mod = @import("std_arena.zig");
const file_mod = @import("std_file.zig");
const io = @import("std_io");
const os = @import("std_os");
const objects = @import("../objects.zig");
const delta = @import("../delta.zig");

const ARENA_BYTES: usize = 16 * 1024 * 1024;
const MAX_LEN: usize = 0xFFFFFFFF;

var arena_buf: [ARENA_BYTES]u8 = undefined;
var arena: arena_mod.Arena = undefined;

var test_dir: []const u8 = undefined;
var scratch_dir: []const u8 = undefined;

var passes: usize = 0;
var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
        passes += 1;
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn strEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn bytesEq(a: []const u8, b: []const u8) bool {
    return strEq(a, b);
}

fn lenAdd(a: usize, b: usize) !usize {
    if (a > MAX_LEN or b > MAX_LEN or a > MAX_LEN - b) return error.OutOfMemory;
    return a + b;
}

fn join2(a: []const u8, b: []const u8) ![]u8 {
    const n = try lenAdd(a.len, b.len);
    const raw = arena_mod.alloc(&arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    i = 0;
    while (i < b.len) : (i += 1) raw[a.len + i] = b[i];
    return raw[0..n];
}

fn join3(a: []const u8, b: []const u8, c: []const u8) ![]u8 {
    const ab = try lenAdd(a.len, b.len);
    const n = try lenAdd(ab, c.len);
    const raw = arena_mod.alloc(&arena, n) catch return error.OutOfMemory;
    var i: usize = 0;
    while (i < a.len) : (i += 1) raw[i] = a[i];
    i = 0;
    while (i < b.len) : (i += 1) raw[a.len + i] = b[i];
    i = 0;
    while (i < c.len) : (i += 1) raw[ab + i] = c[i];
    return raw[0..n];
}

fn hexVal(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return 0xFF;
}

fn parseId(s: []const u8, id: *[20]u8) bool {
    if (s.len != 40) return false;
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const hi = hexVal(s[i * 2]);
        const lo = hexVal(s[i * 2 + 1]);
        if (hi == 0xFF or lo == 0xFF) return false;
        id[i] = (hi << 4) | lo;
    }
    return true;
}

fn typeFromStr(s: []const u8, ty: *objects.ObjType) bool {
    if (strEq(s, "commit")) {
        ty.* = objects.ObjType.commit;
        return true;
    }
    if (strEq(s, "tree")) {
        ty.* = objects.ObjType.tree;
        return true;
    }
    if (strEq(s, "blob")) {
        ty.* = objects.ObjType.blob;
        return true;
    }
    if (strEq(s, "tag")) {
        ty.* = objects.ObjType.tag;
        return true;
    }
    return false;
}

const Record = struct {
    id: [20]u8,
    ty: objects.ObjType,
    data: []const u8,
};

// Cat-file --batch record: "<40hex> <type> <size>\n<bytes>\n".
fn nextRecord(g: []const u8, pos: *usize, rec: *Record) !bool {
    if (pos.* >= g.len) return false;
    var nl: usize = pos.*;
    while (nl < g.len and g[nl] != '\n') : (nl += 1) {}
    if (nl >= g.len) return error.Corrupt;
    const header = g[pos.*..nl];

    var sp1: usize = 0;
    while (sp1 < header.len and header[sp1] != ' ') : (sp1 += 1) {}
    if (sp1 >= header.len) return error.Corrupt;
    var sp2: usize = sp1 + 1;
    while (sp2 < header.len and header[sp2] != ' ') : (sp2 += 1) {}
    if (sp2 >= header.len) return error.Corrupt;

    if (!parseId(header[0..sp1], &rec.id)) return error.Corrupt;
    if (!typeFromStr(header[sp1 + 1 .. sp2], &rec.ty)) return error.Corrupt;

    var size: u64 = 0;
    var i: usize = sp2 + 1;
    if (i >= header.len) return error.Corrupt;
    while (i < header.len) : (i += 1) {
        const c = header[i];
        if (c < '0' or c > '9') return error.Corrupt;
        size = size * 10 + @intCast(u64, c - '0');
    }

    const start = nl + 1;
    if (size > @intCast(u64, g.len - start)) return error.Corrupt;
    const end = start + @intCast(usize, size);
    rec.data = g[start..end];
    if (end == g.len) {
        pos.* = end;
        return true;
    }
    if (g[end] != '\n') return error.Corrupt;
    pos.* = end + 1;
    return true;
}

fn openStore(repo: []const u8, s: *objects.Store) bool {
    objects.storeOpen(&arena, repo, s) catch return false;
    return true;
}

fn runGolden(golden_rel: []const u8, repo_subdir: []const u8) bool {
    arena_mod.reset(&arena);
    const repo = join3(test_dir, "/testdata/", repo_subdir) catch return false;
    const gpath = join3(test_dir, "/testdata/goldens/", golden_rel) catch return false;
    const g = file_mod.readAll(&arena, gpath) catch return false;

    var s: objects.Store = undefined;
    if (!openStore(repo, &s)) return false;

    var pos: usize = 0;
    var count: usize = 0;
    while (true) {
        var rec: Record = undefined;
        const more = nextRecord(g, &pos, &rec) catch return false;
        if (!more) break;

        var out: objects.TypedObject = undefined;
        objects.storeReadTyped(&arena, &s, rec.id, &out) catch return false;
        if (out.ty != rec.ty) return false;
        if (!bytesEq(out.data, rec.data)) return false;
        count += 1;
    }
    return count > 0;
}

fn loosePath(id: [20]u8) ![]u8 {
    const base = join2(scratch_dir, "/write_repo/objects/") catch return error.OutOfMemory;
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
    const with_dir = join3(base, hex2[0..], "/") catch return error.OutOfMemory;
    return join2(with_dir, hex38[0..]);
}

fn tPackedGolden() bool {
    return runGolden("packed.catfile", "packed_repo");
}

fn tLooseGolden() bool {
    return runGolden("loose.catfile", "loose_repo");
}

fn tOfsDeltas() bool {
    return runGolden("packed_ofs_deltas.catfile", "packed_repo");
}

fn tRefDeltas() bool {
    return runGolden("packed_ref_deltas.catfile", "packed_repo");
}

fn tHybrid() bool {
    return runGolden("hybrid.catfile", "hybrid_repo");
}

fn tLargeOffset() bool {
    return runGolden("large_offset.catfile", "large_offset_repo");
}

fn nextIdLine(g: []const u8, pos: *usize, id: *[20]u8) bool {
    const start = pos.*;
    if (start + 40 > g.len) return false;
    if (!parseId(g[start .. start + 40], id)) return false;
    pos.* = start + 40;
    if (pos.* < g.len and g[pos.*] == '\n') pos.* += 1;
    return true;
}

// Review Focus 5 through the store path: the target idx offset is encoded in
// the 8-byte large-offset table, the entry is a REF_DELTA, and its COPY
// instruction names source offset 0xFFFFFFFE with size 4.  A naive 32-bit
// offset+size would wrap to 2; storeReadTyped must surface error.Corrupt.
fn tLargeOffsetDeltaCorrupt() bool {
    arena_mod.reset(&arena);
    const ids_path = join3(test_dir, "/testdata/goldens/", "large_offset_delta.ids") catch return false;
    const ids = file_mod.readAll(&arena, ids_path) catch return false;
    var pos: usize = 0;
    var target_id: [20]u8 = undefined;
    var base_id: [20]u8 = undefined;
    if (!nextIdLine(ids, &pos, &target_id)) return false;
    if (!nextIdLine(ids, &pos, &base_id)) return false;

    const repo = join3(test_dir, "/testdata/", "large_offset_delta_repo") catch return false;
    var s: objects.Store = undefined;
    if (!openStore(repo, &s)) return false;

    // The normal base entry (ordinary 4-byte idx offset) must still read.
    var base_out: objects.TypedObject = undefined;
    objects.storeReadTyped(&arena, &s, base_id, &base_out) catch return false;
    if (base_out.ty != objects.ObjType.blob) return false;
    if (!strEq(base_out.data, "base")) return false;

    var out: objects.TypedObject = undefined;
    var got_corrupt = false;
    objects.storeReadTyped(&arena, &s, target_id, &out) catch |e| {
        if (e == error.Corrupt) got_corrupt = true;
    };
    return got_corrupt;
}

fn tWriteLoose() bool {
    arena_mod.reset(&arena);
    const gpath = join3(test_dir, "/testdata/goldens/", "loose.catfile") catch return false;
    const g = file_mod.readAll(&arena, gpath) catch return false;
    var pos: usize = 0;
    var rec: Record = undefined;
    const got = nextRecord(g, &pos, &rec) catch return false;
    if (!got) return false;

    const path = loosePath(rec.id) catch return false;
    const compressed = file_mod.readAll(&arena, path) catch return false;
    file_mod.remove(path) catch return false;
    if (file_mod.exists(path)) return false;

    const write_repo = join3(scratch_dir, "/", "write_repo") catch return false;
    objects.storeWriteLoose(write_repo, rec.id, compressed) catch return false;
    if (!file_mod.exists(path)) return false;

    var s: objects.Store = undefined;
    if (!openStore(write_repo, &s)) return false;
    var out: objects.TypedObject = undefined;
    objects.storeReadTyped(&arena, &s, rec.id, &out) catch return false;
    if (out.ty != rec.ty) return false;
    return bytesEq(out.data, rec.data);
}

fn tNotFound() bool {
    arena_mod.reset(&arena);
    const repo = join3(test_dir, "/testdata/", "packed_repo") catch return false;
    var s: objects.Store = undefined;
    if (!openStore(repo, &s)) return false;
    var id: [20]u8 = undefined;
    var i: usize = 0;
    while (i < 20) : (i += 1) id[i] = 0xAB;
    var out: objects.TypedObject = undefined;
    var found_not_found = false;
    objects.storeReadTyped(&arena, &s, id, &out) catch |e| {
        if (e == error.NotFound) found_not_found = true;
    };
    return found_not_found;
}

fn storeIsCorrupt(dir: []const u8) bool {
    var s: objects.Store = undefined;
    var got_corrupt = false;
    objects.storeOpen(&arena, dir, &s) catch |e| {
        if (e == error.Corrupt) got_corrupt = true;
    };
    return got_corrupt;
}

fn tMalformedIdx() bool {
    arena_mod.reset(&arena);
    const dir = join3(scratch_dir, "/", "bad_idx") catch return false;
    const path = join3(dir, "/objects/pack/", "bad.idx") catch return false;

    // Too short to contain even the v2 header + fanout + trailers.
    var junk: [17]u8 = undefined;
    var i: usize = 0;
    while (i < junk.len) : (i += 1) junk[i] = 0xFF;
    file_mod.writeAll(path, junk[0..]) catch return false;
    if (!storeIsCorrupt(dir)) return false;

    const src_packdir = join2(test_dir, "/testdata/packed_repo/objects/pack") catch return false;
    var idx_name: []const u8 = undefined;
    if (!(findFirstIdx(src_packdir, &idx_name) catch return false)) return false;
    const src_idx = join3(src_packdir, "/", idx_name) catch return false;

    // Valid length, altered magic.
    const magic_bad = file_mod.readAll(&arena, src_idx) catch return false;
    if (magic_bad.len < 8) return false;
    magic_bad[0] = magic_bad[0] ^ 0xFF;
    file_mod.writeAll(path, magic_bad) catch return false;
    if (!storeIsCorrupt(dir)) return false;

    // Valid length/magic, flipped idx trailer checksum byte.
    const trailer_bad = file_mod.readAll(&arena, src_idx) catch return false;
    if (trailer_bad.len < 20) return false;
    trailer_bad[trailer_bad.len - 1] = trailer_bad[trailer_bad.len - 1] ^ 0xFF;
    file_mod.writeAll(path, trailer_bad) catch return false;
    return storeIsCorrupt(dir);
}

fn findFirstIdx(dir: []const u8, out_name: *[]const u8) !bool {
    var d = file_mod.openDir(&arena, dir) catch return false;
    var found = false;
    while (true) {
        const maybe = file_mod.readDir(&arena, &d) catch break;
        const e = maybe orelse break;
        if (e.is_dir) continue;
        if (e.name.len >= 4 and strEq(e.name[e.name.len - 4 ..], ".idx")) {
            out_name.* = e.name;
            found = true;
            break;
        }
    }
    file_mod.closeDir(&d);
    return found;
}

fn tMalformedPack() bool {
    arena_mod.reset(&arena);
    const src_packdir = join2(test_dir, "/testdata/packed_repo/objects/pack") catch return false;
    var idx_name: []const u8 = undefined;
    if (!(findFirstIdx(src_packdir, &idx_name) catch return false)) return false;

    const src_idx = join3(src_packdir, "/", idx_name) catch return false;
    const idx_bytes = file_mod.readAll(&arena, src_idx) catch return false;
    const stem = idx_name[0 .. idx_name.len - 4];
    const pack_name = join2(stem, ".pack") catch return false;
    const src_pack = join3(src_packdir, "/", pack_name) catch return false;
    const pack_bytes = file_mod.readAll(&arena, src_pack) catch return false;
    if (pack_bytes.len == 0) return false;
    pack_bytes[pack_bytes.len - 1] = pack_bytes[pack_bytes.len - 1] ^ 0xFF;

    const dst_dir = join3(scratch_dir, "/", "bad_pack") catch return false;
    const dst_idx = join3(dst_dir, "/objects/pack/", idx_name) catch return false;
    const dst_pack = join3(dst_dir, "/objects/pack/", pack_name) catch return false;
    file_mod.writeAll(dst_idx, idx_bytes) catch return false;
    file_mod.writeAll(dst_pack, pack_bytes) catch return false;

    var s: objects.Store = undefined;
    var got_corrupt = false;
    objects.storeOpen(&arena, dst_dir, &s) catch |e| {
        if (e == error.Corrupt) got_corrupt = true;
    };
    return got_corrupt;
}

fn expectDeltaCorrupt(base: []const u8, delta_bytes: []const u8, out: []u8) bool {
    var got_corrupt = false;
    delta.deltaApply(base, delta_bytes, out) catch |e| {
        if (e == error.Corrupt) got_corrupt = true;
    };
    return got_corrupt;
}

fn tDeltaCopyInsert() bool {
    const base = "hello world";
    const payload = [_]u8{ 11, 17, 0x90, 6, 6, 'b', 'r', 'a', 'v', 'e', ' ', 0x91, 6, 5 };
    var out: [17]u8 = undefined;
    delta.deltaApply(base, payload[0..], out[0..]) catch return false;
    return strEq(out[0..], "hello brave world");
}

fn tDeltaOutOfRange() bool {
    // COPY offset 255 + size 3 from a 6-byte base must not wrap.
    const a = [_]u8{ 6, 3, 0x91, 0xFF, 0x03 };
    var out_a: [3]u8 = undefined;
    if (!expectDeltaCorrupt("abcdef", a[0..], out_a[0..])) return false;

    // Target overrun: COPY 6 into a 3-byte target.
    const b = [_]u8{ 6, 3, 0x90, 6 };
    var out_b: [3]u8 = undefined;
    if (!expectDeltaCorrupt("abcdef", b[0..], out_b[0..])) return false;

    // Declared source length larger than the supplied base.
    const c = [_]u8{ 7, 3, 0x90, 3 };
    var out_c: [3]u8 = undefined;
    return expectDeltaCorrupt("abcdef", c[0..], out_c[0..]);
}

fn tDeltaBadSrc() bool {
    // Overflowing delta size varint.  The out-of-range copy-offset case through
    // the pack/large-offset path is in tLargeOffsetDeltaCorrupt above.
    const a = [_]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x02 };
    var out_a: [4]u8 = undefined;
    return expectDeltaCorrupt("", a[0..], out_a[0..]);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    os.initArgs(argc, argv);
    if (os.argc() < 3) {
        io.write("usage: store_test <tests-dir> <scratch-dir>\n");
        os.exit(2);
    }
    test_dir = os.argv(1);
    scratch_dir = os.argv(2);
    arena = arena_mod.init(arena_buf[0..]);

    report("packed_lookup_golden", tPackedGolden());
    report("loose_lookup_golden", tLooseGolden());
    report("ofs_delta_chain", tOfsDeltas());
    report("ref_delta_pack", tRefDeltas());
    report("hybrid_ref_delta_across_loose", tHybrid());
    report("large_offset_idx_decode", tLargeOffset());
    report("large_offset_delta_corrupt", tLargeOffsetDeltaCorrupt());
    report("store_write_loose_roundtrip", tWriteLoose());
    report("missing_object_not_found", tNotFound());
    report("malformed_idx_corrupt", tMalformedIdx());
    report("malformed_pack_corrupt", tMalformedPack());
    report("delta_copy_insert", tDeltaCopyInsert());
    report("delta_out_of_range_copy", tDeltaOutOfRange());
    report("delta_bad_header", tDeltaBadSrc());

    io.write("PASS ");
    io.printInt(@intCast(i32, passes));
    io.write(" FAIL ");
    io.printInt(@intCast(i32, fails));
    io.write("\n");
    if (fails != 0) os.exit(1);
}
