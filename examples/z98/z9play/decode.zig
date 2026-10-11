// decode.zig — Vorbis audio packet -> interleaved signed-16-bit PCM (z9play M3
// Task 4).
//
// This is the top of the decode layer: it consumes one audio packet and emits
// finished PCM frames, wiring together the pieces built by M1/M3:
//   vorbis_info.zig  identification header (blocksize exponents, channels)
//   vorbis_setup.zig setup header (codebooks/floors/residues/mappings/modes)
//   codebook.zig     Huffman decode tables + VQ vector unpack
//   floor.zig        floor1 curve decode
//   residue.zig      residue type 0/1/2 decode
//   dsp.zig          window slope, inverse MDCT, overlap-add
//
// Packet decode follows Vorbis I spec section 4.3 exactly:
//   4.3.1 packet type, mode, blocksize, window-shape bits
//   4.3.2 floor curve per channel (channel order)
//   4.3.3 nonzero-vector propagate (coupling dirties the unused list)
//   4.3.4 residue decode per submap (submap order)
//   4.3.5 inverse coupling (square-polar -> Cartesian), descending step order
//   4.3.6 floor/residue dot product (per channel)
//   4.3.7 inverse MDCT
//   4.3.8 window + overlap-add with the previous block
//
// Window selection (spec 4.3.1/4.3.3): a short block (mode.blockflag clear) is
// always the symmetric short window. A long block reads previous/next window
// flags; a clear flag makes that half a "hybrid" slope lapping a short block,
// so the long window has flat regions at its ends. The asymmetric window is
// assembled from dsp.windowSlope() (the left slope) and the mirror of a slope
// (the right slope) rather than calling dsp.window(), which only produces the
// symmetric equal-size case.
//
// Transform scale: dsp.imdct is the raw UNNORMALIZED inverse MDCT
// (out[i] = sum_k X[k] cos((pi/2n)(2i+1+n/2)(2k+1))). libvorbis carries its
// 4/n factor in mdct_forward (the analysis), and its mdct_backward -- the
// decoder transform that produced the golden -- is exactly this raw inverse.
// The decoder's effective scale is therefore unity, and the 4/n cancels
// against libvorbis's forward normalization. (A 4/n factor applied here would
// scale by 1/128 for a 256 block and 1/2048 for a 2048 block, so a single
// constant cannot absorb the error -- and indeed the gate's max |delta| = 1
// with unity scale confirms it.)
//
// Overlap-add (spec 4.3.8): the previous block's windowed right half and the
// current block's windowed left half lap at the "3/4 point of the previous
// aligned with the 1/4 point of the current". With previous size pn and current
// size n, the returned range is current-local indices
//     [(n-pn)/4, n/2), length (pn+n)/4,
// and out[t] = current[start+t] (when 0 <= start+t < n) + prev_tail[t] (when
// t < pn/2), where prev_tail holds the previous block's windowed second half.
// The first block returns no frames; it only primes prev_tail.
//
// Output is interleaved signed-16-bit, converted exactly like libvorbisfile:
// clamp to [-1,1], val = floor(x*32768 + 0.5), saturate to [-32768, 32767].
//
// Pure Z98: free functions, no generics/anytype/@Type, strict @intCast, no
// @cImport, no switch (if/else only). Every string literal is written through a
// typed `var` (see AGENTS.md X.5).

const std = @import("std");
const vi = @import("vorbis_info.zig");
const vs = @import("vorbis_setup.zig");
const cbk = @import("codebook.zig");
const dsp = @import("dsp.zig");
const flr = @import("floor.zig");
const res = @import("residue.zig");

// Packet decode errors. BadPacket is a non-audio packet or an out-of-range mode
// number; BadVersion is a malformed/unsupported setup relationship;
// UnsupportedFloor is a floor-0 stream (v1 scope); Truncated is a packet that
// ends before the mandatory header fields; OutOfMemory is an exhausted arena.
pub const DecodeError = error{ BadPacket, BadVersion, UnsupportedFloor, Truncated, OutOfMemory };

// Persistent decoder state across packets: the built codebook decode tables,
// the identification header's block sizes, and the per-channel overlap tail.
// All buffers are arena-owned and sized once, so a long stream does not grow
// the arena through this struct. `prev_n == 0` marks "no previous block yet"
// (the priming frame). `tables` holds the setup-order decode tables the floor
// and residue decoders index by codebook number.
pub const DecoderState = struct {
    channels: u8,
    blocksize_0: u32,
    blocksize_1: u32,
    max_n: u32,
    prev_n: u32,
    tail: [][]f64,
    floors: [][]f64,
    residue: [][]f64,
    blocks: [][]f64,
    bundle: [][]f64,
    no_residue: []bool,
    dnd: []bool,
    tables: []cbk.DecodeTable,
    spectrum: []f64,
    imdct_out: []f64,
    win: []f64,
    slope: []f64,
};

