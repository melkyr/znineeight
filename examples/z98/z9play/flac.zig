// flac.zig — native FLAC stream + frame decode to interleaved signed-16 PCM
// (z9play M8 Task 2).
//
// Pure Z98: free functions only (no method syntax), no generics/`anytype`, no
// switch (if/else), strict `@intCast`, string literals via typed `var`.
//
// Scope (M8 T2): the FLAC subset needed to decode the generated stereo
// 44.1 kHz/16-bit fixture:
//   - `fLaC` marker + metadata blocks, with STREAMINFO parsed into min/max
//     block size, sample rate, channels, bits per sample and total samples;
//   - frame header sync/block size/sample rate/channels/bits/CRC-8;
//   - subframes constant / verbatim / fixed / LPC;
//   - Rice (partitioned) residuals, including the escape/raw form;
//   - channel decorrelation independent / left-side / right-side / mid-side;
//   - interleaved signed-16 PCM, returned 0 at end of stream.
//
// CRC-8 over the frame header is verified. The frame CRC-16 is skipped (the
// plan explicitly allows skip/verify); decoding is sequential because each
// frame's subframes determine its own length.
//
// The decoder owns one arena-sized scratch block (`max_block * channels`
// i64 samples) allocated once by `open`, so a long stream does not grow the
// arena per frame. `decode` returns the frame count of the next frame.

const std = @import("std");

pub const FlacError = error{
    BadStream,
    BadFrame,
    Unsupported,
    Truncated,
    BadBuffer,
    OutOfMemory,
};

// Parsed frame/stream metadata plus the sequential frame cursor and scratch.
pub const FlacDecoder = struct {
    data: []const u8,
    arena: *std.arena.Arena,
    pos: usize, // byte offset of the next frame
    sample_rate: u32,
    channels: u8,
    bits_per_sample: u8,
    min_block: u16,
    max_block: u16,
    max_frames: u32,
    total_frames: u64,
    samples: []i64, // channels * max_block (channel-major)
};

// MSB-first bit reader over one frame. `byte_pos` is relative to the slice.
const BitReader = struct {
    data: []const u8,
    byte_pos: usize,
    bit_pos: u8, // 0..7, next bit within data[byte_pos]
};

fn readBit(br: *BitReader) FlacError!u1 {
    if (br.byte_pos >= br.data.len) return error.Truncated;
    var b: u8 = br.data[br.byte_pos];
    var sh: u3 = @intCast(u3, 7 - br.bit_pos);
    var bit: u1 = @intCast(u1, (b >> sh) & 1);
    if (br.bit_pos == 7) {
        br.bit_pos = 0;
        br.byte_pos += 1;
    } else {
        br.bit_pos += 1;
    }
    return bit;
}

fn readBits(br: *BitReader, n: u32) FlacError!u64 {
    if (n == 0) return 0;
    var v: u64 = 0;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var bit: u1 = try readBit(br);
        v = (v << 1) | @intCast(u64, bit);
    }
    return v;
}

// Read `n` bits as a two's-complement signed value (n in 0..=63).
fn readSigned(br: *BitReader, n: u32) FlacError!i64 {
    if (n == 0) return 0;
    var uv: u64 = try readBits(br, n);
    var signbit: u64 = @intCast(u64, 1) << @intCast(u64, n - 1);
    if ((uv & signbit) == 0) return @intCast(i64, uv);
    var mask: u64 = (@intCast(u64, 1) << @intCast(u64, n)) - 1;
    var extended: u64 = uv | (~mask);
    return @bitCast(i64, extended);
}

// Unary coding: count zero bits before the terminating one.
fn readUnary(br: *BitReader) FlacError!u32 {
    var q: u32 = 0;
    while (true) {
        var bit: u1 = try readBit(br);
        if (bit == 1) return q;
        q += 1;
        if (q > 0x00ffffff) return error.BadFrame;
    }
    return 0;
}

fn alignByte(br: *BitReader) void {
    if (br.bit_pos != 0) {
        br.bit_pos = 0;
        br.byte_pos += 1;
    }
}

fn crc8(data: []const u8) u8 {
    var crc: u8 = 0;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        crc = crc ^ data[i];
        var j: u8 = 0;
        while (j < 8) : (j += 1) {
            if ((crc & 0x80) != 0) {
                crc = (crc *% 2) ^ 0x07;
            } else {
                crc = crc *% 2;
            }
        }
    }
    return crc;
}

