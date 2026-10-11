// floor_test.zig — deterministic unit harness for z9play floor.zig (M3 Task 2).
//
// Checks, all under `-fsafe`, exiting 0 on success / 1 on the first failure:
//   1. table: the 256-entry floor1_inverse_dB_table spot-checks against the
//      Vorbis I spec 10.1 values (indices 0, 20, 46, 80, 127, 128) and is
//      strictly increasing across the whole table.
//   2. crafted floor 1: a hand-built Floor (multiplier 2, rangebits 4, one
//      dimension-1 partition class with one subclass book) plus a hand-built
//      packet decodes to the exact interpolated curve. The expected integer Y
//      at every x is derived by hand from spec 9.2.7's render_line (Y0=20,
//      Y1=80, anchor Y2=46 at x=8, n=20), and the anchors are also checked
//      against the spec's absolute table values, so the check is not circular.
//      The curve is asserted monotone non-decreasing.
//   3. zero floor: the nonzero flag clear -> returns false and zeroes the
//      output.
//   4. floor 0: a parsed floor-0 setup is rejected with error.UnsupportedFloor.
//   5. fixture smoke: the first usable floor of a committed stereo fixture
//      decodes to a positive curve in (0,1] whose length is the spectral
//      length (block size / 2), bit-identically on a re-run.
//
// The crafted expected Y values below were derived independently by hand from
// the spec's integer render_line:
//   segment (0,20)->(8,46): dy=26 adx=8 base=3 sy=4 ady=2 ->
//     x=0..7 -> 20,23,26,29,33,36,39,42
//   segment (8,46)->(16,80): dy=34 adx=8 base=4 sy=5 ady=2 ->
//     x=8..15 -> 46,50,54,58,63,67,71,75
//   tail (16,80)..(20,80): x=16..19 -> 80.
//
// Build/run from the repo root (binding seed recipe):
//   mkdir -p out
//   timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o out \
//       examples/z98/z9play/tests/floor_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog

const std = @import("std");
const filemod = @import("std_file");
const ogg = @import("../ogg.zig");
const vi = @import("../vorbis_info.zig");
const vs = @import("../vorbis_setup.zig");
const cbk = @import("../codebook.zig");
const flr = @import("../floor.zig");

var arena_buf: [4 * 1024 * 1024]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "floor_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn absF(x: f64) f64 {
    if (x < 0.0) return -x;
    return x;
}

fn checkNear(got: f64, want: f64, tol: f64, msg: []const u8) void {
    if (absF(got - want) > tol) fail(msg);
}

fn ilog(x: u32) u32 {
    var n: u32 = 0;
    var v: u32 = x;
    while (v > 0) : (v = v >> 1) {
        n += 1;
    }
    return n;
}

// LSB-first packet writer for the crafted vector.
var pkt: [64]u8 = undefined;
var bp: usize = 0;

