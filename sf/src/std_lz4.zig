const MFLIMIT: usize = 12;
const LASTLITERALS: usize = 5;
const MINMATCH: usize = 4;

pub fn lz4DecompressBlock(src: []const u8, dst: []u8) !u32 {
    if (src.len == 0) return error.Corrupt;

    var ip: usize = 0;
    var op: usize = 0;
    var had_match: bool = false;
    var last_match_start: usize = 0;
    var final_lit_len: usize = 0;

    while (true) {
        if (ip >= src.len) return error.Corrupt;
        const token: u8 = src[ip];
        ip += 1;

        var lit_len: usize = @intCast(usize, token >> 4);
        if (lit_len == 15) {
            if (lit_len > src.len) return error.Corrupt;
            while (true) {
                if (ip >= src.len) return error.Corrupt;
                const b: u8 = src[ip];
                ip += 1;
                const add: usize = @intCast(usize, b);
                if (add > src.len - lit_len) return error.Corrupt;
                lit_len += add;
                if (b != 255) break;
            }
        }

        if (lit_len > src.len - ip) return error.Corrupt;
        if (lit_len > dst.len - op) return error.OutputTooSmall;

        var li: usize = 0;
        while (li < lit_len) : (li += 1) {
            dst[op + li] = src[ip + li];
        }
        ip += lit_len;
        op += lit_len;

        if (ip == src.len) {
            final_lit_len = lit_len;
            break;
        }

        if (src.len - ip < 2) return error.Corrupt;
        const offset: usize = @intCast(usize, src[ip]) |
            (@intCast(usize, src[ip + 1]) << 8);
        ip += 2;
        if (offset == 0 or offset > op) return error.Corrupt;

        var match_len: usize = @intCast(usize, token & 15);
        if (match_len == 15) {
            while (true) {
                if (ip >= src.len) return error.Corrupt;
                const b: u8 = src[ip];
                ip += 1;
                const add: usize = @intCast(usize, b);
                if (match_len > dst.len or add > dst.len - match_len) {
                    return error.OutputTooSmall;
                }
                match_len += add;
                if (b != 255) break;
            }
        }
        if (match_len > dst.len or MINMATCH > dst.len - match_len) {
            return error.OutputTooSmall;
        }
        match_len += MINMATCH;
        if (match_len > dst.len - op) return error.OutputTooSmall;

        last_match_start = op;
        had_match = true;
        var mi: usize = 0;
        while (mi < match_len) : (mi += 1) {
            dst[op + mi] = dst[op - offset + mi];
        }
        op += match_len;
    }

    if (had_match) {
        if (final_lit_len < LASTLITERALS) return error.Corrupt;
        if (op - last_match_start < MFLIMIT) return error.Corrupt;
    }
    return @intCast(u32, op);
}