// UTF-8-style coded frame/sample number (FLAC's optional header field).
fn readUtf8Number(br: *BitReader) FlacError!u64 {
    var b0: u8 = @intCast(u8, try readBits(br, 8));
    var extra: u32 = 0;
    var val: u64 = 0;
    if ((b0 & 0x80) == 0) {
        val = b0;
    } else if ((b0 & 0xe0) == 0xc0) {
        extra = 1;
        val = b0 & 0x1f;
    } else if ((b0 & 0xf0) == 0xe0) {
        extra = 2;
        val = b0 & 0x0f;
    } else if ((b0 & 0xf8) == 0xf0) {
        extra = 3;
        val = b0 & 0x07;
    } else if ((b0 & 0xfc) == 0xf8) {
        extra = 4;
        val = b0 & 0x03;
    } else if ((b0 & 0xfe) == 0xfc) {
        extra = 5;
        val = b0 & 0x01;
    } else if (b0 == 0xfe) {
        extra = 6;
        val = 0;
    } else {
        return error.BadFrame;
    }
    var i: u32 = 0;
    while (i < extra) : (i += 1) {
        var b: u8 = @intCast(u8, try readBits(br, 8));
        if ((b & 0xc0) != 0x80) return error.BadFrame;
        val = (val << 6) | @intCast(u64, b & 0x3f);
    }
    return val;
}

// Partitioned residual decode. Writes `block - order` residual values into
// `dst[order..block]`; the caller applies the predictor afterwards.
fn decodeResidual(br: *BitReader, dst: []i64, block: u32, order: u32) FlacError!void {
    var method: u32 = @intCast(u32, try readBits(br, 2));
    if (method > 1) return error.Unsupported;
    var pbits: u32 = 4;
    if (method == 1) pbits = 5;
    var param_max: u32 = (@intCast(u32, 1) << @intCast(u32, pbits)) - 1;

    var porder: u32 = @intCast(u32, try readBits(br, 4));
    var parts: u32 = @intCast(u32, 1) << @intCast(u32, porder);
    if ((block % parts) != 0) return error.BadFrame;
    var part_len: u32 = block / parts;
    if (part_len < order and porder != 0) return error.BadFrame;

    var idx: u32 = order;
    var p: u32 = 0;
    while (p < parts) : (p += 1) {
        var n: u32 = part_len;
        if (p == 0) {
            if (part_len < order) return error.BadFrame;
            n = part_len - order;
        }
        var param: u32 = @intCast(u32, try readBits(br, pbits));
        if (param == param_max) {
            var raw_bits: u32 = @intCast(u32, try readBits(br, 5));
            var k: u32 = 0;
            while (k < n) : (k += 1) {
                var v: i64 = try readSigned(br, raw_bits);
                dst[@intCast(usize, idx)] = v;
                idx += 1;
            }
        } else {
            var k: u32 = 0;
            while (k < n) : (k += 1) {
                var q: u32 = try readUnary(br);
                var rem: u64 = try readBits(br, param);
                var uv: u64 = (@intCast(u64, q) << @intCast(u64, param)) | rem;
                var sign: i64 = -@intCast(i64, uv & 1);
                var v: i64 = @intCast(i64, uv >> 1);
                if (sign != 0) v = ~v;
                dst[@intCast(usize, idx)] = v;
                idx += 1;
            }
        }
    }
    if (idx != block) return error.BadFrame;
}

