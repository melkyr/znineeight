// floor.zig — Vorbis floor decode (z9play M3 Task 2).
//
// Vorbis I has two floor types. This module implements floor type 1 (the
// piecewise-linear dB floor, spec 7.2) and cleanly rejects floor type 0 with
// error.UnsupportedFloor (v1 of the player has no floor-0 support, per the M3
// plan; a floor-0 stream is a supported stream shape that is simply out of
// scope, so the rejection is a clean error, never a crash or silence).
//
// The floor is a per-channel multiplicative envelope over the spectral
// coefficients of the current frame. `decodeFloor1` reads the packeted floor
// data (nonzero flag, two initial Y values, then per-partition Y values decoded
// through the master/subclass codebooks), unwraps the differenced Y values by
// linear prediction (spec 7.2.4 step 1), and renders the curve (step 2) into
// `out_curve`.
//
// Curve convention consumed by the M3 Task 4 packet decoder:
//   out_curve has length floor1_spectral_length = (current block size) / 2,
//   i.e. the number of spectral coefficients the inverse MDCT consumes
//   (`dsp.imdct(arena, n, spectra, out)` takes `n/2` spectra). Every entry is
//   the linear-domain floor amplitude in (0, 1] (it already includes the
//   floor1_multiplier scaling and the `floor1_inverse_dB_table` lookup), and
//   Task 4 forms the audio spectrum by multiplying the residue vector by it
//   element by element (spec 4.3.3 / "compute floor/residue dot product").
//   A `false` return (or a floor-0 rejection) means the channel is unused for
//   the frame; `out_curve` is then zeroed, so the caller may either skip the
//   channel or multiply by zero.
//
// Pure Z98: free functions, no generics/anytype/@Type, strict @intCast, no
// @cImport, no switch. The integer line/point algorithms are ported exactly
// from the Vorbis I specification (9.2.4 / 9.2.5 / 9.2.6 / 9.2.7) and the
// reference implementation (xiph/vorbis lib/floor1.c); the 256-entry
// floor1_inverse_dB_table is included verbatim from spec 10.1.

const std = @import("std");
const vs = @import("vorbis_setup.zig");
const cbk = @import("codebook.zig");

// Floor decode can fail only in these ways: a floor-0 configuration is
// unsupported in v1; a structurally impossible floor-1 setup (an index past
// the codebook list, a malformed partition list, a short/absent x list) is
// BadVersion. End-of-packet reads are nominal (spec 7.2.3) and surface as a
// `false` (unused) return, matching libvorbis's eop path, not as an error.
pub const FloorError = error{ UnsupportedFloor, BadVersion };

