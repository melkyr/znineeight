// residue_test.zig — deterministic unit harness for z9play residue.zig
// (M3 Task 3).
//
// Checks, all under `-fsafe`, exiting 0 on success / 1 on the first failure:
//   1. type 0: a crafted residue (begin 2, end 10, partition size 4,
//      classifications 2, classbook dim 1, one cascade stage) decodes into a
//      spectral vector of length 16 whose [2,10) bins are exactly the expected
//      interleaved partition values and whose [0,2) / [10,16) bins stay zero.
//   2. type 1: the same crafted packet decodes to the sequential layout.
//   3. type 2 (2 channels): the interleaved single-vector decode deinterleaves
//      correctly into the two channel rows.
//   4. type-0 end-of-packet handshake: an empty packet leaves every vector
//      zeroed (the first vector's classword read gates the decode); a one-byte
//      packet with only the first partition present decodes that partition but
//      leaves the next partition's range zero, and never reads past the packet.
//   5. 'do not decode': a channel marked unused is skipped in the bitstream and
//      left zero (type 0), and an all-'do not decode' type-2 bundle consumes no
//      bits and stays zero.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/residue_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const vs = @import("../vorbis_setup.zig");
const cbk = @import("../codebook.zig");
const res = @import("../residue.zig");

var arena_buf: [4 * 1024 * 1024]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "residue_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

// LSB-first packet writer (Vorbis bit packing, spec 2.1.4).
var pkt: [32]u8 = undefined;
var bp: usize = 0;

fn pktClear() void {
    var i: usize = 0;
    while (i < 32) : (i += 1) pkt[i] = 0;
    bp = 0;
}

fn wbits(n: u32, v: u32) void {
    var k: u32 = 0;
    while (k < n) : (k += 1) {
        var bit: u32 = (v >> k) & 1;
        if (bit == 1) {
            var sh: u32 = @intCast(u32, bp & 7);
            var b: u32 = @intCast(u32, pkt[bp >> 3]);
            b = b | (bit << sh);
            pkt[bp >> 3] = @intCast(u8, b & 0xff);
        }
        bp += 1;
    }
}

// Write a canonical codeword MSb-first: decodeScalar walks a codeword's bits
// from its MSb, so the stream order is bit(len-1) .. bit(0).
fn wcode(len: u32, val: u32) void {
    var k: u32 = len;
    while (k > 0) {
        k -= 1;
        var bit: u32 = (val >> k) & 1;
        wbits(1, bit);
    }
}

fn pktBytes() usize {
    return (bp + 7) / 8;
}

// Build the two crafted decode tables:
//   tables[0] — classbook: dim 1, 2 entries, length 1 each, no VQ mapping.
//   tables[1] — stage book: dim 2, 4 entries, length 2 each, explicit (type 2)
//               VQ mapping with values [1,2],[3,4],[5,6],[7,8].
fn makeBooks(arena: *std.arena.Arena, tables: []cbk.DecodeTable) void {
    var l0_raw: [*]u8 = std.arena.alloc(arena, 2) catch {
        fail("alloc l0");
        return;
    };
    var l0: []u8 = l0_raw[0..2];
    l0[0] = 1;
    l0[1] = 1;
    var e0_raw: [*]u8 = std.arena.alloc(arena, 0) catch {
        fail("alloc e0");
        return;
    };
    var e0: []u32 = @ptrCast([*]u32, e0_raw)[0..0];
    var cb0: vs.Codebook = vs.Codebook{
        .dimensions = 1,
        .entries = 2,
        .ordered = false,
        .sparse = false,
        .lengths = l0,
        .lookup_type = 0,
        .value_bits = 0,
        .sequence_p = false,
        .min_bits = 0,
        .delta_bits = 0,
        .lookup_values = 0,
        .multiplicands = e0,
    };
    tables[0] = cbk.buildDecodeTable(arena, cb0) catch {
        fail("build classbook");
        return;
    };

    var l1_raw: [*]u8 = std.arena.alloc(arena, 4) catch {
        fail("alloc l1");
        return;
    };
    var l1: []u8 = l1_raw[0..4];
    l1[0] = 2;
    l1[1] = 2;
    l1[2] = 2;
    l1[3] = 2;
    var mul_raw: [*]u8 = std.arena.alloc(arena, 8 * @sizeOf(u32)) catch {
        fail("alloc mul");
        return;
    };
    var mul: []u32 = @ptrCast([*]u32, mul_raw)[0..8];
    var mi: usize = 0;
    while (mi < 8) : (mi += 1) mul[mi] = @intCast(u32, mi + 1);
    // delta_value = float32_unpack(0x60100000) = 1.0 exactly; min_value = 0.
    var cb1: vs.Codebook = vs.Codebook{
        .dimensions = 2,
        .entries = 4,
        .ordered = false,
        .sparse = false,
        .lengths = l1,
        .lookup_type = 2,
        .value_bits = 4,
        .sequence_p = false,
        .min_bits = 0,
        .delta_bits = 0x60100000,
        .lookup_values = 8,
        .multiplicands = mul,
    };
    tables[1] = cbk.buildDecodeTable(arena, cb1) catch {
        fail("build stagebook");
        return;
    };
}