// Correctly-rounded IEEE-754 double pi (0x1.921fb54442d18p+1), matching
// dsp.zig; the lexer's decimal-float parser is not guaranteed correctly
// rounded.
const PI_BITS: u64 = 0x400921FB54442D18;

fn b2d(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

// ilog (spec 9.2.1): number of bits needed to represent x (0 -> 0). Used to
// size the mode field.
fn ilog(x: u32) u32 {
    var n: u32 = 0;
    var v: u32 = x;
    while (v > 0) : (v = v >> 1) {
        n += 1;
    }
    return n;
}

// Unnormalized inverse MDCT, identical in value to dsp.imdct:
//   out[i] = sum_{k=0}^{n/2-1} X[k] cos( (pi/(2n)) (2i+1+n/2) (2k+1) ).
// dsp.imdct evaluates that directly, needing O(n^2/2) std.math.cos calls; at
// -O0 the pure-Z98 cos makes a 2-second stream take minutes. Here each output
// row is evaluated with a per-row angle recurrence (c_k = cos(theta (2k+1)),
// advanced by an orthogonal rotation of 2 theta), which needs O(n) trig calls
// per block. The rotation drifts only ~1e-13, far below the 2-LSB gate.
fn imdctFast(n: u32, spectra: []const f64, out: []f64) void {
    var half: u32 = n / 2;
    var nf: f64 = @intToFloat(f64, n);
    var scale: f64 = b2d(PI_BITS) / (2.0 * nf);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var theta: f64 = scale * @intToFloat(f64, 2 * i + 1 + half);
        var c: f64 = std.math.cos(theta);
        var s: f64 = std.math.sin(theta);
        var c2: f64 = c * c - s * s;
        var s2: f64 = 2.0 * c * s;
        var sum: f64 = 0.0;
        var k: u32 = 0;
        while (k < half) : (k += 1) {
            sum = sum + spectra[@intCast(usize, k)] * c;
            var nc: f64 = c * c2 - s * s2;
            var ns: f64 = s * c2 + c * s2;
            c = nc;
            s = ns;
        }
        out[@intCast(usize, i)] = sum;
    }
}

// Allocate `ch` f64 rows of length `len` from `arena`. Used for the per-channel
// working vectors and the overlap tails.
fn allocRows(arena: *std.arena.Arena, ch: usize, len: u32) DecodeError![][]f64 {
    var raw: [*]u8 = std.arena.alloc(arena, ch * @sizeOf([]f64)) catch return error.OutOfMemory;
    var rows: [][]f64 = @ptrCast([*][]f64, raw)[0..ch];
    var i: usize = 0;
    while (i < ch) : (i += 1) {
        var r: [*]u8 = std.arena.alloc(arena, @intCast(usize, len) * @sizeOf(f64)) catch return error.OutOfMemory;
        rows[i] = @ptrCast([*]f64, r)[0..@intCast(usize, len)];
    }
    return rows;
}

fn allocF64(arena: *std.arena.Arena, len: u32) DecodeError![]f64 {
    var raw: [*]u8 = std.arena.alloc(arena, @intCast(usize, len) * @sizeOf(f64)) catch return error.OutOfMemory;
    return @ptrCast([*]f64, raw)[0..@intCast(usize, len)];
}

fn allocBool(arena: *std.arena.Arena, len: usize) DecodeError![]bool {
    var raw: [*]u8 = std.arena.alloc(arena, len) catch return error.OutOfMemory;
    return @ptrCast([*]bool, raw)[0..len];
}