// floor1_inverse_dB_table (Vorbis I spec 10.1; libvorbis
// `FLOOR1_fromdB_LOOKUP`). Index [y] with the integer Y amplitude in 0..255;
// the result is the linear-domain amplitude for that dB step.
pub const FLOOR1_INVERSE_DB_TABLE: [256]f64 = [256]f64{
    1.0649863e-07, 1.1341951e-07, 1.2079015e-07, 1.2863978e-07,
    1.3699951e-07, 1.4590251e-07, 1.5538408e-07, 1.6548181e-07,
    1.7623575e-07, 1.8768855e-07, 1.9988561e-07, 2.128753e-07,
    2.2670913e-07, 2.4144197e-07, 2.5713223e-07, 2.7384213e-07,
    2.9163793e-07, 3.1059021e-07, 3.3077411e-07, 3.5226968e-07,
    3.7516214e-07, 3.9954229e-07, 4.2550680e-07, 4.5315863e-07,
    4.8260743e-07, 5.1396998e-07, 5.4737065e-07, 5.8294187e-07,
    6.2082472e-07, 6.6116941e-07, 7.0413592e-07, 7.4989464e-07,
    7.9862701e-07, 8.5052630e-07, 9.0579828e-07, 9.6466216e-07,
    1.0273513e-06, 1.0941144e-06, 1.1652161e-06, 1.2409384e-06,
    1.3215816e-06, 1.4074654e-06, 1.4989305e-06, 1.5963394e-06,
    1.7000785e-06, 1.8105592e-06, 1.9282195e-06, 2.0535261e-06,
    2.1869758e-06, 2.3290978e-06, 2.4804557e-06, 2.6416497e-06,
    2.8133190e-06, 2.9961443e-06, 3.1908506e-06, 3.3982101e-06,
    3.6190449e-06, 3.8542308e-06, 4.1047004e-06, 4.3714470e-06,
    4.6555282e-06, 4.9580707e-06, 5.2802740e-06, 5.6234160e-06,
    5.9888572e-06, 6.3780469e-06, 6.7925283e-06, 7.2339451e-06,
    7.7040476e-06, 8.2047000e-06, 8.7378876e-06, 9.3057248e-06,
    9.9104632e-06, 1.0554501e-05, 1.1240392e-05, 1.1970856e-05,
    1.2748789e-05, 1.3577278e-05, 1.4459606e-05, 1.5399272e-05,
    1.6400004e-05, 1.7465768e-05, 1.8600792e-05, 1.9809576e-05,
    2.1096914e-05, 2.2467911e-05, 2.3928002e-05, 2.5482978e-05,
    2.7139006e-05, 2.8902651e-05, 3.0780908e-05, 3.2781225e-05,
    3.4911534e-05, 3.7180282e-05, 3.9596466e-05, 4.2169667e-05,
    4.4910090e-05, 4.7828601e-05, 5.0936773e-05, 5.4246931e-05,
    5.7772202e-05, 6.1526565e-05, 6.5524908e-05, 6.9783085e-05,
    7.4317983e-05, 7.9147585e-05, 8.4291040e-05, 8.9768747e-05,
    9.5602426e-05, 0.00010181521, 0.00010843174, 0.00011547824,
    0.00012298267, 0.00013097477, 0.00013948625, 0.00014855085,
    0.00015820453, 0.00016848555, 0.00017943469, 0.00019109536,
    0.00020351382, 0.00021673929, 0.00023082423, 0.00024582449,
    0.00026179955, 0.00027881276, 0.00029693158, 0.00031622787,
    0.00033677814, 0.00035866388, 0.00038197188, 0.00040679456,
    0.00043323036, 0.00046138411, 0.00049136745, 0.00052329927,
    0.00055730621, 0.00059352311, 0.00063209358, 0.00067317058,
    0.00071691700, 0.00076350630, 0.00081312324, 0.00086596457,
    0.00092223983, 0.00098217216, 0.0010459992, 0.0011139742,
    0.0011863665, 0.0012634633, 0.0013455702, 0.0014330129,
    0.0015261382, 0.0016253153, 0.0017309374, 0.0018434235,
    0.0019632195, 0.0020908006, 0.0022266726, 0.0023713743,
    0.0025254795, 0.0026895994, 0.0028643847, 0.0030505286,
    0.0032487691, 0.0034598925, 0.0036847358, 0.0039241906,
    0.0041792066, 0.0044507950, 0.0047400328, 0.0050480668,
    0.0053761186, 0.0057254891, 0.0060975636, 0.0064938176,
    0.0069158225, 0.0073652516, 0.0078438871, 0.0083536271,
    0.0088964928, 0.009474637, 0.010090352, 0.010746080,
    0.011444421, 0.012188144, 0.012980198, 0.013823725,
    0.014722068, 0.015678791, 0.016697687, 0.017782797,
    0.018938423, 0.020169149, 0.021479854, 0.022875735,
    0.024362330, 0.025945531, 0.027631618, 0.029427276,
    0.031339626, 0.033376252, 0.035545228, 0.037855157,
    0.040315199, 0.042935108, 0.045725273, 0.048696758,
    0.051861348, 0.055231591, 0.058820850, 0.062643361,
    0.066714279, 0.071049749, 0.075666962, 0.080584227,
    0.085821044, 0.091398179, 0.097337747, 0.10366330,
    0.11039993, 0.11757434, 0.12521498, 0.13335215,
    0.14201813, 0.15124727, 0.16107617, 0.17154380,
    0.18269168, 0.19456402, 0.20720788, 0.22067342,
    0.23501402, 0.25028656, 0.26655159, 0.28387361,
    0.30232132, 0.32196786, 0.34289114, 0.36517414,
    0.38890521, 0.41417847, 0.44109412, 0.46975890,
    0.50028648, 0.53279791, 0.56742212, 0.60429640,
    0.64356699, 0.68538959, 0.72993007, 0.77736504,
    0.82788260, 0.88168307, 0.9389798, 1.0,
};