// Crafted residue: classifications 2, classbook 0, cascade bit 0 only for
// class 0, whose stage-0 book is codebook 1.
fn makeResidue(arena: *std.arena.Arena, rtype: u16, begin: u32, end: u32, psize: u32) vs.Residue {
    var cas_raw: [*]u8 = std.arena.alloc(arena, 2) catch {
        fail("alloc cascade");
        return undefined;
    };
    var cas: []u8 = cas_raw[0..2];
    cas[0] = 1;
    cas[1] = 0;
    var bk_raw: [*]u8 = std.arena.alloc(arena, 16 * @sizeOf(i16)) catch {
        fail("alloc books");
        return undefined;
    };
    var bk: []i16 = @ptrCast([*]i16, bk_raw)[0..16];
    var i: usize = 0;
    while (i < 16) : (i += 1) bk[i] = -1;
    bk[0] = 1;
    return vs.Residue{
        .residue_type = rtype,
        .begin = begin,
        .end = end,
        .partition_size = psize,
        .classifications = 2,
        .classbook = 0,
        .cascade = cas,
        .books = bk,
    };
}

fn makeOut(arena: *std.arena.Arena, ch: usize, len: usize) [][]f64 {
    var raw: [*]u8 = std.arena.alloc(arena, ch * @sizeOf([]f64)) catch {
        fail("alloc out rows");
        return undefined;
    };
    var rows: [][]f64 = @ptrCast([*][]f64, raw)[0..ch];
    var i: usize = 0;
    while (i < ch) : (i += 1) {
        var r_raw: [*]u8 = std.arena.alloc(arena, len * @sizeOf(f64)) catch {
            fail("alloc out row");
            return undefined;
        };
        rows[i] = @ptrCast([*]f64, r_raw)[0..len];
    }
    return rows;
}

fn checkRow(row: []f64, want: []const f64, msg: []const u8) void {
    if (row.len != want.len) {
        fail(msg);
        return;
    }
    var i: usize = 0;
    while (i < row.len) : (i += 1) {
        if (row[i] != want[i]) {
            fail(msg);
            return;
        }
    }
}