// Build every codebook decode table once. `setup` (and the arena it lives in)
// must outlive the returned state because the tables alias the parsed codebook
// lengths and multiplicands.
pub fn initDecoderState(arena: *std.arena.Arena, setup: vs.Setup, channels: u8, bs0_exp: u8, bs1_exp: u8) DecodeError!DecoderState {
    if (channels == 0) return error.BadVersion;
    var n0: u32 = @intCast(u32, 1) << @intCast(u32, bs0_exp);
    var n1: u32 = @intCast(u32, 1) << @intCast(u32, bs1_exp);
    var max_n: u32 = n0;
    if (n1 > max_n) max_n = n1;
    var spec_cap: u32 = max_n / 2;
    var ch: usize = @intCast(usize, channels);

    var cnt: usize = setup.codebooks.len;
    var t_raw: [*]u8 = std.arena.alloc(arena, cnt * @sizeOf(cbk.DecodeTable)) catch return error.OutOfMemory;
    var tables: []cbk.DecodeTable = @ptrCast([*]cbk.DecodeTable, t_raw)[0..cnt];
    var c: usize = 0;
    while (c < cnt) : (c += 1) {
        tables[c] = cbk.buildDecodeTable(arena, setup.codebooks[c]) catch |e| {
            if (e == error.OutOfMemory) return error.OutOfMemory;
            return error.BadVersion;
        };
    }

    var tail: [][]f64 = try allocRows(arena, ch, spec_cap);
    var floors: [][]f64 = try allocRows(arena, ch, spec_cap);
    var residue: [][]f64 = try allocRows(arena, ch, spec_cap);
    var blocks: [][]f64 = try allocRows(arena, ch, max_n);

    var b_raw: [*]u8 = std.arena.alloc(arena, ch * @sizeOf([]f64)) catch return error.OutOfMemory;
    var bundle: [][]f64 = @ptrCast([*][]f64, b_raw)[0..ch];

    var no_residue: []bool = try allocBool(arena, ch);
    var dnd: []bool = try allocBool(arena, ch);
    var spectrum: []f64 = try allocF64(arena, spec_cap);
    var imdct_out: []f64 = try allocF64(arena, max_n);
    var win: []f64 = try allocF64(arena, max_n);
    var slope: []f64 = try allocF64(arena, spec_cap);

    return DecoderState{
        .channels = channels,
        .blocksize_0 = n0,
        .blocksize_1 = n1,
        .max_n = max_n,
        .prev_n = 0,
        .tail = tail,
        .floors = floors,
        .residue = residue,
        .blocks = blocks,
        .bundle = bundle,
        .no_residue = no_residue,
        .dnd = dnd,
        .tables = tables,
        .spectrum = spectrum,
        .imdct_out = imdct_out,
        .win = win,
        .slope = slope,
    };
}

fn fillRange(buf: []f64, from: u32, to: u32, v: f64) void {
    var i: u32 = from;
    while (i < to) : (i += 1) {
        buf[@intCast(usize, i)] = v;
    }
}

// Assemble the current block's window (spec 4.3.1/4.3.3). `bs0` is the short
// block size; a long block (`blockflag`) with a clear previous/next window flag
// gets a hybrid half that laps a short block, placing the short slope against
// the block centre and flat regions toward the ends. `win` has length n, and
// `slope` is scratch of length >= n/2.
fn buildWindow(n: u32, bs0: u32, blockflag: bool, prev_wf: u32, next_wf: u32, win: []f64, slope: []f64) void {
    var center: u32 = n / 2;

    var l_start: u32 = 0;
    var l_end: u32 = center;
    var l_n: u32 = n / 2;
    if (blockflag and prev_wf == 0) {
        l_start = n / 4 - bs0 / 4;
        l_end = n / 4 + bs0 / 4;
        l_n = bs0 / 2;
    }

    var r_start: u32 = center;
    var r_end: u32 = n;
    var r_n: u32 = n / 2;
    if (blockflag and next_wf == 0) {
        r_start = n * 3 / 4 - bs0 / 4;
        r_end = n * 3 / 4 + bs0 / 4;
        r_n = bs0 / 2;
    }

    fillRange(win, 0, l_start, 0.0);
    dsp.windowSlope(l_n, slope[0..@intCast(usize, l_n)]);
    var i: u32 = 0;
    while (i < l_n) : (i += 1) {
        win[@intCast(usize, l_start + i)] = slope[@intCast(usize, i)];
    }
    fillRange(win, l_end, r_start, 1.0);
    dsp.windowSlope(r_n, slope[0..@intCast(usize, r_n)]);
    i = 0;
    while (i < r_n) : (i += 1) {
        win[@intCast(usize, r_end - 1 - i)] = slope[@intCast(usize, i)];
    }
    fillRange(win, r_end, n, 0.0);
}

// Convert one sample to s16 exactly as libvorbisfile (_vorbis_ftoi):
// clamp to [-1,1], val = floor(x*32768 + 0.5), saturate. Z98 has no floor, so
// the truncating @intCast to i32 is corrected for negatives.
fn toS16(v: f64) i16 {
    var x: f64 = v;
    if (x != x) x = 0.0;
    if (x > 1.0) x = 1.0;
    if (x < -1.0) x = -1.0;
    var t: f64 = x * 32768.0 + 0.5;
    var n: i32 = @intCast(i32, t);
    if (t < 0.0) {
        var nf: f64 = @intToFloat(f64, n);
        if (nf > t) n = n - 1;
    }
    if (n > 32767) n = 32767;
    if (n < -32768) n = -32768;
    return @intCast(i16, n);
}