// ilog(x): 0 -> 0, 1 -> 1, 2/3 -> 2, 4..7 -> 3, ... (spec 9.2.1). The same
// helper the setup parser uses for the ordered-codebook run counts.
fn ilog(x: u32) u32 {
    var n: u32 = 0;
    var v: u32 = x;
    while (v > 0) : (v = v >> 1) {
        n += 1;
    }
    return n;
}

// range = vector { 256, 128, 86, 64 } element (multiplier - 1) (spec 7.2.3);
// multiplier is 1..4 from setup.
fn quantRange(mult: u8) u32 {
    if (mult == 1) return 256;
    if (mult == 2) return 128;
    if (mult == 3) return 86;
    return 64;
}

fn iabs(x: i32) i32 {
    if (x < 0) return -x;
    return x;
}

// Clamp an integer Y amplitude into the floor1_inverse_dB_table index range.
fn clampIndex(v: i32) u32 {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return @intCast(u32, v);
}

fn zeroCurve(out: []f64) void {
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        out[i] = 0.0;
    }
}

// low_neighbor(v, p) (spec 9.2.4): the position n < p with the greatest
// x_list[n] still less than x_list[p]. Points 0 and 1 (x = 0 and 1<<rangebits)
// always bound every explicit point, so a neighbor exists.
fn lowNeighbor(floor: vs.Floor, p: u32) u32 {
    var currentx: u32 = floor.x_list[@intCast(usize, p)];
    var lo: u32 = 0;
    var lx: u32 = 0;
    var j: u32 = 0;
    while (j < p) : (j += 1) {
        var x: u32 = floor.x_list[@intCast(usize, j)];
        if (x > lx and x < currentx) {
            lo = j;
            lx = x;
        }
    }
    return lo;
}

// high_neighbor(v, p) (spec 9.2.5): the position n < p with the lowest
// x_list[n] still greater than x_list[p].
fn highNeighbor(floor: vs.Floor, p: u32) u32 {
    var currentx: u32 = floor.x_list[@intCast(usize, p)];
    var hi: u32 = 1;
    var hx: u32 = floor.x_list[1];
    var j: u32 = 0;
    while (j < p) : (j += 1) {
        var x: u32 = floor.x_list[@intCast(usize, j)];
        if (x < hx and x > currentx) {
            hi = j;
            hx = x;
        }
    }
    return hi;
}

// render_point(x0, y0, x1, y1, X) (spec 9.2.6): the integer Y at position X on
// the line from (x0,y0) to (x1,y1). y0/y1 may carry the 0x8000 predicted flag,
// which is masked off. Integer division truncates toward zero (spec 9.2.7).
fn renderPoint(x0: u32, y0: i32, x1: u32, y1: i32, x: u32) i32 {
    var a: i32 = y0 & 0x7fff;
    var b: i32 = y1 & 0x7fff;
    var dy: i32 = b - a;
    var adx: i32 = @intCast(i32, x1) - @intCast(i32, x0);
    var ady: i32 = iabs(dy);
    var err: i32 = ady * (@intCast(i32, x) - @intCast(i32, x0));
    var off: i32 = err / adx;
    if (dy < 0) return a - off;
    return a + off;
}