// Decode one subframe into `dst[0..block]`. `bps` is the frame bit depth for
// this channel (side channels get +1). Wasted-bit low zeros are restored at
// the end, after prediction.
fn decodeSubframe(br: *BitReader, dst: []i64, block: u32, bps: u32) FlacError!void {
    if (try readBit(br) != 0) return error.BadFrame;
    var stype: u32 = @intCast(u32, try readBits(br, 6));
    var wasted: u32 = 0;
    if (try readBit(br) == 1) {
        wasted = try readUnary(br) + 1;
    }
    if (wasted >= bps) return error.BadFrame;
    var ebits: u32 = bps - wasted;

    if (stype == 0) {
        var v: i64 = try readSigned(br, ebits);
        var i: u32 = 0;
        while (i < block) : (i += 1) dst[@intCast(usize, i)] = v;
    } else if (stype == 1) {
        var i: u32 = 0;
        while (i < block) : (i += 1) {
            dst[@intCast(usize, i)] = try readSigned(br, ebits);
        }
    } else if (stype >= 8 and stype <= 12) {
        var order: u32 = stype - 8;
        if (order > block) return error.BadFrame;
        var i: u32 = 0;
        while (i < order) : (i += 1) {
            dst[@intCast(usize, i)] = try readSigned(br, ebits);
        }
        try decodeResidual(br, dst, block, order);
        if (order == 1) {
            i = order;
            while (i < block) : (i += 1) {
                var ui: usize = @intCast(usize, i);
                dst[ui] = dst[ui] + dst[ui - 1];
            }
        } else if (order == 2) {
            i = order;
            while (i < block) : (i += 1) {
                var ui: usize = @intCast(usize, i);
                dst[ui] = dst[ui] + 2 * dst[ui - 1] - dst[ui - 2];
            }
        } else if (order == 3) {
            i = order;
            while (i < block) : (i += 1) {
                var ui: usize = @intCast(usize, i);
                dst[ui] = dst[ui] + 3 * dst[ui - 1] - 3 * dst[ui - 2] + dst[ui - 3];
            }
        } else if (order == 4) {
            i = order;
            while (i < block) : (i += 1) {
                var ui: usize = @intCast(usize, i);
                dst[ui] = dst[ui] + 4 * dst[ui - 1] - 6 * dst[ui - 2] + 4 * dst[ui - 3] - dst[ui - 4];
            }
        }
    } else if (stype >= 32) {
        var order: u32 = (stype - 32) + 1;
        if (order > block or order > 32) return error.BadFrame;
        var i: u32 = 0;
        while (i < order) : (i += 1) {
            dst[@intCast(usize, i)] = try readSigned(br, ebits);
        }
        var precision: u32 = @intCast(u32, try readBits(br, 4));
        if (precision == 15) return error.BadFrame;
        precision += 1;
        var shift: i64 = try readSigned(br, 5);
        var coefs: [32]i64 = undefined;
        i = 0;
        while (i < order) : (i += 1) {
            coefs[@intCast(usize, i)] = try readSigned(br, precision);
        }
        try decodeResidual(br, dst, block, order);
        i = order;
        while (i < block) : (i += 1) {
            var ui: usize = @intCast(usize, i);
            var sum: i64 = 0;
            var j: u32 = 0;
            while (j < order) : (j += 1) {
                sum += coefs[@intCast(usize, j)] * dst[ui - 1 - @intCast(usize, j)];
            }
            if (shift >= 0) {
                sum = sum >> @intCast(i64, shift);
            } else {
                sum = sum << @intCast(i64, -shift);
            }
            dst[ui] = dst[ui] + sum;
        }
    } else {
        return error.Unsupported;
    }

    if (wasted > 0) {
        var i2: u32 = 0;
        while (i2 < block) : (i2 += 1) {
            var ui: usize = @intCast(usize, i2);
            dst[ui] = dst[ui] << @intCast(i64, wasted);
        }
    }
}

fn blockSize(code: u32, br: *BitReader) FlacError!u32 {
    if (code == 0) return error.BadFrame;
    if (code == 1) return 192;
    if (code >= 2 and code <= 5) {
        return @intCast(u32, 576) << @intCast(u32, code - 2);
    }
    if (code == 6) return @intCast(u32, try readBits(br, 8)) + 1;
    if (code == 7) return @intCast(u32, try readBits(br, 16)) + 1;
    if (code >= 8 and code <= 15) {
        return @intCast(u32, 256) << @intCast(u32, code - 8);
    }
    return error.BadFrame;
}