fn pktClear() void {
    var i: usize = 0;
    while (i < 64) : (i += 1) pkt[i] = 0;
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

var empty_pkt: [1]u8 = [1]u8{0};

// True when decodeFloor rejects `f` with error.UnsupportedFloor.
fn floor0Rejected(arena: *std.arena.Arena, tables: []const cbk.DecodeTable, f: vs.Floor, out: []f64) bool {
    var br: vs.BitReader = vs.brInit(empty_pkt[0..1]);
    var v: bool = flr.decodeFloor(arena, tables, &br, f, out) catch |err| return (err == error.UnsupportedFloor);
    _ = v;
    return false;
}

// Reassemble/parse `path`, then decode channel 0's floor for EVERY audio packet
// from the CORRECT bit offset. The Vorbis audio packet begins with a 1-bit
// packet-type flag (0 = audio, spec 4.3.1), then ilog(mode_count-1) mode bits,
// then (long windows only) two window-shape bits, and only then the floor data.
// The expected mode / spectral length / nonzero values are taken from an
// independent python3 LSB-first probe of this fixture: all 88 audio packets
// have nonzero=1; packet 3 is mode 0 (spec_len 128) and packets 4.. are mode 1
// (spec_len 1024). A misaligned offset reads a different nonzero bit and fails.
// Returns true when every audio packet decoded to a valid, used floor.
fn checkFixtureFloor(path: []const u8) bool {
    var arena = std.arena.init(arena_buf[0..]);
    var data: []u8 = filemod.readAll(&arena, path) catch {
        fail("cannot read fixture");
        return false;
    };
    var packets: []ogg.Packet = ogg.reassemble(&arena, data) catch {
        fail("reassemble failed");
        return false;
    };
    if (packets.len < 4) {
        fail("no audio packets");
        return false;
    }
    var id: vi.IdHeader = vi.parseId(packets[0].bytes) catch {
        fail("cannot parse identification header");
        return false;
    };
    var setup: vs.Setup = vs.parseSetup(&arena, packets[2].bytes, @intCast(u32, id.channels)) catch {
        fail("parseSetup failed");
        return false;
    };
    if (setup.codebooks.len == 0) {
        fail("no codebooks");
        return false;
    }

    var raw: [*]u8 = std.arena.alloc(&arena, setup.codebooks.len * @sizeOf(cbk.DecodeTable)) catch {
        fail("table array alloc failed");
        return false;
    };
    var tables: []cbk.DecodeTable = @ptrCast([*]cbk.DecodeTable, raw)[0..setup.codebooks.len];
    var c: usize = 0;
    while (c < setup.codebooks.len) : (c += 1) {
        tables[c] = cbk.buildDecodeTable(&arena, setup.codebooks[c]) catch {
            fail("buildDecodeTable failed");
            return false;
        };
    }

    if (setup.modes.len == 0) {
        fail("no modes");
        return false;
    }
    var mode_bits: u32 = ilog(@intCast(u32, setup.modes.len - 1));

    var audio_count: usize = 0;
    var p: usize = 3;
    while (p < packets.len) : (p += 1) {
        var br: vs.BitReader = vs.brInit(packets[p].bytes);

        // spec 4.3.1: 1-bit packet type, then mode number.
        var ptype: u32 = vs.brRead(&br, 1) catch 0;
        if (ptype != 0) {
            fail("fixture: audio packet type != 0");
            return false;
        }
        var mode: u32 = vs.brRead(&br, mode_bits) catch 0;
        if (mode >= setup.modes.len) {
            fail("fixture: mode number out of range");
            return false;
        }
        // Independent probe alignment: pkt3 mode 0, all later packets mode 1.
        if (p == 3) {
            if (mode != 0) {
                fail("fixture: pkt3 mode != 0");
                return false;
            }
        } else {
            if (mode != 1) {
                fail("fixture: pkt>=4 mode != 1");
                return false;
            }
        }

        var mo: vs.Mode = setup.modes[@intCast(usize, mode)];
        if (mo.blockflag) {
            // spec 4.3.1: long windows carry previous/next window-shape bits
            // before the floor data.
            _ = vs.brRead(&br, 1) catch 0;
            _ = vs.brRead(&br, 1) catch 0;
        }

        // Floor for channel 0: submap mux[0] (0 when there is a single submap).
        var mp: vs.Mapping = setup.mappings[@intCast(usize, mo.mapping)];
        var sub: u32 = 0;
        if (mp.mux.len > 0) sub = @intCast(u32, mp.mux[0]);
        var fidx: u32 = mp.submap_floor[@intCast(usize, sub)];
        var f: vs.Floor = setup.floors[@intCast(usize, fidx)];

        var bs_exp: u8 = id.blocksize_0;
        if (mo.blockflag) bs_exp = id.blocksize_1;
        var sh: u32 = @intCast(u32, bs_exp);
        var spec_len: u32 = (@intCast(u32, 1) << sh) >> 1;
        if (p == 3) {
            if (spec_len != 128) {
                fail("fixture: pkt3 spec_len != 128");
                return false;
            }
        } else {
            if (spec_len != 1024) {
                fail("fixture: pkt>=4 spec_len != 1024");
                return false;
            }
        }

        var out: [4096]f64 = undefined;
        var used: bool = flr.decodeFloor1(&arena, tables[0..], &br, f, out[0..@intCast(usize, spec_len)]) catch {
            fail("fixture: floor decode error");
            return false;
        };
        if (!used) {
            fail("fixture: floor unexpectedly unused (misaligned offset?)");
            return false;
        }

        var q: usize = 0;
        while (q < @intCast(usize, spec_len)) : (q += 1) {
            if (out[q] <= 0.0) {
                fail("floor curve nonpositive");
                return false;
            }
            if (out[q] > 1.0) {
                fail("floor curve exceeds 1.0");
                return false;
            }
        }

        // Determinism: re-decode from the same correct offset.
        var br2: vs.BitReader = vs.brInit(packets[p].bytes);
        _ = vs.brRead(&br2, 1) catch 0;
        _ = vs.brRead(&br2, mode_bits) catch 0;
        if (mo.blockflag) {
            _ = vs.brRead(&br2, 1) catch 0;
            _ = vs.brRead(&br2, 1) catch 0;
        }
        var out2: [4096]f64 = undefined;
        var used2: bool = flr.decodeFloor1(&arena, tables[0..], &br2, f, out2[0..@intCast(usize, spec_len)]) catch {
            fail("second decode error");
            return false;
        };
        if (!used2) {
            fail("determinism: used flag mismatch");
            return false;
        }
        q = 0;
        while (q < @intCast(usize, spec_len)) : (q += 1) {
            if (out[q] != out2[q]) {
                fail("floor decode not deterministic");
                return false;
            }
        }
        audio_count += 1;
    }

    if (audio_count != packets.len - 3) {
        fail("fixture: not every audio packet decoded");
        return false;
    }
    return true;
}


pub fn main() void {
    var arena = std.arena.init(arena_buf[0..]);

    // --- 1. table spot-checks (spec 10.1) + strict monotonicity ---
    checkNear(flr.FLOOR1_INVERSE_DB_TABLE[0], 1.0649863e-07, 0.0, "table[0] mismatch");
    checkNear(flr.FLOOR1_INVERSE_DB_TABLE[20], 3.7516214e-07, 0.0, "table[20] mismatch");
    checkNear(flr.FLOOR1_INVERSE_DB_TABLE[46], 1.9282195e-06, 0.0, "table[46] mismatch");
    checkNear(flr.FLOOR1_INVERSE_DB_TABLE[80], 1.6400004e-05, 0.0, "table[80] mismatch");
    checkNear(flr.FLOOR1_INVERSE_DB_TABLE[127], 0.00031622787, 0.0, "table[127] mismatch");
    checkNear(flr.FLOOR1_INVERSE_DB_TABLE[128], 0.00033677814, 0.0, "table[128] mismatch");
    checkNear(flr.FLOOR1_INVERSE_DB_TABLE[255], 1.0, 0.0, "table[255] mismatch");
    var ti: usize = 1;
    while (ti < 256) : (ti += 1) {
        if (flr.FLOOR1_INVERSE_DB_TABLE[ti] <= flr.FLOOR1_INVERSE_DB_TABLE[ti - 1]) {
            fail("table not strictly increasing");
            return;
        }
    }

    // --- 2. crafted floor 1 ---
    // A 4-entry, all-length-2 codebook: canonical codewords 0,1,2,3, so the
    // 2-bit MSb-first codeword 11 selects entry 3.
    var lens_raw: [*]u8 = std.arena.alloc(&arena, 4) catch {
        fail("alloc failed");
        return;
    };
    var lens: []u8 = lens_raw[0..4];
    var li: usize = 0;
    while (li < 4) : (li += 1) lens[li] = 2;
    var mul_raw: [*]u8 = std.arena.alloc(&arena, 0) catch {
        fail("alloc failed");
        return;
    };
    var mul: []u32 = @ptrCast([*]u32, mul_raw)[0..0];
    var cb: vs.Codebook = vs.Codebook{
        .dimensions = 1,
        .entries = 4,
        .ordered = false,
        .sparse = false,
        .lengths = lens,
        .lookup_type = 0,
        .value_bits = 0,
        .sequence_p = false,
        .min_bits = 0,
        .delta_bits = 0,
        .lookup_values = 0,
        .multiplicands = mul,
    };
    var dt: cbk.DecodeTable = cbk.buildDecodeTable(&arena, cb) catch {
        fail("crafted buildDecodeTable failed");
        return;
    };
    var tables: [1]cbk.DecodeTable = undefined;
    tables[0] = dt;

    var pc_raw: [*]u8 = std.arena.alloc(&arena, 1) catch {
        fail("alloc failed");
        return;
    };
    var pc: []u8 = pc_raw[0..1];
    pc[0] = 0;
    var cd_raw: [*]u8 = std.arena.alloc(&arena, 1) catch {
        fail("alloc failed");
        return;
    };
    var cd: []u8 = cd_raw[0..1];
    cd[0] = 1;
    var cs_raw: [*]u8 = std.arena.alloc(&arena, 1) catch {
        fail("alloc failed");
        return;
    };
    var cs: []u8 = cs_raw[0..1];
    cs[0] = 0;
    var cm_raw: [*]u8 = std.arena.alloc(&arena, 1) catch {
        fail("alloc failed");
        return;
    };
    var cm: []u8 = cm_raw[0..1];
    cm[0] = 0;
    var sb_raw: [*]u8 = std.arena.alloc(&arena, 8 * @sizeOf(i16)) catch {
        fail("alloc failed");
        return;
    };
    var sb: []i16 = @ptrCast([*]i16, sb_raw)[0..8];
    var sbi: usize = 0;
    while (sbi < 8) : (sbi += 1) sb[sbi] = -1;
    sb[0] = 0;
    var xl_raw: [*]u8 = std.arena.alloc(&arena, 3 * @sizeOf(u32)) catch {
        fail("alloc failed");
        return;
    };
    var xl: []u32 = @ptrCast([*]u32, xl_raw)[0..3];
    xl[0] = 0;
    xl[1] = 16;
    xl[2] = 8;
    var e_raw: [*]u8 = std.arena.alloc(&arena, 0) catch {
        fail("alloc failed");
        return;
    };
    var e: []u8 = e_raw[0..0];
    var f: vs.Floor = vs.Floor{
        .floor_type = 1,
        .order = 0,
        .rate = 0,
        .bark_map_size = 0,
        .amplitude_bits = 0,
        .amplitude_offset = 0,
        .floor0_book_count = 0,
        .floor0_books = e,
        .partition_count = 1,
        .partition_class = pc,
        .class_dimensions = cd,
        .class_subclasses = cs,
        .class_masterbooks = cm,
        .subclass_books = sb,
        .multiplier = 2,
        .rangebits = 4,
        .x_list = xl,
    };

    pktClear();
    wbits(1, 1); // nonzero
    wbits(7, 10); // Y[0]
    wbits(7, 40); // Y[1]
    wbits(2, 3); // subclass codeword -> entry 3
    var nb: usize = (bp + 7) / 8;
    var br: vs.BitReader = vs.brInit(pkt[0..nb]);
    var out: [20]f64 = undefined;
    var used: bool = flr.decodeFloor1(&arena, tables[0..], &br, f, out[0..20]) catch {
        fail("crafted decode returned an error");
        return;
    };
    if (!used) {
        fail("crafted floor reported unused");
        return;
    }
    var want_y: [20]u32 = [20]u32{ 20, 23, 26, 29, 33, 36, 39, 42, 46, 50, 54, 58, 63, 67, 71, 75, 80, 80, 80, 80 };
    var x: usize = 0;
    while (x < 20) : (x += 1) {
        checkNear(out[x], flr.FLOOR1_INVERSE_DB_TABLE[@intCast(usize, want_y[x])], 0.0, "crafted curve mismatch");
    }
    checkNear(out[0], 3.7516214e-07, 0.0, "crafted out[0] mismatch");
    checkNear(out[8], 1.9282195e-06, 0.0, "crafted out[8] mismatch");
    checkNear(out[16], 1.6400004e-05, 0.0, "crafted out[16] mismatch");
    checkNear(out[19], 1.6400004e-05, 0.0, "crafted tail mismatch");
    x = 1;
    while (x < 20) : (x += 1) {
        if (out[x] < out[x - 1]) {
            fail("crafted curve not monotone");
            return;
        }
    }

    // --- 3. zero floor (nonzero flag clear) ---
    pktClear();
    wbits(1, 0);
    var brz: vs.BitReader = vs.brInit(pkt[0..1]);
    var outz: [20]f64 = undefined;
    var zi: usize = 0;
    while (zi < 20) : (zi += 1) outz[zi] = 9.0;
    var usedz: bool = flr.decodeFloor1(&arena, tables[0..], &brz, f, outz[0..20]) catch {
        fail("zero-floor decode returned an error");
        return;
    };
    if (usedz) {
        fail("zero floor reported used");
        return;
    }
    zi = 0;
    while (zi < 20) : (zi += 1) {
        if (outz[zi] != 0.0) {
            fail("zero floor did not zero the curve");
            return;
        }
    }

    // --- 4. floor 0 -> error.UnsupportedFloor ---
    // The synthetic floor-0 setup packet is the same one pinned in
    // setup_test.zig (emitted by an independent python3 bit-writer).
    var p_floor0: []const u8 = "\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x01\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x80\x02\x32\x00\x64\x00\xe3\x20\x00\x00\x00\x00\x80\x00\x00\x00\x01\x00\x00\x01\x00\x80\x00\x00\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40";
    var s0: vs.Setup = vs.parseSetup(&arena, p_floor0, 1) catch {
        fail("floor0 parseSetup failed");
        return;
    };
    if (s0.floors.len != 1) {
        fail("floor0: floor count != 1");
        return;
    }
    if (s0.floors[0].floor_type != 0) {
        fail("floor0: type != 0");
        return;
    }
    var out0: [8]f64 = undefined;
    if (!floor0Rejected(&arena, tables[0..], s0.floors[0], out0[0..8])) {
        fail("floor 0 was not rejected with UnsupportedFloor");
        return;
    }

    // --- 5. fixture smoke: a real stream's floor decodes to a valid envelope ---
    var f_stereo: []const u8 = "examples/z98/z9play/testdata/sine_stereo_44100.ogg";
    if (!checkFixtureFloor(f_stereo)) {
        fail("fixture: no nonzero floor decoded");
        return;
    }

    var ok: []const u8 = "floor_test: PASS table=spec+monotone crafted=exact+monotone zerofloor=ok floor0=unsupported fixture=curve\n";
    std.io.write(ok);
    std.os.exit(0);
}