// render_line(x0, y0, x1, y1, v) (spec 9.2.7): fill v[x0 .. min(x1,n)) with the
// integer line, then substitute each integer through floor1_inverse_dB_table.
// The curve is written straight into the f64 output, so the table lookup is
// applied at each sample; the resulting values are identical to rendering
// integers and mapping them afterwards. x1 > x0 is guaranteed by the caller.
fn renderLine(n: usize, x0: u32, x1: u32, y0: u32, y1: u32, out: []f64) void {
    if (x1 <= x0) return;
    var dy: i32 = @intCast(i32, y1) - @intCast(i32, y0);
    var adx: i32 = @intCast(i32, x1) - @intCast(i32, x0);
    var ady: i32 = iabs(dy);
    var base: i32 = dy / adx;
    var sy: i32 = base + 1;
    if (dy < 0) sy = base - 1;
    var x: i32 = @intCast(i32, x0);
    var y: i32 = @intCast(i32, y0);
    var err: i32 = 0;
    ady = ady - iabs(base * adx);

    var lim: usize = n;
    if (lim > @intCast(usize, x1)) lim = @intCast(usize, x1);

    if (@intCast(usize, x) < lim) {
        out[@intCast(usize, x)] = FLOOR1_INVERSE_DB_TABLE[clampIndex(y)];
    }
    x = x + 1;
    while (@intCast(usize, x) < lim) : (x += 1) {
        err = err + ady;
        if (err >= adx) {
            err = err - adx;
            y = y + sy;
        } else {
            y = y + base;
        }
        out[@intCast(usize, x)] = FLOOR1_INVERSE_DB_TABLE[clampIndex(y)];
    }
}

