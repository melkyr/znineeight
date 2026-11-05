// delta.zig -- Git pack delta reconstruction (the "copy/insert" stream).
//
// A delta payload is
//   src-size  varint
//   tgt-size  varint
//   instruction*
// where an instruction with the high bit set is a COPY (offset/size selected
// by the low seven bits) and an instruction in 1..=127 is an INSERT of that
// many literal bytes.  A zero instruction byte is reserved and rejected.
// There is no delete op.  Every offset/size addition is checked so a hostile
// or truncated stream yields error.Corrupt instead of a 32-bit wrap.

const MAX_U64: u64 = 0xFFFFFFFFFFFFFFFF;

fn readVarint(delta: []const u8, pos: *usize) !u64 {
    var result: u64 = 0;
    var shift: usize = 0;
    while (true) {
        if (pos.* >= delta.len) return error.Corrupt;
        const b: u8 = delta[pos.*];
        pos.* += 1;
        if (shift >= 64) return error.Corrupt;
        const bits: u64 = @intCast(u64, b & 0x7F);
        const sh: u64 = @intCast(u64, shift);
        if (bits > (MAX_U64 >> sh)) return error.Corrupt;
        result |= bits << sh;
        if ((b & 0x80) == 0) return result;
        shift += 7;
    }
    return error.Corrupt;
}

// Decode the two leading size varints without applying anything.  Used by the
// store to allocate the target buffer before calling deltaApply.
pub fn deltaSizes(delta: []const u8, src_len: *usize, tgt_len: *usize) !void {
    var pos: usize = 0;
    const s = try readVarint(delta, &pos);
    const t = try readVarint(delta, &pos);
    if (s > 0xFFFFFFFF) return error.Corrupt;
    if (t > 0xFFFFFFFF) return error.Corrupt;
    src_len.* = @intCast(usize, s);
    tgt_len.* = @intCast(usize, t);
}

pub fn deltaApply(base: []const u8, delta: []const u8, out: []u8) !void {
    var pos: usize = 0;
    const src64 = try readVarint(delta, &pos);
    const tgt64 = try readVarint(delta, &pos);
    if (src64 != @intCast(u64, base.len)) return error.Corrupt;
    if (tgt64 != @intCast(u64, out.len)) return error.Corrupt;

    var op: usize = 0;
    while (pos < delta.len) {
        const cmd: u8 = delta[pos];
        pos += 1;

        if ((cmd & 0x80) != 0) {
            var off32: u32 = 0;
            var size32: u32 = 0;

            if ((cmd & 0x01) != 0) {
                if (pos >= delta.len) return error.Corrupt;
                off32 |= @intCast(u32, delta[pos]);
                pos += 1;
            }
            if ((cmd & 0x02) != 0) {
                if (pos >= delta.len) return error.Corrupt;
                off32 |= @intCast(u32, delta[pos]) << 8;
                pos += 1;
            }
            if ((cmd & 0x04) != 0) {
                if (pos >= delta.len) return error.Corrupt;
                off32 |= @intCast(u32, delta[pos]) << 16;
                pos += 1;
            }
            if ((cmd & 0x08) != 0) {
                if (pos >= delta.len) return error.Corrupt;
                off32 |= @intCast(u32, delta[pos]) << 24;
                pos += 1;
            }
            if ((cmd & 0x10) != 0) {
                if (pos >= delta.len) return error.Corrupt;
                size32 |= @intCast(u32, delta[pos]);
                pos += 1;
            }
            if ((cmd & 0x20) != 0) {
                if (pos >= delta.len) return error.Corrupt;
                size32 |= @intCast(u32, delta[pos]) << 8;
                pos += 1;
            }
            if ((cmd & 0x40) != 0) {
                if (pos >= delta.len) return error.Corrupt;
                size32 |= @intCast(u32, delta[pos]) << 16;
                pos += 1;
            }

            var off64: u64 = @intCast(u64, off32);
            var size64: u64 = @intCast(u64, size32);
            if (size64 == 0) size64 = 0x10000;
            if (off64 > @intCast(u64, base.len)) return error.Corrupt;
            if (size64 > @intCast(u64, base.len) - off64) return error.Corrupt;
            if (@intCast(u64, op) > @intCast(u64, out.len)) return error.Corrupt;
            if (size64 > @intCast(u64, out.len) - @intCast(u64, op)) return error.Corrupt;

            const off: usize = @intCast(usize, off64);
            const size: usize = @intCast(usize, size64);
            var i: usize = 0;
            while (i < size) : (i += 1) {
                out[op + i] = base[off + i];
            }
            op += size;
        } else if (cmd != 0) {
            const n: usize = @intCast(usize, cmd);
            if (pos > delta.len or n > delta.len - pos) return error.Corrupt;
            if (op > out.len or n > out.len - op) return error.Corrupt;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                out[op + i] = delta[pos + i];
            }
            pos += n;
            op += n;
        } else {
            return error.Corrupt;
        }
    }

    if (op != out.len) return error.Corrupt;
}