// Decode one Vorbis audio packet into finished interleaved s16 frames written
// to `pcm_out` (which must hold at least frames*channels samples). Returns the
// number of frames (samples per channel) produced, which is zero for the
// priming packet. `state` carries the codebook tables, block sizes and the
// previous block's overlap tail across calls; `setup` is the parsed setup
// header the state's tables were built from.
pub fn decodePacket(arena: *std.arena.Arena, setup: vs.Setup, state: *DecoderState, packet: []const u8, pcm_out: []i16) DecodeError!usize {
    var ch: usize = @intCast(usize, state.channels);
    var bits: vs.BitReader = vs.brInit(packet);

    // spec 4.3.1: packet type + mode number (+ window flags for long blocks).
    var ptype: u32 = vs.brRead(&bits, 1) catch return error.Truncated;
    if (ptype != 0) return error.BadPacket;

    var mode_count: u32 = @intCast(u32, setup.modes.len);
    if (mode_count == 0) return error.BadVersion;
    var mode_bits: u32 = ilog(mode_count - 1);
    var mode_num: u32 = vs.brRead(&bits, mode_bits) catch return error.Truncated;
    if (mode_num >= mode_count) return error.BadPacket;
    var mode: vs.Mode = setup.modes[@intCast(usize, mode_num)];
    if (@intCast(u32, mode.mapping) >= @intCast(u32, setup.mappings.len)) return error.BadVersion;
    var mapping: vs.Mapping = setup.mappings[@intCast(usize, mode.mapping)];

    var n: u32 = state.blocksize_0;
    if (mode.blockflag) n = state.blocksize_1;
    var half: usize = @intCast(usize, n / 2);
    var nus: usize = @intCast(usize, n);

    var prev_wf: u32 = 1;
    var next_wf: u32 = 1;
    if (mode.blockflag) {
        prev_wf = vs.brRead(&bits, 1) catch return error.Truncated;
        next_wf = vs.brRead(&bits, 1) catch return error.Truncated;
    }

    // spec 4.3.2: floor curve for each channel (channel order). A floor-0
    // stream is a clean UnsupportedFloor; an end-of-packet during floor decode
    // surfaces as `used == false` and a zeroed curve (silence for the channel).
    var i: usize = 0;
    while (i < ch) : (i += 1) {
        var sub: u32 = 0;
        if (mapping.mux.len > 0) {
            if (i >= mapping.mux.len) return error.BadVersion;
            sub = @intCast(u32, mapping.mux[i]);
        }
        if (sub >= @intCast(u32, mapping.submap_floor.len)) return error.BadVersion;
        var fidx: u32 = @intCast(u32, mapping.submap_floor[@intCast(usize, sub)]);
        if (fidx >= @intCast(u32, setup.floors.len)) return error.BadVersion;
        var f: vs.Floor = setup.floors[@intCast(usize, fidx)];
        var used: bool = flr.decodeFloor(arena, state.tables, &bits, f, state.floors[i][0..half]) catch |e| {
            if (e == error.UnsupportedFloor) return error.UnsupportedFloor;
            return error.BadVersion;
        };
        state.no_residue[i] = !used;
    }

    // spec 4.3.3: coupling dirties the unused list -- if either channel of a
    // coupled pair is used, both must have their residue decoded.
    var cs: u32 = 0;
    while (cs < mapping.coupling_steps) : (cs += 1) {
        if (@intCast(usize, cs) >= mapping.coupling_magnitude.len) return error.BadVersion;
        if (@intCast(usize, cs) >= mapping.coupling_angle.len) return error.BadVersion;
        var m0: usize = @intCast(usize, mapping.coupling_magnitude[@intCast(usize, cs)]);
        var a0: usize = @intCast(usize, mapping.coupling_angle[@intCast(usize, cs)]);
        if (m0 >= ch or a0 >= ch) return error.BadVersion;
        if (!state.no_residue[m0] or !state.no_residue[a0]) {
            state.no_residue[m0] = false;
            state.no_residue[a0] = false;
        }
    }

    // spec 4.3.4: residue decode per submap (submap order). The affected
    // channels are gathered in channel order; decodeResidue zeroes and fills
    // the gathered rows in place.
    var sub_i: u32 = 0;
    while (sub_i < mapping.submaps) : (sub_i += 1) {
        var count: usize = 0;
        i = 0;
        while (i < ch) : (i += 1) {
            var s2: u32 = 0;
            if (mapping.mux.len > 0) s2 = @intCast(u32, mapping.mux[i]);
            if (s2 == sub_i) {
                state.bundle[count] = state.residue[i];
                state.dnd[count] = state.no_residue[i];
                count += 1;
            }
        }
        if (sub_i >= @intCast(u32, mapping.submap_residue.len)) return error.BadVersion;
        var ridx: u32 = @intCast(u32, mapping.submap_residue[@intCast(usize, sub_i)]);
        if (ridx >= @intCast(u32, setup.residues.len)) return error.BadVersion;
        var r: vs.Residue = setup.residues[@intCast(usize, ridx)];
        res.decodeResidue(arena, state.tables, &bits, r, state.dnd[0..count], n / 2, state.bundle[0..count]) catch |e| {
            if (e == error.OutOfMemory) return error.OutOfMemory;
            return error.BadVersion;
        };
    }

    // spec 4.3.5: inverse coupling, descending step order (square polar ->
    // Cartesian).
    var ci: u32 = mapping.coupling_steps;
    while (ci > 0) {
        ci -= 1;
        var m: usize = @intCast(usize, mapping.coupling_magnitude[@intCast(usize, ci)]);
        var a: usize = @intCast(usize, mapping.coupling_angle[@intCast(usize, ci)]);
        var k: usize = 0;
        while (k < half) : (k += 1) {
            var M: f64 = state.residue[m][k];
            var A: f64 = state.residue[a][k];
            if (M > 0.0) {
                if (A > 0.0) {
                    state.residue[m][k] = M;
                    state.residue[a][k] = M - A;
                } else {
                    state.residue[a][k] = M;
                    state.residue[m][k] = M + A;
                }
            } else {
                if (A > 0.0) {
                    state.residue[m][k] = M;
                    state.residue[a][k] = M + A;
                } else {
                    state.residue[a][k] = M;
                    state.residue[m][k] = M - A;
                }
            }
        }
    }

    buildWindow(n, state.blocksize_0, mode.blockflag, prev_wf, next_wf, state.win[0..nus], state.slope);

    // spec 4.3.6/4.3.7/4.3.8: per channel, dot the floor curve with the
    // residue, inverse-MDCT, apply the window, then overlap-add. The transform
    // scale is unity: libvorbis puts its 4/n factor in mdct_forward (the
    // analysis), while mdct_backward -- the decoder's transform, and the one
    // the golden was produced with -- is the raw unnormalized inverse, exactly
    // dsp.imdct/imdctFast. (The PR-correct synthesis for an *unnormalized*
    // forward is (4/n)*raw, which is why the 4/n cancels.)
    var scale: f64 = 1.0;
    i = 0;
    while (i < ch) : (i += 1) {
        var k: usize = 0;
        while (k < half) : (k += 1) {
            state.spectrum[k] = state.floors[i][k] * state.residue[i][k];
        }
        imdctFast(n, state.spectrum[0..half], state.imdct_out[0..nus]);
        var p: usize = 0;
        while (p < nus) : (p += 1) {
            state.blocks[i][p] = state.imdct_out[p] * scale * state.win[p];
        }
    }

    // Priming frame: no output, only seed the overlap tail.
    if (state.prev_n == 0) {
        i = 0;
        while (i < ch) : (i += 1) {
            var t: usize = 0;
            while (t < half) : (t += 1) {
                state.tail[i][t] = state.blocks[i][half + t];
            }
        }
        state.prev_n = n;
        return 0;
    }

    var prev_n: u32 = state.prev_n;
    var diff: i32 = @intCast(i32, n) - @intCast(i32, prev_n);
    var start_i: i32 = diff / 4;
    var length: u32 = (n + prev_n) / 4;
    var frames: usize = @intCast(usize, length);
    if (pcm_out.len < frames * ch) return error.BadVersion;
    var prev_half: usize = @intCast(usize, prev_n / 2);

    var t2: usize = 0;
    while (t2 < frames) : (t2 += 1) {
        var cc: i32 = start_i + @intCast(i32, t2);
        var j: usize = 0;
        while (j < ch) : (j += 1) {
            var v: f64 = 0.0;
            if (cc >= 0 and cc < @intCast(i32, n)) {
                v = v + state.blocks[j][@intCast(usize, cc)];
            }
            if (t2 < prev_half) {
                v = v + state.tail[j][t2];
            }
            pcm_out[t2 * ch + j] = toS16(v);
        }
    }

    i = 0;
    while (i < ch) : (i += 1) {
        var t3: usize = 0;
        while (t3 < half) : (t3 += 1) {
            state.tail[i][t3] = state.blocks[i][half + t3];
        }
    }
    state.prev_n = n;
    return frames;
}