// Decode a floor type 1 configuration from `bits` and render its curve into
// `out_curve`. Returns true when the floor is used, false when it is unused
// (the nonzero flag was clear, or an end-of-packet condition occurred during
// curve decode, spec 7.2.3); in both false cases `out_curve` is zeroed.
// `floor.floor_type` must be 1. `tables[k]` is the built decode table for
// codebook k, in setup order (vorbis_setup.Setup.codebooks / codebook.zig).
pub fn decodeFloor1(arena: *std.arena.Arena, tables: []const cbk.DecodeTable, bits: *vs.BitReader, floor: vs.Floor, out_curve: []f64) FloorError!bool {
    // No allocation is needed: the floor1 x_list is capped at 65 entries and
    // all working state fits in fixed blocks. `arena` is accepted for signature
    // stability with the other decoder stages (Task 4).
    _ = arena;

    if (floor.floor_type != 1) return error.UnsupportedFloor;

    var nonzero: u32 = vs.brRead(bits, 1) catch 0;
    if (nonzero == 0) {
        zeroCurve(out_curve);
        return false;
    }

    var posts: usize = floor.x_list.len;
    if (posts < 2 or posts > 65) return error.BadVersion;

    var range: u32 = quantRange(floor.multiplier);
    var ybits: u32 = ilog(range - 1);

    // floor1_Y / floor1_final_Y in one array. Bit 0x8000 is the spec's
    // floor1_step2_flag, inverted: a set flag (an un-decoded/predicted point)
    // is stored as 0x8000 (libvorbis's convention) so it is skipped in step 2.
    var fit: [65]i32 = undefined;
    var z: usize = 0;
    while (z < posts) : (z += 1) fit[z] = 0;

    // An end-of-packet during these reads yields zero bits (spec 2.1.8), which
    // is a nominal read, not the "unused" condition.
    var y0: u32 = vs.brRead(bits, ybits) catch 0;
    var y1: u32 = vs.brRead(bits, ybits) catch 0;
    fit[0] = @intCast(i32, y0);
    fit[1] = @intCast(i32, y1);

    // --- per-partition Y decode (spec 7.2.3) ---
    var j: usize = 2;
    var pi: u32 = 0;
    while (pi < floor.partition_count) : (pi += 1) {
        var cls: usize = @intCast(usize, floor.partition_class[@intCast(usize, pi)]);
        var cdim: u32 = floor.class_dimensions[cls];
        var cbits: u32 = floor.class_subclasses[cls];
        var csub: u32 = @intCast(u32, 1) << cbits;
        var cval: u32 = 0;
        if (cbits > 0) {
            var mk: usize = @intCast(usize, floor.class_masterbooks[cls]);
            if (mk >= tables.len) return error.BadVersion;
            var cv: i32 = cbk.decodeScalar(&tables[mk], bits);
            if (cv < 0) {
                zeroCurve(out_curve);
                return false;
            }
            cval = @intCast(u32, cv);
        }
        var k: u32 = 0;
        while (k < cdim) : (k += 1) {
            var sub: usize = @intCast(usize, cval & (csub - 1));
            cval = cval >> cbits;
            var sbook: i16 = floor.subclass_books[cls * 8 + sub];
            if (j >= posts) return error.BadVersion;
            if (sbook >= 0) {
                var bu: usize = @intCast(usize, sbook);
                if (bu >= tables.len) return error.BadVersion;
                var v: i32 = cbk.decodeScalar(&tables[bu], bits);
                if (v < 0) {
                    zeroCurve(out_curve);
                    return false;
                }
                fit[j] = v;
            } else {
                fit[j] = 0;
            }
            j += 1;
        }
    }

    // --- step 1: amplitude synthesis / unwrap (spec 7.2.4) ---
    var i: usize = 2;
    while (i < posts) : (i += 1) {
        var pu: u32 = @intCast(u32, i);
        var ln: u32 = lowNeighbor(floor, pu);
        var hn: u32 = highNeighbor(floor, pu);
        var predicted: i32 = renderPoint(floor.x_list[ln], fit[@intCast(usize, ln)], floor.x_list[hn], fit[@intCast(usize, hn)], floor.x_list[i]);
        var hiroom: i32 = @intCast(i32, range) - predicted;
        var loroom: i32 = predicted;
        var mn: i32 = hiroom;
        if (loroom < mn) mn = loroom;
        var room: i32 = mn * 2;
        var val: i32 = fit[i];
        if (val != 0) {
            fit[@intCast(usize, ln)] = fit[@intCast(usize, ln)] & 0x7fff;
            fit[@intCast(usize, hn)] = fit[@intCast(usize, hn)] & 0x7fff;
            if (val >= room) {
                if (hiroom > loroom) {
                    val = val - loroom + predicted;
                } else {
                    val = predicted - val + hiroom - 1;
                }
            } else {
                if ((val & 1) != 0) {
                    val = predicted - ((val + 1) / 2);
                } else {
                    val = predicted + (val / 2);
                }
            }
            fit[i] = val & 0x7fff;
        } else {
            fit[i] = predicted | 0x8000;
        }
    }

    // --- step 2: curve synthesis (spec 7.2.4). Sort X order (selection sort;
    // X values are unique) and render contiguous segments between anchor
    // points, then the constant tail out to n. ---
    var order: [65]u32 = undefined;
    i = 0;
    while (i < posts) : (i += 1) order[i] = @intCast(u32, i);
    i = 0;
    while (i < posts) : (i += 1) {
        var m: usize = i;
        var k2: usize = i + 1;
        while (k2 < posts) : (k2 += 1) {
            if (floor.x_list[@intCast(usize, order[k2])] < floor.x_list[@intCast(usize, order[m])]) m = k2;
        }
        var tmp: u32 = order[i];
        order[i] = order[m];
        order[m] = tmp;
    }

    var n: usize = out_curve.len;
    var hx: u32 = 0;
    var lx: u32 = 0;
    var ly: u32 = clampIndex(fit[0] * @intCast(i32, floor.multiplier));
    i = 1;
    while (i < posts) : (i += 1) {
        var cu: u32 = order[i];
        var yv: i32 = fit[@intCast(usize, cu)];
        if ((yv & 0x8000) == 0) {
            hx = floor.x_list[@intCast(usize, cu)];
            var hy: u32 = clampIndex(yv * @intCast(i32, floor.multiplier));
            renderLine(n, lx, hx, ly, hy, out_curve);
            lx = hx;
            ly = hy;
        }
    }
    if (@intCast(usize, hx) < n) {
        renderLine(n, hx, @intCast(u32, n), ly, ly, out_curve);
    }

    return true;
}

// Decode a floor of either type. Type 1 is delegated to `decodeFloor1`; type 0
// is rejected with error.UnsupportedFloor (v1 scope, M3 plan Task 2).
pub fn decodeFloor(arena: *std.arena.Arena, tables: []const cbk.DecodeTable, bits: *vs.BitReader, floor: vs.Floor, out_curve: []f64) FloorError!bool {
    if (floor.floor_type == 0) return error.UnsupportedFloor;
    if (floor.floor_type != 1) return error.BadVersion;
    return decodeFloor1(arena, tables, bits, floor, out_curve);
}