pub fn main() void {
    var arena = std.arena.init(arena_buf[0..]);

    var tables: [2]cbk.DecodeTable = undefined;
    makeBooks(&arena, tables[0..2]);

    // Common packet: group0 cls0, stage codewords for entries 0 and 1;
    // group1 cls0, stage codewords for entries 2 and 3.
    pktClear();
    wcode(1, 0);
    wcode(2, 0);
    wcode(2, 1);
    wcode(1, 0);
    wcode(2, 2);
    wcode(2, 3);
    var nb: usize = pktBytes();

    // --- 1. type 0 (interleaved) exact layout ---
    {
        var r: vs.Residue = makeResidue(&arena, 0, 2, 10, 4);
        var dnd: [1]bool = undefined;
        dnd[0] = false;
        var out: [][]f64 = makeOut(&arena, 1, 16);
        var br: vs.BitReader = vs.brInit(pkt[0..nb]);
        res.decodeResidue(&arena, tables[0..2], &br, r, dnd[0..1], 16, out) catch {
            fail("type0 decode error");
            return;
        };
        var want: [16]f64 = [16]f64{ 0, 0, 1, 3, 2, 4, 5, 7, 6, 8, 0, 0, 0, 0, 0, 0 };
        checkRow(out[0], want[0..16], "type0 layout");
    }

    // --- 2. type 1 (sequential) exact layout ---
    {
        var r: vs.Residue = makeResidue(&arena, 1, 2, 10, 4);
        var dnd: [1]bool = undefined;
        dnd[0] = false;
        var out: [][]f64 = makeOut(&arena, 1, 16);
        var br: vs.BitReader = vs.brInit(pkt[0..nb]);
        res.decodeResidue(&arena, tables[0..2], &br, r, dnd[0..1], 16, out) catch {
            fail("type1 decode error");
            return;
        };
        var want: [16]f64 = [16]f64{ 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 0, 0 };
        checkRow(out[0], want[0..16], "type1 layout");
    }

    // --- 3. type 2 (2 channels) interleave/deinterleave ---
    {
        var r: vs.Residue = makeResidue(&arena, 2, 0, 8, 4);
        var dnd: [2]bool = undefined;
        dnd[0] = false;
        dnd[1] = false;
        var out: [][]f64 = makeOut(&arena, 2, 4);
        var br: vs.BitReader = vs.brInit(pkt[0..nb]);
        res.decodeResidue(&arena, tables[0..2], &br, r, dnd[0..2], 4, out) catch {
            fail("type2 decode error");
            return;
        };
        var want0: [4]f64 = [4]f64{ 1, 3, 5, 7 };
        var want1: [4]f64 = [4]f64{ 2, 4, 6, 8 };
        checkRow(out[0], want0[0..4], "type2 ch0");
        checkRow(out[1], want1[0..4], "type2 ch1");
    }

    // --- 4a. empty packet: the first classword read gates the decode ---
    {
        var r: vs.Residue = makeResidue(&arena, 0, 2, 10, 4);
        var dnd: [1]bool = undefined;
        dnd[0] = false;
        var out: [][]f64 = makeOut(&arena, 1, 16);
        var empty: [1]u8 = [1]u8{0};
        var br: vs.BitReader = vs.brInit(empty[0..0]);
        res.decodeResidue(&arena, tables[0..2], &br, r, dnd[0..1], 16, out) catch {
            fail("empty decode error");
            return;
        };
        var want: [16]f64 = [16]f64{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        checkRow(out[0], want[0..16], "empty packet all zero");
    }

    // --- 4b. partial packet: group0 decodes, group1 runs past end-of-packet ---
    {
        pktClear();
        wcode(1, 0);
        wcode(2, 0);
        wcode(2, 1);
        var nb2: usize = pktBytes();
        var r: vs.Residue = makeResidue(&arena, 0, 2, 10, 4);
        var dnd: [1]bool = undefined;
        dnd[0] = false;
        var out: [][]f64 = makeOut(&arena, 1, 16);
        var br: vs.BitReader = vs.brInit(pkt[0..nb2]);
        res.decodeResidue(&arena, tables[0..2], &br, r, dnd[0..1], 16, out) catch {
            fail("partial decode error");
            return;
        };
        var want: [16]f64 = [16]f64{ 0, 0, 1, 3, 2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        checkRow(out[0], want[0..16], "partial packet stops at EOP");
    }

    // --- 5a. do not decode: unused channel is skipped and left zero ---
    {
        // Rebuild the full packet: test 4b rewrote the shared buffer.
        pktClear();
        wcode(1, 0);
        wcode(2, 0);
        wcode(2, 1);
        wcode(1, 0);
        wcode(2, 2);
        wcode(2, 3);
        var r: vs.Residue = makeResidue(&arena, 0, 2, 10, 4);

        var dnd: [2]bool = undefined;
        dnd[0] = false;
        dnd[1] = true;
        var out: [][]f64 = makeOut(&arena, 2, 16);
        var br: vs.BitReader = vs.brInit(pkt[0..nb]);
        res.decodeResidue(&arena, tables[0..2], &br, r, dnd[0..2], 16, out) catch {
            fail("dnd decode error");
            return;
        };
        var want0: [16]f64 = [16]f64{ 0, 0, 1, 3, 2, 4, 5, 7, 6, 8, 0, 0, 0, 0, 0, 0 };
        var want1: [16]f64 = [16]f64{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        checkRow(out[0], want0[0..16], "dnd ch0 decoded");
        checkRow(out[1], want1[0..16], "dnd ch1 zero");
    }

    // --- 5b. type 2 all 'do not decode': consumes no bits, stays zero ---
    {
        var r: vs.Residue = makeResidue(&arena, 2, 0, 8, 4);
        var dnd: [2]bool = undefined;
        dnd[0] = true;
        dnd[1] = true;
        var out: [][]f64 = makeOut(&arena, 2, 4);
        var empty: [1]u8 = [1]u8{0};
        var br: vs.BitReader = vs.brInit(empty[0..0]);
        res.decodeResidue(&arena, tables[0..2], &br, r, dnd[0..2], 4, out) catch {
            fail("type2 dnd decode error");
            return;
        };
        if (br.pos != 0) {
            fail("type2 all-dnd consumed bits");
            return;
        }
        var want: [4]f64 = [4]f64{ 0, 0, 0, 0 };
        checkRow(out[0], want[0..4], "type2 all-dnd ch0 zero");
        checkRow(out[1], want[0..4], "type2 all-dnd ch1 zero");
    }

    var ok: []const u8 = "residue_test: PASS type0=exact type1=exact type2=deinterleave eop_empty=zero eop_partial=stop dnd=skip\n";
    std.io.write(ok);
    std.os.exit(0);
}