// Decode the next frame, returning its frame count (0 at end of stream).
fn decodeFrame(d: *FlacDecoder, out: []i16) FlacError!usize {
    if (d.pos >= d.data.len) return 0;

    var hstart: usize = d.pos;
    var br = BitReader{ .data = d.data[hstart..], .byte_pos = 0, .bit_pos = 0 };

    var sync: u32 = @intCast(u32, try readBits(&br, 14));
    if (sync != 0x3ffe) return error.BadFrame;
    if (try readBit(&br) != 0) return error.BadFrame;
    var blocking: u1 = try readBit(&br);
    var bscode: u32 = @intCast(u32, try readBits(&br, 4));
    var srcode: u32 = @intCast(u32, try readBits(&br, 4));
    var chanassign: u32 = @intCast(u32, try readBits(&br, 4));
    var sscode: u32 = @intCast(u32, try readBits(&br, 3));
    if (try readBit(&br) != 0) return error.BadFrame;

    _ = try readUtf8Number(&br);

    var block: u32 = try blockSize(bscode, &br);

    var frame_rate: u32 = d.sample_rate;
    if (srcode == 1) {
        frame_rate = 88200;
    } else if (srcode == 2) {
        frame_rate = 176400;
    } else if (srcode == 3) {
        frame_rate = 192000;
    } else if (srcode == 4) {
        frame_rate = 8000;
    } else if (srcode == 5) {
        frame_rate = 16000;
    } else if (srcode == 6) {
        frame_rate = 22050;
    } else if (srcode == 7) {
        frame_rate = 24000;
    } else if (srcode == 8) {
        frame_rate = 32000;
    } else if (srcode == 9) {
        frame_rate = 44100;
    } else if (srcode == 10) {
        frame_rate = 48000;
    } else if (srcode == 11) {
        frame_rate = 96000;
    } else if (srcode == 12) {
        frame_rate = @intCast(u32, try readBits(&br, 8)) * 1000;
    } else if (srcode == 13) {
        frame_rate = @intCast(u32, try readBits(&br, 16));
    } else if (srcode == 14) {
        frame_rate = @intCast(u32, try readBits(&br, 16)) * 10;
    } else if (srcode == 15) {
        return error.BadFrame;
    }
    if (frame_rate == 0) return error.BadFrame;

    var frame_bps: u32 = d.bits_per_sample;
    if (sscode == 1) {
        frame_bps = 8;
    } else if (sscode == 2) {
        frame_bps = 12;
    } else if (sscode == 4) {
        frame_bps = 16;
    } else if (sscode == 5) {
        frame_bps = 20;
    } else if (sscode == 6) {
        frame_bps = 24;
    } else if (sscode != 0) {
        return error.BadFrame;
    }
    if (frame_bps == 0 or frame_bps > 32) return error.BadFrame;
    _ = blocking;

    var nch: u32 = 0;
    if (chanassign <= 7) {
        nch = chanassign + 1;
    } else if (chanassign >= 8 and chanassign <= 10) {
        nch = 2;
    } else {
        return error.BadFrame;
    }
    if (nch != @intCast(u32, d.channels)) return error.BadFrame;
    if (block > @intCast(u32, d.max_block) or block > @intCast(u32, d.max_frames)) {
        return error.BadFrame;
    }

    if (br.bit_pos != 0) return error.BadFrame;
    var crc_pos: usize = br.byte_pos;
    var stored_crc: u8 = @intCast(u8, try readBits(&br, 8));
    var computed: u8 = crc8(d.data[hstart .. hstart + crc_pos]);
    if (stored_crc != computed) return error.BadFrame;

    var stride: usize = @intCast(usize, d.max_block);
    var ch: u32 = 0;
    while (ch < nch) : (ch += 1) {
        var bps: u32 = frame_bps;
        if (chanassign == 8 and ch == 1) bps += 1; // left-side: side channel
        if (chanassign == 9 and ch == 0) bps += 1; // right-side: side channel
        if (chanassign == 10 and ch == 1) bps += 1; // mid-side: side channel
        if (bps > 33) return error.BadFrame;
        var base: usize = @intCast(usize, ch) * stride;
        var dst: []i64 = d.samples[base .. base + @intCast(usize, block)];
        try decodeSubframe(&br, dst, block, bps);
    }

    // Channel decorrelation (FLAC spec 4.2.1). The side channel is the
    // difference; restore both channels in place.
    if (chanassign == 8) {
        var left: []i64 = d.samples[0..@intCast(usize, block)];
        var side: []i64 = d.samples[stride .. stride + @intCast(usize, block)];
        var i: usize = 0;
        while (i < @intCast(usize, block)) : (i += 1) {
            side[i] = left[i] - side[i];
        }
    } else if (chanassign == 9) {
        var side: []i64 = d.samples[0..@intCast(usize, block)];
        var right: []i64 = d.samples[stride .. stride + @intCast(usize, block)];
        var i: usize = 0;
        while (i < @intCast(usize, block)) : (i += 1) {
            side[i] = side[i] + right[i];
        }
    } else if (chanassign == 10) {
        var mid: []i64 = d.samples[0..@intCast(usize, block)];
        var side: []i64 = d.samples[stride .. stride + @intCast(usize, block)];
        var i: usize = 0;
        while (i < @intCast(usize, block)) : (i += 1) {
            var m: i64 = (mid[i] << 1) | (side[i] & 1);
            mid[i] = (m + side[i]) >> 1;
            side[i] = (m - side[i]) >> 1;
        }
    }

    alignByte(&br);
    _ = try readBits(&br, 16); // frame CRC-16 (skipped, as the plan allows)
    d.pos = hstart + br.byte_pos;

    var nsamples: usize = @intCast(usize, block) * @intCast(usize, nch);
    if (out.len < nsamples) return error.BadBuffer;

    var fi: usize = 0;
    while (fi < @intCast(usize, block)) : (fi += 1) {
        var ci: usize = 0;
        while (ci < @intCast(usize, nch)) : (ci += 1) {
            var v: i64 = d.samples[ci * stride + fi];
            if (frame_bps < 16) {
                v = v << @intCast(i64, 16 - frame_bps);
            } else if (frame_bps > 16) {
                v = v >> @intCast(i64, frame_bps - 16);
            }
            if (v > 32767) v = 32767;
            if (v < -32768) v = -32768;
            out[fi * @intCast(usize, nch) + ci] = @intCast(i16, v);
        }
    }
    return @intCast(usize, block);
}

