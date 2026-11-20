const px = @import("std_gfx_px_core.zig");

pub const Sprite = px.Sprite;

const HEADER_BYTES: usize = 16;
const PALETTE_BYTES: usize = 512;
const DATA_OFFSET: usize = HEADER_BYTES + PALETTE_BYTES;

fn readU16(buf: []const u8, off: usize) u16 {
    return @intCast(u16, buf[off]) | (@intCast(u16, buf[off + 1]) << 8);
}

fn readU32(buf: []const u8, off: usize) u32 {
    return @intCast(u32, buf[off]) |
        (@intCast(u32, buf[off + 1]) << 8) |
        (@intCast(u32, buf[off + 2]) << 16) |
        (@intCast(u32, buf[off + 3]) << 24);
}

pub fn zspDecode(buf: []const u8, out_sprite: *Sprite, out_lut: *[256]u16, pix: []u8, pix_len: *i32) bool {
    if (buf.len < DATA_OFFSET) return false;
    if (buf[0] != 'Z' or buf[1] != 'S' or buf[2] != 'P' or buf[3] != '1') return false;

    const w = readU16(buf, 4);
    const h = readU16(buf, 6);
    const key = buf[8];
    if (readU16(buf, 10) != 0) return false;
    if (readU32(buf, 12) != 0) return false;

    const total32: u32 = @intCast(u32, w) * @intCast(u32, h);
    if (total32 > 2147483647) return false;
    const total: usize = @intCast(usize, total32);
    if (pix.len < total) return false;

    var pos: u32 = 0;
    var i: usize = DATA_OFFSET;
    while (i < buf.len) : (i += 2) {
        if (i + 1 >= buf.len) return false;
        const count = buf[i];
        if (count == 0) return false;
        pos += @intCast(u32, count);
        if (pos > total32) return false;
    }
    if (pos != total32) return false;

    var j: usize = 0;
    while (j < 256) : (j += 1) {
        out_lut[j] = readU16(buf, HEADER_BYTES + j * 2);
    }

    var o: usize = 0;
    i = DATA_OFFSET;
    while (i < buf.len) : (i += 2) {
        const count: usize = @intCast(usize, buf[i]);
        const index = buf[i + 1];
        var n: usize = 0;
        while (n < count) : (n += 1) {
            pix[o] = index;
            o += 1;
        }
    }

    out_sprite.* = Sprite{
        .w = @intCast(u32, w),
        .h = @intCast(u32, h),
        .idx = @ptrCast([*]const u8, pix.ptr),
        .lut = @ptrCast([*]const u16, &out_lut[0]),
        .key = key,
    };
    pix_len.* = @intCast(i32, total32);
    return true;
}

pub fn zspRecolorLut(out: *[256]u16, base: *const [256]u16, from_ramp: u8, to_ramp: u8) void {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        out[i] = base[i];
    }
    if (from_ramp > 15 or to_ramp > 15) return;

    i = 0;
    while (i < 255) : (i += 1) {
        const ramp: u8 = @intCast(u8, i >> 4);
        if (ramp != from_ramp) continue;
        const shade: u8 = @intCast(u8, i & 15);
        var src: usize = @intCast(usize, to_ramp) * 16 + @intCast(usize, shade);
        if (to_ramp == 15 and shade == 15) src = 254;
        out[i] = base[src];
    }
}

pub fn zspCanonicalEncode(pix: []const u8, w: u32, h: u32, out: []u8) usize {
    if (h != 0 and w > 4294967295 / h) return 0;
    const total32: u32 = w * h;
    if (total32 == 0) return 0;
    const total: usize = @intCast(usize, total32);
    if (total > pix.len) return 0;

    var n: usize = 0;
    var i: usize = 0;
    while (i < total) {
        const value = pix[i];
        var j: usize = i + 1;
        while (j < total and pix[j] == value) : (j += 1) {}
        var remain: usize = j - i;
        while (remain > 0) {
            var count: usize = remain;
            if (count > 255) count = 255;
            if (n + 2 > out.len) return 0;
            out[n] = @intCast(u8, count);
            out[n + 1] = value;
            n += 2;
            remain -= count;
        }
        i = j;
    }
    return n;
}