// Parse `fLaC` + all metadata blocks; require STREAMINFO. Leaves `pos` at the
// first audio frame.
pub fn open(arena: *std.arena.Arena, bytes: []const u8) FlacError!FlacDecoder {
    if (bytes.len < 4) return error.BadStream;
    if (bytes[0] != 'f' or bytes[1] != 'L' or bytes[2] != 'a' or bytes[3] != 'C') {
        return error.BadStream;
    }

    var pos: usize = 4;
    var have_info: bool = false;
    var min_block: u16 = 0;
    var max_block: u16 = 0;
    var sample_rate: u32 = 0;
    var channels: u8 = 0;
    var bits: u8 = 0;
    var total: u64 = 0;

    while (true) {
        if (pos + 4 > bytes.len) return error.Truncated;
        var hdr: u8 = bytes[pos];
        var last: bool = (hdr & 0x80) != 0;
        var mtype: u8 = hdr & 0x7f;
        var mlen: usize = (@intCast(usize, bytes[pos + 1]) << 16) |
            (@intCast(usize, bytes[pos + 2]) << 8) |
            @intCast(usize, bytes[pos + 3]);
        pos += 4;
        if (pos + mlen > bytes.len) return error.Truncated;
        if (mtype == 0) {
            if (mlen < 34) return error.BadStream;
            var b: []const u8 = bytes[pos .. pos + 34];
            min_block = (@intCast(u16, b[0]) << 8) | @intCast(u16, b[1]);
            max_block = (@intCast(u16, b[2]) << 8) | @intCast(u16, b[3]);
            var packbits: u64 = 0;
            var i: usize = 10;
            while (i < 18) : (i += 1) packbits = (packbits << 8) | @intCast(u64, b[i]);
            sample_rate = @intCast(u32, (packbits >> 44) & 0xfffff);
            channels = @intCast(u8, ((packbits >> 41) & 0x7) + 1);
            bits = @intCast(u8, ((packbits >> 36) & 0x1f) + 1);
            total = packbits & 0xfffffffff;
            have_info = true;
        }
        pos += mlen;
        if (last) break;
    }

    if (!have_info) return error.BadStream;
    if (sample_rate == 0 or channels == 0 or channels > 8) return error.BadStream;
    if (bits < 4 or bits > 32) return error.BadStream;
    if (max_block < 16) return error.BadStream;
    if (min_block > max_block) return error.BadStream;

    var ch: usize = @intCast(usize, channels);
    var mb: usize = @intCast(usize, max_block);
    var n: usize = ch * mb;
    var raw: [*]u8 = std.arena.alloc(arena, n * @sizeOf(i64)) catch return error.OutOfMemory;
    var samples: []i64 = @ptrCast([*]i64, raw)[0..n];
    var i2: usize = 0;
    while (i2 < n) : (i2 += 1) samples[i2] = 0;

    return FlacDecoder{
        .data = bytes,
        .arena = arena,
        .pos = pos,
        .sample_rate = sample_rate,
        .channels = channels,
        .bits_per_sample = bits,
        .min_block = min_block,
        .max_block = max_block,
        .max_frames = @intCast(u32, max_block),
        .total_frames = total,
        .samples = samples,
    };
}

// Decode the next frame into `out` (interleaved s16). Returns the number of
// frames written, or 0 at end of stream.
pub fn decode(d: *FlacDecoder, arena: *std.arena.Arena, out: []i16) FlacError!usize {
    _ = arena;
    return decodeFrame(d, out);
}
